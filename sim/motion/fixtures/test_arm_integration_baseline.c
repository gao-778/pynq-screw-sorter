#include "arm_motion.h"
#include "arm_bus.h"
#include "fusion_clock.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define DATA 0x1000U
#define IER 0x1004U
#define FCR 0x1008U
#define LCR 0x100CU
#define MCR 0x1010U
#define LSR 0x1014U
#define SCR 0x101CU
#define MOVE_CAPACITY 2048U
#define QUERY_CAPACITY 512U

typedef struct {
    unsigned id, position, duration;
    unsigned background_epoch;
    uint64_t started, transmitted;
} MoveRecord;
typedef struct {
    unsigned id;
    int position;
    uint64_t transmitted, rx_enabled;
} QueryRecord;
typedef struct {
    uint64_t now, tx_end, tx_enabled, tx_start, reply_start;
    unsigned direction, lcr, ier, mcr, scr, dll, dlm;
    unsigned tx_count, reply_size, reply_read, reply_sent;
    unsigned packet_applied, moves, queries, stops, stop_mask;
    unsigned partial_query, partial_count, inject_line_at_move, pending_line_error;
    unsigned empty_query, empty_count;
    unsigned tx_noise_events, tx_noise_id, tx_noise_before_temt, rx_noise;
    unsigned inject_tx_line_query, reply_delay_us;
    unsigned stall_fifo_at_move, stall_fifo_seen, stall_fifo_active;
    unsigned inject_line_query, line_query_count, pending_query_error;
    unsigned sticky_rx_error, forced_line_error, rx_resets;
    unsigned opening_value, groups_done, ticks, idle_ticks;
    unsigned partial_recovery_count;
    unsigned slow_tasks_enabled, slow_task_count;
    unsigned first_stop_background_epoch, last_stop_background_epoch;
    uint64_t next_slow_task, first_stop_started, last_stop_transmitted, stall_fifo_started;
    uint64_t slow_started[2048];
    int position[7], target[7], feedback_delta[7];
    uint64_t reached_at[7];
    uint8_t tx[16], reply[8];
    MoveRecord move[MOVE_CAPACITY];
    QueryRecord query[QUERY_CAPACITY];
} DeviceModel;

static DeviceModel device;
static ArmAction reference[ARM_PLAN_CAPACITY];
static unsigned reference_count;
static unsigned tests;
static VisualPickTarget visual_target={20,100,0.6,0.8,0,1,1000};

static void update_positions(DeviceModel *m)
{
    unsigned id;
    for(id=1;id<=6;++id)
        if(m->reached_at[id] && m->now>=m->reached_at[id]){
            m->position[id]=m->target[id];m->reached_at[id]=0;
        }
}

static void apply_packet(DeviceModel *m)
{
    unsigned i,sum=0,id,command,raw;
    if(m->packet_applied || m->tx_count<6 || m->now<m->tx_end)return;
    assert(m->tx_count==(unsigned)m->tx[3]+3U);
    assert(m->tx[0]==0x55U && m->tx[1]==0x55U);
    for(i=2;i<m->tx_count;++i)sum+=m->tx[i];
    assert((sum&255U)==255U);
    id=m->tx[2];command=m->tx[4];assert(id>=1 && id<=6);
    m->packet_applied=1;
    if(command==1U){
        MoveRecord *r;
        assert(m->moves<MOVE_CAPACITY && m->tx_count==10);
        r=&m->move[m->moves++];r->id=id;
        r->position=m->tx[5]|((unsigned)m->tx[6]<<8);
        r->duration=m->tx[7]|((unsigned)m->tx[8]<<8);
        r->started=m->tx_start;r->transmitted=m->tx_end;
        r->background_epoch=m->idle_ticks;
        assert(arm_position_allowed(id,(int)r->position));
        m->target[id]=(int)r->position;
        if(id==1 && r->position==200)m->target[id]=(int)m->opening_value;
        if(id==1 && r->position==600)m->target[id]=565;
        m->reached_at[id]=m->tx_end+(uint64_t)r->duration*1000U;
    }else if(command==28U){
        QueryRecord *r;
        assert(m->queries<QUERY_CAPACITY && m->tx_count==6);
        r=&m->query[m->queries++];r->id=id;r->transmitted=m->tx_end;
        update_positions(m);
        raw=(unsigned)(m->position[id]+(m->moves?m->feedback_delta[id]:0))&0xffffU;
        r->position=(int16_t)raw;
        m->reply[0]=m->reply[1]=0x55U;m->reply[2]=(uint8_t)id;
        m->reply[3]=5;m->reply[4]=28;m->reply[5]=(uint8_t)raw;
        m->reply[6]=(uint8_t)(raw>>8);sum=0;
        for(i=2;i<7;++i)sum+=m->reply[i];
        m->reply[7]=(uint8_t)~sum;m->reply_size=8;m->reply_read=0;
        if(m->partial_query && m->queries>=m->partial_query && m->partial_count){
            --m->partial_count;m->reply_size=7;
        }
        if(m->empty_query && m->queries>=m->empty_query && m->empty_count){
            --m->empty_count;m->reply_size=0;
        }
        m->reply_start=m->tx_end+m->reply_delay_us;
        if(m->inject_line_query && m->queries>=m->inject_line_query && m->line_query_count){
            --m->line_query_count;m->pending_query_error=0x08U;
        }
    }else if(command==12U){
        assert(m->tx_count==6);
        if(!m->stops){
            m->first_stop_background_epoch=m->idle_ticks;
            m->first_stop_started=m->tx_start;
        }
        m->last_stop_background_epoch=m->idle_ticks;
        m->last_stop_transmitted=m->tx_end;
        ++m->stops;m->stop_mask|=1U<<id;
        m->reached_at[id]=0;
    }else assert(0);  
}

static unsigned available_reply(DeviceModel *m)
{
    uint64_t available;
    if(m->direction!=2U || !m->reply_size || m->now<m->reply_start)return 0;
    available=1U+(m->now-m->reply_start)/87U;
    return available>m->reply_size?m->reply_size:(unsigned)available;
}

static uint32_t read_register(void *user,uintptr_t address)
{
    DeviceModel *m=user;unsigned offset,status;
    assert(m==&device && address>=ARM_BUS_UART_BASE);
    apply_packet(m);update_positions(m);
    offset=(unsigned)(address-ARM_BUS_UART_BASE);
    switch(offset){
    case DATA:
        if(m->lcr&0x80U)return m->dll;
        if(m->rx_noise){m->rx_noise=0;return 0xa5U;}
        assert(m->reply_read<available_reply(m));return m->reply[m->reply_read++];
    case IER:return m->lcr&0x80U?m->dlm:m->ier;
    case LCR:return m->lcr;
    case MCR:return m->mcr;
    case SCR:return m->scr;
    case LSR:
        status=m->now>=m->tx_end?0x60U:0;
        

        if(m->direction==1U && !m->packet_applied && m->tx_count==10U && m->tx[4]==1U &&
           m->moves+1U==m->inject_line_at_move && !m->tx_noise_events){
            ++m->tx_noise_events;m->tx_noise_id=m->tx[2];
            m->tx_noise_before_temt=m->now<m->tx_end;
            m->pending_line_error=0x88U;m->rx_noise=1;
        }
        if(m->direction==1U && !m->packet_applied && m->tx_count==6U && m->tx[4]==28U &&
           m->queries+1U==m->inject_tx_line_query && !m->tx_noise_events){
            ++m->tx_noise_events;m->tx_noise_id=m->tx[2];
            m->tx_noise_before_temt=m->now<m->tx_end;
            m->pending_line_error=0x88U;m->rx_noise=1;
        }
        if(m->direction==1U && !m->tx_count &&
           m->moves+1U==m->stall_fifo_at_move && !m->stall_fifo_seen){
            m->stall_fifo_seen=m->stall_fifo_active=1;
            m->stall_fifo_started=m->now;
        }
        if(m->stall_fifo_active)status&=~0x60U;
        if(m->rx_noise)status|=1U;
        if(m->reply_read<available_reply(m))status|=1U;
        status|=m->pending_line_error|m->sticky_rx_error|m->forced_line_error;
        m->pending_line_error=0;
        return status;
    default:assert(0);return 0;
    }
}

static void write_register(void *user,uintptr_t address,uint32_t value)
{
    DeviceModel *m=user;unsigned offset;
    assert(m==&device);apply_packet(m);
    if(address==ARM_BUS_GPIO_BASE+4U){assert(value==0);return;}
    if(address==ARM_BUS_GPIO_BASE){
        assert(value<3U);
        if(value==0U)m->stall_fifo_active=0;
        if(value==1U){
            assert(m->direction==0);m->tx_enabled=m->now;m->tx_count=0;
            m->packet_applied=0;m->reply_size=m->reply_read=0;
        }else if(value==2U){
            assert(m->direction==0 && m->now>=m->tx_end);
            assert(m->tx[4]==28 && m->packet_applied);
             
            assert(m->now<m->reply_start);
            m->query[m->queries-1U].rx_enabled=m->now;
            m->sticky_rx_error|=m->pending_query_error;m->pending_query_error=0;
        }
        m->direction=value;return;
    }
    assert(address>=ARM_BUS_UART_BASE);offset=(unsigned)(address-ARM_BUS_UART_BASE);
    switch(offset){
    case DATA:
        if(m->lcr&0x80U){m->dll=value;break;}
        assert(m->direction==1U && m->now-m->tx_enabled>=10U);
        assert(m->tx_count<16U);
        if(!m->tx_count){m->tx_start=m->now;m->tx_end=m->now;}
        m->tx[m->tx_count++]=(uint8_t)value;m->tx_end+=87U;break;
    case IER:if(m->lcr&0x80U)m->dlm=value;else m->ier=value;break;
    case LCR:m->lcr=value;break;
    case MCR:m->mcr=value;break;
    case SCR:m->scr=value;break;
    case FCR: {

        unsigned future_reply=value==3U && m->packet_applied && m->tx_count==6U &&
            m->tx[4]==28U && m->now<m->reply_start;
        assert(value==7U || value==3U);
        if(value==3U)assert(m->now>=m->tx_end && !m->direction);
        ++m->rx_resets;m->sticky_rx_error=0;
        m->rx_noise=0;
        if(!future_reply){m->reply_size=m->reply_read=0;m->pending_query_error=0;}
        if(value&4U){m->tx_count=0;m->packet_applied=1;m->tx_end=m->now;}
        break;
    }
    default:assert(0);
    }
}

static const arm_bus_hal_t hal={read_register,write_register,&device};

static void reset(void)
{
    const int initial[7]={0,552,499,145,781,689,481};
    if(arm_bus_busy())arm_bus_cancel();
    memset(&device,0,sizeof(device));memcpy(device.position,initial,sizeof(initial));
    device.now=1000000;device.opening_value=231;device.reply_delay_us=300U;
    assert(arm_bus_init(&hal)==0);arm_motion_init();
    assert(device.dll==54 && device.dlm==0 && device.lcr==3 && device.ier==0);
    assert(!device.moves && !device.queries && !device.stops && !device.direction);
}

static void tick(void)
{
    

    if(arm_motion_urgent())device.now+=10;
    else {
        device.now+=500;++device.idle_ticks;
        if(device.slow_tasks_enabled && device.now>=device.next_slow_task){
            assert(device.slow_task_count<2048U);
            device.slow_started[device.slow_task_count]=device.now;
            device.now+=25000;  
            device.next_slow_task=device.now+50000;
            ++device.slow_task_count;
        }
    }
    ++device.ticks;
     
    const uint64_t hz=(COUNTS_PER_SECOND);
    uint64_t ticks=device.now*(hz/1000000U);
    uint64_t measured_us=fusion_ticks_us(ticks);
    assert(measured_us==device.now);
    arm_motion_service(measured_us);
}

static void finish(void)
{
    unsigned budget=2000000;
    while(arm_motion_busy() && budget--){tick();}
    assert(budget>0 && device.direction==0 && !arm_bus_busy());
}

static void set_reference_home_duration(unsigned first_query)
{
    unsigned ms=500U;
    assert(reference[0].phase==ARM_PHASE_HOME && reference[0].mask==0x7cU);
    for(unsigned id=1;id<=6U;++id){
        const QueryRecord *q=&device.query[first_query+id-1U];
        assert(q->id==id && q->position>=0 && q->position<=1200);
        if(id==1U)continue;
        int delta=reference[0].positions[id]-q->position;
        if(delta<0)delta=-delta;
        unsigned limit=id==2U?60U:80U;
        unsigned required=((unsigned)delta*300U+limit-1U)/limit;
        if(required>ms)ms=required;
    }
    reference[0].duration_ms=(uint16_t)ms;
}

static void verify_trace(unsigned mode)
{
    unsigned i,id,index=0,previous_wait=0;
    uint64_t previous_end=0;
    if(mode==3)assert(arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count)==0);
    else assert(arm_plan_build(mode,reference,ARM_PLAN_CAPACITY,&reference_count)==0);
    if(mode==3)set_reference_home_duration(0U);
    for(i=0;i<reference_count;++i){
        ArmAction *a=&reference[i];
        unsigned first_in_group=index;
        if(a->hold){previous_wait+=a->duration_ms;continue;}
        if(previous_end)
            assert(device.move[index].started>=previous_end+(uint64_t)previous_wait*1000U);
        for(id=1;id<=6;++id){
            MoveRecord *r;
            if(!(a->mask&(1U<<id)))continue;
            assert(index<device.moves);r=&device.move[index++];
            assert(r->id==id && r->position==(unsigned)a->positions[id]);
            assert(r->duration==a->duration_ms);
            assert(r->transmitted-r->started==870U);
            

            assert(r->background_epoch==device.move[first_in_group].background_epoch);
            if(index>first_in_group+1U)
                assert(r->started-device.move[index-2U].transmitted<1000U);
        }
        previous_end=device.move[index-1U].transmitted;
        previous_wait=a->duration_ms+a->settle_ms;
    }
    assert(index==device.moves);
    assert(arm_motion_completed_actions()==reference_count);
    assert(strcmp(arm_motion_state_name(),"COMPLETED")==0);
    assert(device.idle_ticks>10000);  
}

static void verify_vertical_feedback_gates(void)
{
    unsigned move_index=0,query_index=6,align_gates=0,roll_gates=0,lift_gates=0,pick_gates=0;
    assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
    set_reference_home_duration(0U);
    for(unsigned i=0;i<reference_count;++i){
        const ArmAction *a=&reference[i];
        for(unsigned id=1;id<=6;++id)if(a->mask&(1U<<id))++move_index;
        if(i+1U<reference_count && reference[i+1U].phase==a->phase)continue;
        uint64_t settled=device.move[move_index-1U].transmitted+
                         (uint64_t)(a->duration_ms+a->settle_ms)*1000U;
        for(unsigned id=1;id<=6;++id)if(a->mask&(1U<<id)){
            assert(query_index<device.queries);
            const QueryRecord *q=&device.query[query_index++];
            assert(q->id==id && q->transmitted>=settled && q->rx_enabled>=q->transmitted);
        }
        if(i+1U<reference_count)
            assert(device.move[move_index].started>device.query[query_index-1U].transmitted+
                   device.reply_delay_us+7U*87U);
        if(a->phase==ARM_PHASE_VERTICAL_ALIGN){
            assert(a->mask==0x78U && a->pose[3]==-90 && a->pose[2]==-87);
            assert(reference[i+1U].phase==ARM_PHASE_ORIENT);++align_gates;
        }
        if(a->phase==ARM_PHASE_ORIENT && a->pose[2]==-87){
            assert(a->mask==4U && reference[i+1U].phase==ARM_PHASE_DESCEND);++roll_gates;
        }
        if(a->phase==ARM_PHASE_LIFT){
            assert(a->mask==0x7cU && a->pose[3]==-90 && a->pose[2]==-87);
            assert(reference[i+1U].phase==ARM_PHASE_LEAVE_VERTICAL);++lift_gates;
        }
        if(a->phase==ARM_PHASE_DESCEND){
            assert(a->pose[2]==-96 && a->pose[3]==-90 && a->mask==0x7cU);
            assert(reference[i+1U].phase==ARM_PHASE_CLOSE);++pick_gates;
        }
    }
    assert(query_index==device.queries && align_gates==1 && roll_gates==1 && lift_gates==1 && pick_gates==1);
}

static unsigned moves_through_first_phase(unsigned phase)
{
    unsigned moves=0;
    assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
    for(unsigned i=0;i<reference_count;++i){
        for(unsigned id=1;id<=6;++id)if(reference[i].mask&(1U<<id))++moves;
        if(reference[i].phase==phase &&
           (i+1U==reference_count || reference[i+1U].phase!=phase))return moves;
    }
    assert(0);return 0;
}

static void verify_pick_snapshot(int id4_delta)
{
    ArmPickFeedback snapshot;
    unsigned pick_index=0;
    assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
    for(unsigned i=0;i<reference_count;++i)
        if(reference[i].phase==ARM_PHASE_DESCEND)pick_index=i;
    assert(reference[pick_index+1U].phase==ARM_PHASE_CLOSE);
    assert(arm_motion_get_pick_feedback(&snapshot));
    assert(snapshot.valid && snapshot.action_index==pick_index && snapshot.mask==0x7cU);
    assert(snapshot.pose[0]==visual_target.x && snapshot.pose[1]==visual_target.y);
    assert(snapshot.pose[2]==-96 && snapshot.pose[3]==-90);
    for(unsigned id=2;id<=6;++id){
        assert(snapshot.commanded[id]==reference[pick_index].positions[id]);
        assert(snapshot.measured[id]==snapshot.commanded[id]+(id==4U?id4_delta:0));
    }
     
    assert(arm_motion_last_position(2)==500 && snapshot.measured[2]!=500);
}

static void test_fresh_skip_real_bus(void)
{
    assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
    for(unsigned scenario=0;scenario<7U;++scenario){
        reset();device.opening_value=200U;
        for(unsigned id=1;id<=6U;++id)device.position[id]=id==1U?200:reference[0].positions[id];
        assert(!arm_motion_start_visual(&visual_target,device.now));finish();
        verify_trace(3);verify_vertical_feedback_gates();
        assert(!device.stops && device.queries==42U && !arm_motion_skipped_initial_actions());
        unsigned expected_skip=2U;
        if(scenario==1U){device.position[1]=206;device.opening_value=206U;expected_skip=1U;}
        if(scenario==2U){device.position[3]+=6;expected_skip=0U;}
        if(scenario==3U){
            device.position[4]=1201;
            unsigned old_moves=device.moves;
            assert(!arm_motion_start_visual(&visual_target,device.now));finish();
            assert(!strcmp(arm_motion_last_error(),"POSITION_RANGE") && device.moves==old_moves && !device.stops);
            device.position[4]=reference[0].positions[4];expected_skip=0U;
        }
        if(scenario==4U)expected_skip=0U;
        if(scenario==6U)expected_skip=0U;
        if(scenario==5U){
            unsigned old_moves=device.moves;
            device.inject_line_query=device.queries+6U;device.line_query_count=3U;
            assert(!arm_motion_start_visual(&visual_target,device.now));finish();
            assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") && device.moves==old_moves && !device.stops);
            device.inject_line_query=0U;expected_skip=0U;
        }
        unsigned first_move=device.moves,first_query=device.queries;
        assert(!arm_motion_start_visual(&visual_target,device.now));
        if(scenario==4U){
            while(device.queries==first_query || arm_bus_busy())tick();
            assert(device.queries==first_query+1U && device.moves==first_move);
            device.now+=100001U;
        }
        if(scenario==6U){
            

            while(device.direction!=2U)tick();
            assert(device.queries==first_query+1U && device.moves==first_move);
            device.now+=105000U;arm_motion_service(device.now);
            ArmBusDiagnostic late;
            assert(arm_bus_get_diagnostic(&late) && late.command==28U && late.servo_id==1U);
            assert(late.accepted_at_deadline && late.received_bytes==8U && !late.error_code);
        }
        while(device.moves==first_move && arm_motion_busy())tick();
        assert(device.moves==first_move+1U && device.queries==first_query+6U);
        for(unsigned id=1;id<=6U;++id){
            const QueryRecord *q=&device.query[first_query+id-1U];
            assert(q->id==id && q->transmitted<device.move[first_move].started);
        }
        finish();assert(!strcmp(arm_motion_state_name(),"COMPLETED") && !device.stops);
        assert(arm_motion_skipped_initial_actions()==expected_skip);
        assert(device.queries-first_query==42U-(expected_skip?5U:0U)-(expected_skip==2U?1U:0U));
        set_reference_home_duration(first_query);
        unsigned m=first_move;
        for(unsigned i=expected_skip;i<reference_count;++i){
            const ArmAction *a=&reference[i];
            for(unsigned id=1;id<=6U;++id)if(a->mask&(1U<<id)){
                assert(m<device.moves && device.move[m].id==id);
                assert(device.move[m].position==(unsigned)a->positions[id]);
                assert(device.move[m].duration==a->duration_ms);++m;
            }
        }
        assert(m==device.moves && arm_motion_completed_actions()==reference_count);
        verify_pick_snapshot(0);++tests;
    }
    puts("REAL_UART_FRESH_SKIP_PASS: seven scenarios; actual parsed six-axis replies, first boot full gates, second HOME/OPEN strict skip,6raw drift/100ms stale feedback/late first valid FIFO reply105ms/1201/LINE reject reuse; exact remaining MOVE trace and final pick feedback retained");
}

static void test_expanded_range_repeated_picks(void)
{
    VisualPickTarget original=visual_target;
    const double targets_y[]={99,99.25,100,139,150,155,197.5,197.75};
    for(unsigned target_index=0;target_index<sizeof(targets_y)/sizeof(targets_y[0]);++target_index){
        visual_target.x=0;visual_target.y=targets_y[target_index];
        visual_target.dx=0.6;visual_target.dy=0.8;
        reset();
        unsigned per_moves=0,per_queries=0;
        for(unsigned cycle=0;cycle<3;++cycle){
            unsigned first_move=device.moves,first_query=device.queries;
            uint64_t cycle_start=device.now;
            assert(!arm_motion_start_visual(&visual_target,device.now));
            assert(!arm_motion_get_pick_feedback(NULL));
            finish();
            assert(!strcmp(arm_motion_state_name(),"COMPLETED") && !device.stops);
            assert(!arm_motion_query_retries());
            if(!cycle){
                verify_trace(3);verify_vertical_feedback_gates();
                per_moves=device.moves;per_queries=device.queries;
            }
            

            unsigned skipped_home=cycle?1U:0U;
            assert(device.moves-first_move==per_moves-5U*skipped_home);
            assert(device.queries-first_query==per_queries-5U*skipped_home);
            assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
            set_reference_home_duration(first_query);
            for(unsigned id=2;id<=6U;++id)if(skipped_home)
                assert(device.query[first_query+id-1U].position==reference[0].positions[id]);
            assert(device.query[first_query].position==231 || !cycle);
            assert(arm_motion_skipped_initial_actions()==skipped_home);
            unsigned move_index=first_move,down=0,up=0;
            const double down_z[2]={-92,-96},up_z[2]={-92,-87};
            for(unsigned i=0;i<reference_count;++i){
                const ArmAction *a=&reference[i];
                if(!i && skipped_home)continue;
                if(a->phase==ARM_PHASE_DESCEND){
                    assert(down<2 && a->pose[2]==down_z[down++] && a->pose[3]==-90);
                }
                if(a->phase==ARM_PHASE_LIFT){
                    assert(up<2 && a->pose[2]==up_z[up++] && a->pose[3]==-90);
                }
                for(unsigned id=1;id<=6;++id)if(a->mask&(1U<<id)){
                    const MoveRecord *sent=&device.move[move_index++];
                    assert(sent->id==id && sent->position==(unsigned)a->positions[id]);
                    assert(sent->duration==a->duration_ms);
                }
            }
            assert(down==2 && up==2 && move_index==device.moves);
            verify_pick_snapshot(0);
            ArmPickFeedback pick;assert(arm_motion_get_pick_feedback(&pick));

            double roll=(500.0-pick.commanded[2])*0.24*3.14159265358979323846/180.0;
            double projected_x=-sin(roll);
            double projected_y=sin(90.0*3.14159265358979323846/180.0)*cos(roll);
            double projected_norm=hypot(projected_x,projected_y);
            assert(pick.commanded[2]>500 && pick.measured[2]==pick.commanded[2]);
            assert(fabs(projected_x/projected_norm-0.6)<0.003);
            assert(fabs(projected_y/projected_norm-0.8)<0.003);
            assert(arm_motion_last_position(2)==500 && arm_motion_last_position(1)==231);
            for(unsigned id=3;id<=6;++id)
                assert(arm_motion_last_position(id)==reference[0].positions[id]);
            assert(device.move[device.moves-1U].id==1 && device.move[device.moves-1U].position==200);
            printf("CYCLE_LATENCY target=(0,%.2f) cycle=%u elapsed_us=%llu moves=%u queries=%u\n",
                   visual_target.y,cycle+1U,(unsigned long long)(device.now-cycle_start),
                   device.moves-first_move,device.queries-first_query);
        }
        ++tests;
        printf("RANGE_REPEAT target=(0,%.2f) cycles=3 init=1 moves_per_cycle=%u; transport100, fixedpitch-90, down-87/-92/-96, lift-96/-92/-87, bounded transport speed, negative wrist projection, HOME/center/open complete\n",visual_target.y,per_moves);
    }
    visual_target=original;
}

static void test_descent_tx_noise_and_timeout(void)
{
    unsigned first_descent=ARM_PLAN_CAPACITY,move_ordinal=0,id3_ordinal=0;
    assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
    for(unsigned i=0;i<reference_count;++i){
        if(reference[i].phase==ARM_PHASE_DESCEND && first_descent==ARM_PLAN_CAPACITY)
            first_descent=i;
        for(unsigned id=1;id<=6;++id)if(reference[i].mask&(1U<<id)){
            ++move_ordinal;
            if(i==first_descent && id==3U)id3_ordinal=move_ordinal;
        }
    }
    assert(first_descent<reference_count && id3_ordinal && reference[first_descent].pose[2]==-92);

    reset();device.inject_line_at_move=id3_ordinal;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    verify_trace(3);verify_vertical_feedback_gates();verify_pick_snapshot(0);
    assert(device.tx_noise_events==1 && device.tx_noise_id==3 && device.tx_noise_before_temt);
    assert(arm_bus_tx_rx_error_events()==1U &&
           (arm_bus_tx_rx_error_lsr()&0x89U)==0x89U);
    assert(!device.rx_noise && !device.stops && !arm_motion_query_retries());
    assert(device.moves==move_ordinal);
    assert(device.move[id3_ordinal-1U].id==3 &&
           device.move[id3_ordinal-1U].position==(unsigned)reference[first_descent].positions[3]);
    assert(device.move[id3_ordinal-1U].transmitted-device.move[id3_ordinal-1U].started==870U);
    ++tests;

    reset();device.stall_fifo_at_move=id3_ordinal;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    assert(device.stall_fifo_seen && device.moves==id3_ordinal-1U);
    assert(!arm_bus_tx_rx_error_events());
    assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") &&
           !strcmp(arm_motion_bus_error(),"TX_TIMEOUT") && arm_motion_fault_servo()==3);
    assert(device.stops==6 && device.stop_mask==0x7eU && !arm_motion_query_retries());
    ArmBusDiagnostic frozen,current;
    assert(arm_motion_get_bus_fault(&frozen) && arm_bus_get_diagnostic(&current));
    assert(frozen.command==1U && frozen.servo_id==3U && frozen.error_code==ARM_BUS_ERROR_TX_TIMEOUT);
    assert(!strcmp(arm_bus_phase_name(frozen.phase),"WAIT_FIFO") && !frozen.queued_bytes && !frozen.received_bytes);
    assert(frozen.elapsed_us==50000U && current.command==12U && current.servo_id==6U);
    assert(arm_motion_completed_actions()==first_descent && !arm_motion_get_pick_feedback(NULL));
    assert(device.first_stop_started>=device.stall_fifo_started+49000U &&
           device.first_stop_started<device.stall_fifo_started+52000U);
    for(unsigned i=0;i<device.moves;++i)
        assert(device.move[i].id!=1 || device.move[i].position!=600);
    ++tests;
    puts("DESCENT_TX: first Z-92 DESCEND ID3 receives 0x89 before TEMT; one complete 10-byte MOVE, no replay, all Z-96 feedback before CLOSE; blocked TX remains TX_TIMEOUT with six STOPs and no close/snapshot");
}

static void test_query_transmit_boundary(void)
{
    ArmBusDiagnostic frozen;
    reset();device.inject_tx_line_query=1U;
    assert(!arm_motion_start(ARM_MODE_FRONT,device.now));finish();verify_trace(ARM_MODE_FRONT);
    assert(device.tx_noise_events==1U && device.tx_noise_id==1U && device.tx_noise_before_temt);
    assert(arm_bus_tx_rx_error_events()==1U && (arm_bus_tx_rx_error_lsr()&0x89U)==0x89U);
    assert(device.queries==29U && device.moves==143U && !device.stops);
    assert(!arm_motion_query_retries() && !arm_motion_query_line_errors() && !arm_motion_get_bus_fault(NULL));
    ++tests;

    reset();device.inject_tx_line_query=12U;device.reply_delay_us=20U;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();verify_trace(3);
    verify_vertical_feedback_gates();verify_pick_snapshot(0);
    assert(device.tx_noise_events==1U && device.tx_noise_before_temt && !device.stops);
    assert(!arm_motion_query_retries() && !arm_motion_query_line_errors());
    for(unsigned i=0;i<device.queries;++i)
        assert(device.query[i].rx_enabled-device.query[i].transmitted<20U);
    ++tests;

    reset();device.inject_tx_line_query=1U;device.inject_line_query=1U;device.line_query_count=3U;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    assert(device.tx_noise_events==1U && arm_bus_tx_rx_error_events()==1U);
    assert(device.queries==3U && !device.moves && !device.stops);
    assert(arm_motion_query_retries()==2U && arm_motion_query_line_errors()==3U);
    assert(arm_motion_get_bus_fault(&frozen) && frozen.command==28U && frozen.servo_id==1U);
    assert(!strcmp(arm_bus_phase_name(frozen.phase),"RECEIVE") && frozen.error_code==ARM_BUS_ERROR_LINE);
    assert(frozen.queued_bytes==6U && !frozen.received_bytes && (frozen.lsr&8U));
    ++tests;
    puts("QUERY_TX_BOUNDARY_PASS: TX 0x89 preserves one complete query; 20us reply is not cleared; real RX faults still exhaust three reads and freeze RECEIVE diagnostics");
}

static void test_visual_smooth_scheduler(void)
{
    unsigned move_index=0,interiors=0,near_table_interiors=0;
    uint64_t max_drift=0;
    reset();device.slow_tasks_enabled=1U;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    verify_trace(3);verify_vertical_feedback_gates();verify_pick_snapshot(0);
    set_reference_home_duration(0U);
    assert(device.slow_task_count>100U && !device.stops);
    for(unsigned i=0;i<reference_count;++i){
        const ArmAction *a=&reference[i];
        for(unsigned id=1;id<=6U;++id)if(a->mask&(1U<<id))++move_index;
        uint64_t deadline=device.move[move_index-1U].transmitted+
            (uint64_t)(a->duration_ms+a->settle_ms)*1000U;

        for(unsigned n=0;n<device.slow_task_count;++n)
            assert(device.slow_started[n]<deadline-29000U || device.slow_started[n]>=deadline);
        if(i+1U>=reference_count || reference[i+1U].phase!=a->phase)continue;
        uint64_t next=device.move[move_index].started;
        assert(next>=deadline && next-deadline<200U);
        if(next-deadline>max_drift)max_drift=next-deadline;
        if(a->phase==ARM_PHASE_DESCEND || a->phase==ARM_PHASE_LIFT){
            assert(a->duration_ms==300U && a->settle_ms==30U);++near_table_interiors;
        }else{assert(a->settle_ms==0U);++interiors;}
    }
    assert(interiors>35U && near_table_interiors==2U);
    ++tests;
    printf("SMOOTH_SCHEDULER_PASS: %u transport interiors no dwell; two near-table30ms retained; max between-segment scheduler drift=%lluus with %u 25ms tasks, complete phase feedback unchanged\n",
           interiors,(unsigned long long)max_drift,device.slow_task_count);

    reset();assert(!arm_motion_start_visual(&visual_target,device.now));
    while(device.moves<5U || arm_motion_urgent())tick();
    assert(device.queries==6U && !device.stops);
    uint64_t deadline=device.now+(uint64_t)(device.move[0].duration+80U)*1000U;
    device.now=deadline-30001U;arm_motion_service(device.now);
    assert(!arm_motion_urgent() && device.moves==5U && device.queries==6U);
    device.now=deadline-30000U;arm_motion_service(device.now);
    assert(arm_motion_urgent() && device.moves==5U && device.queries==6U);
    device.now=deadline-1U;arm_motion_service(device.now);
    assert(arm_motion_urgent() && device.moves==5U && device.queries==6U);
    arm_motion_cancel();unsigned before_background=device.slow_task_count;
    finish();
    assert(!strcmp(arm_motion_state_name(),"CANCELLED") && device.moves==5U);
    assert(device.stops==6U && device.stop_mask==0x7eU && device.slow_task_count==before_background);
    assert(device.last_stop_transmitted-device.first_stop_started<10000U);
    ++tests;
    puts("VISUAL_WINDOW_PASS: nonurgent at deadline-30001us, urgent at -30000us/-1us, no early read/MOVE, cancel retains six rapid STOPs without OPEN");
}

static void benchmark_smoothing(void)
{
    visual_target.x=0;visual_target.y=155;visual_target.dx=0.6;visual_target.dy=0.8;
    for(unsigned pose=0;pose<4U;++pose)for(unsigned slow=0;slow<2U;++slow){
        const char *names[]={"already_home","default_initial","wrist1200","arm3_1200"};
        reset();
        assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
        if(pose!=1U)for(unsigned id=2U;id<=6U;++id)device.position[id]=reference[0].positions[id];
        if(pose==2U)device.position[2]=1200;
        if(pose==3U)device.position[3]=1200;
        int initial[7];memcpy(initial,device.position,sizeof(initial));
        device.slow_tasks_enabled=slow;
        uint64_t begun=device.now;
        assert(!arm_motion_start_visual(&visual_target,device.now));finish();
        verify_trace(3);verify_vertical_feedback_gates();
        unsigned interiors=0,near_interiors=0,settle=0,duration=0,move_index=0;
        uint64_t max_drift=0;
        for(unsigned i=0;i<reference_count;++i){
            const ArmAction *a=&reference[i];
            settle+=a->settle_ms;duration+=a->duration_ms;
            for(unsigned id=1U;id<=6U;++id)if(a->mask&(1U<<id))++move_index;
            if(i+1U>=reference_count || reference[i+1U].phase!=a->phase)continue;
            if(a->phase==ARM_PHASE_DESCEND || a->phase==ARM_PHASE_LIFT)++near_interiors;
            else ++interiors;
            uint64_t deadline=device.move[move_index-1U].transmitted+
                (uint64_t)(a->duration_ms+a->settle_ms)*1000U;
            assert(device.move[move_index].started>=deadline);
            uint64_t drift=device.move[move_index].started-deadline;
            if(drift>max_drift)max_drift=drift;
        }
        assert(device.queries==42U && !device.stops && move_index==device.moves && near_interiors==2U);
        printf("{\"pose\":\"%s\",\"slow_background\":%s,\"target\":[0,155,-96,-90],\"initial_raw\":[%d,%d,%d,%d,%d,%d],"
               "\"home_duration_ms\":%u,\"elapsed_us\":%llu,\"move_packets\":%u,\"query_packets\":%u,\"actions\":%u,"
               "\"transport_interiors\":%u,\"near_table_interiors\":%u,\"planned_move_ms\":%u,\"planned_settle_ms\":%u,"
               "\"max_intersegment_drift_us\":%llu,\"slow_task_count\":%u}\n",
               names[pose],slow?"true":"false",initial[1],initial[2],initial[3],initial[4],initial[5],initial[6],
               device.move[0].duration,(unsigned long long)(device.now-begun),device.moves,device.queries,reference_count,
               interiors,near_interiors,duration,settle,(unsigned long long)max_drift,device.slow_task_count);
    }
}

static void test_persistent_failure_real_bus(void)
{
    ArmMotionFailure saved,after;
    reset();device.partial_query=1U;device.partial_count=3U;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    assert(device.queries==3U && !device.moves && !device.stops);
    assert(arm_motion_get_last_failure(&saved) && saved.sequence==1U);
    assert(!strcmp(arm_motion_error_name(saved.error_code),"BUS_RESULT"));
    assert(saved.bus_valid && saved.bus.error_code==ARM_BUS_ERROR_RX_TIMEOUT);
    assert(saved.bus.servo_id==1U && saved.actual_mask==0U && !saved.motion_attempted);
    assert(saved.query_retries==2U && saved.read_failure_count==3U);
    for(unsigned i=0;i<3U;++i){
        const ArmReadAttemptFailure *failure=&saved.read_failures[i];
        assert(failure->attempt==i+1U && failure->bus.valid);
        assert(failure->bus.command==28U && failure->bus.servo_id==1U);
        assert(failure->bus.error_code==ARM_BUS_ERROR_RX_TIMEOUT);
        assert(failure->bus.queued_bytes==6U && failure->bus.received_bytes==7U);
        assert(failure->bus.elapsed_us>=100000U && failure->bus.elapsed_us<101000U);
        assert(failure->bus.max_service_gap_us==10U);
        assert(failure->bus.rx_enabled_elapsed_us>0U && failure->bus.rx_enabled_elapsed_us<1000U);
        assert(failure->bus.first_rx_elapsed_us>failure->bus.rx_enabled_elapsed_us);
        assert(failure->bus.first_rx_elapsed_us<2000U);
        assert(failure->bus.deadline_fifo_check && !failure->bus.accepted_at_deadline);
    }
    unsigned initial_queries=device.queries;
    assert(!arm_motion_start_visual(&visual_target,device.now));
    assert(!arm_motion_get_bus_fault(NULL));
    assert(arm_motion_start_visual(&visual_target,device.now)==-1);
    assert(arm_motion_get_last_failure(&after) && !memcmp(&saved,&after,sizeof(saved)));
    finish();
    assert(!strcmp(arm_motion_state_name(),"COMPLETED") && !device.stops);
    assert(device.queries==initial_queries+42U && !arm_motion_get_bus_fault(NULL));
    assert(arm_motion_get_last_failure(&after) && !memcmp(&saved,&after,sizeof(saved)));
     
    assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
    set_reference_home_duration(initial_queries);
    unsigned move_index=0;
    for(unsigned i=0;i<reference_count;++i){
        const ArmAction *action=&reference[i];
        for(unsigned id=1;id<=6U;++id)if(action->mask&(1U<<id)){
            assert(move_index<device.moves);
            const MoveRecord *sent=&device.move[move_index++];
            assert(sent->id==id && sent->position==(unsigned)action->positions[id]);
            assert(sent->duration==action->duration_ms);
        }
    }
    assert(move_index==device.moves);
    unsigned prior_moves=device.moves;
    device.inject_line_query=device.queries+1U;device.line_query_count=3U;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    assert(device.moves==prior_moves && !device.stops && arm_motion_get_last_failure(&after));
    assert(after.sequence==2U && after.bus.error_code==ARM_BUS_ERROR_LINE && after.read_failure_count==3U);
    assert(after.query_line_errors==3U && after.query_retries==2U);
    for(unsigned i=0;i<3U;++i)
        assert(after.read_failures[i].bus.error_code==ARM_BUS_ERROR_LINE && after.read_failures[i].attempt==i+1U);
    arm_motion_init();assert(!arm_motion_get_last_failure(NULL));
    ++tests;
    puts("PERSISTENT_REAL_BUS_PASS: three genuine seven-byte RX timeouts retained across successful pick/BUSY; MOVE trace unchanged; new RECEIVE line failure updates history; init clears");
}

static void test_buffered_reply_after_service_gap(void)
{
    ArmBusDiagnostic diagnostic;
    reset();assert(!arm_motion_start_visual(&visual_target,device.now));
    unsigned budget=10000U;
    while(device.direction!=2U && budget--)tick();
    assert(budget && device.queries==1U && !device.moves);

    device.now+=105000U;
    arm_motion_service(device.now);
    assert(arm_bus_get_diagnostic(&diagnostic));
    assert(diagnostic.command==28U && diagnostic.servo_id==1U);
    assert(diagnostic.received_bytes==8U && diagnostic.error_code==ARM_BUS_ERROR_NONE);
    assert(diagnostic.deadline_fifo_check && diagnostic.accepted_at_deadline);
    assert(diagnostic.max_service_gap_us==105000U);
    assert(diagnostic.first_rx_elapsed_us>100000U);  
    assert(!arm_motion_get_last_failure(NULL) && !arm_motion_query_retries());
    finish();assert(!strcmp(arm_motion_state_name(),"COMPLETED"));
    assert(device.queries==42U && !device.stops && !arm_motion_query_retries());
    verify_trace(3);
    ++tests;
    puts("BUFFERED_DEADLINE_MOTION_PASS: one complete valid buffered reply survives105ms CPU service gap; no retry, error, duplicate query, altered MOVE or STOP");
}

static unsigned visual_phase_query(unsigned phase,unsigned wanted_id)
{
    unsigned q=6U;
    assert(!arm_plan_build_visual(&visual_target,reference,ARM_PLAN_CAPACITY,&reference_count));
    for(unsigned i=0;i<reference_count;++i){
        const ArmAction *a=&reference[i];
        if(i+1U<reference_count && reference[i+1U].phase==a->phase)continue;
        for(unsigned id=1;id<=6U;++id)if(a->mask&(1U<<id)){
            ++q;if(a->phase==phase && id==wanted_id)return q;
        }
    }
    assert(0);return 0;
}

static ArmReadRecovery wait_for_recovery(void)
{
    ArmReadRecovery recovery;unsigned budget=2000000U;
    memset(&recovery,0,sizeof(recovery));
    while(arm_motion_busy() && !arm_motion_get_read_recovery(&recovery) && budget--)tick();
    assert(budget && recovery.attempted==1U && recovery.active && !recovery.succeeded);
    assert(!recovery.recheck_started_us && !arm_bus_busy() && !arm_motion_urgent());
    return recovery;
}

static void start_empty_approach(unsigned q,unsigned count)
{
    reset();device.empty_query=q;device.empty_count=count;
    assert(!arm_motion_start_visual(&visual_target,device.now));
}

static void test_bounded_empty_recheck(void)
{
    const unsigned q=visual_phase_query(ARM_PHASE_APPROACH,5U);
    const unsigned second_q=visual_phase_query(ARM_PHASE_VERTICAL_ALIGN,5U);
    ArmReadRecovery recovery;ArmMotionFailure failure;
    assert(ARM_READ_RECOVERY_SETTLE_US==200000U && q>6U && second_q>q);
    start_empty_approach(q,3U);recovery=wait_for_recovery();
    assert(device.queries==q+2U && recovery.read_mask==0x78U && recovery.fault_servo==5U);
    assert(recovery.phase==ARM_PHASE_APPROACH && recovery.read_failure_count==3U);
    for(unsigned i=0;i<3U;++i){
        const ArmBusDiagnostic *d=&recovery.read_failures[i].bus;
        assert(d->servo_id==5U && d->command==28U && !d->received_bytes);
        assert(d->error_code==ARM_BUS_ERROR_RX_TIMEOUT && !(d->lsr&0x9eU));
    }
    unsigned moves_before=device.moves,queries_before=device.queries;
    device.now=recovery.started_us+199999U;arm_motion_service(device.now);
    assert(device.moves==moves_before && device.queries==queries_before && !device.stops);
    assert(arm_motion_get_read_recovery(&recovery) && !recovery.recheck_started_us && recovery.active);
    device.now=recovery.started_us+200000U;arm_motion_service(device.now);
    finish();verify_trace(3);verify_pick_snapshot(0);
    assert(device.queries==47U && !device.stops && arm_motion_query_retries()==2U);
    assert(arm_motion_get_read_recovery(&recovery) && recovery.succeeded==1U && !recovery.active);
    assert(recovery.fresh_mask==0x78U && !recovery.error_code);
    assert(recovery.recheck_started_us-recovery.started_us==200000U);
    assert(!arm_motion_get_last_failure(NULL) && !arm_motion_get_bus_fault(NULL));
    for(unsigned k=0;k<4U;++k)assert(device.query[q+2U+k].id==3U+k);
    assert(device.query[q+2U].transmitted>=recovery.recheck_started_us);
    ++tests;
    puts("EMPTY_RECOVERY_PASS: three actual empty UART replies; exact200ms no-MOVE wait; complete IDs3..6 reread; unchanged complete MOVE trace/durations; one recovery recorded");

    start_empty_approach(q,1000U);recovery=wait_for_recovery();
    moves_before=device.moves;uint64_t first_bad=device.query[q-1U].transmitted;
    finish();assert(!strcmp(arm_motion_state_name(),"ERROR") && !strcmp(arm_motion_last_error(),"BUS_RESULT"));
    assert(device.moves==moves_before && device.queries==q+5U && device.stops==6U && device.stop_mask==0x7eU);
    assert(device.last_stop_transmitted-first_bad<1000000U);
    assert(arm_motion_get_read_recovery(&recovery) && recovery.attempted==1U && !recovery.active && !recovery.succeeded);
    assert(!recovery.fresh_mask && !strcmp(arm_motion_error_name(recovery.error_code),"BUS_RESULT"));
    assert(recovery.original_fault.servo_id==5U && !recovery.original_fault.received_bytes);
    assert(arm_motion_get_last_failure(&failure) && failure.bus.servo_id==3U);
    ++tests;

    for(unsigned id=3U;id<=4U;++id){
        start_empty_approach(q,3U);recovery=wait_for_recovery();moves_before=device.moves;
        device.feedback_delta[id]=21;finish();
        assert(!strcmp(arm_motion_last_error(),"ARRIVAL") && arm_motion_fault_servo()==id);
        assert(device.moves==moves_before && device.queries==q+6U && device.stops==6U);
        assert(arm_motion_get_read_recovery(&recovery) && !recovery.active && !recovery.succeeded);
        assert(recovery.fresh_mask==0x78U && !strcmp(arm_motion_error_name(recovery.error_code),"ARRIVAL"));
        ++tests;
    }
    start_empty_approach(q,3U);recovery=wait_for_recovery();moves_before=device.moves;
    device.feedback_delta[3]=1201-device.position[3];finish();
    assert(!strcmp(arm_motion_last_error(),"POSITION_RANGE") && arm_motion_fault_servo()==3U);
    assert(device.moves==moves_before && device.stops==6U);
    assert(arm_motion_get_read_recovery(&recovery) && !recovery.succeeded && !recovery.active);
    assert(!recovery.fresh_mask && !strcmp(arm_motion_error_name(recovery.error_code),"POSITION_RANGE"));
    ++tests;

    start_empty_approach(q,3U);recovery=wait_for_recovery();moves_before=device.moves;queries_before=device.queries;
    device.now=recovery.started_us+100000U;arm_motion_cancel();finish();
    assert(!strcmp(arm_motion_state_name(),"CANCELLED") && device.stops==6U);
    assert(device.queries==queries_before && device.moves==moves_before);
    assert(arm_motion_get_read_recovery(&recovery) && !recovery.active && !recovery.succeeded);
    assert(!strcmp(arm_motion_error_name(recovery.error_code),"CANCELLED"));
    for(unsigned i=0;i<1000U;++i)tick();
    assert(device.queries==queries_before && device.moves==moves_before);
    ++tests;

    start_empty_approach(q,3U);recovery=wait_for_recovery();
    while(arm_motion_busy()){
        tick();assert(arm_motion_get_read_recovery(&recovery));
        if(recovery.succeeded)break;
    }
    assert(recovery.succeeded && arm_motion_busy());
    device.empty_query=second_q+5U;device.empty_count=3U;
    finish();
    assert(!strcmp(arm_motion_state_name(),"ERROR") && !strcmp(arm_motion_last_error(),"BUS_RESULT"));
    assert(device.queries==second_q+7U && device.stops==6U);
    assert(device.query[second_q+4U].id==5U && arm_motion_get_read_recovery(&recovery));
    assert(recovery.attempted==1U && recovery.succeeded==1U && !recovery.active);
    ++tests;

    reset();device.empty_query=1U;device.empty_count=3U;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    assert(!device.moves && !device.stops && device.queries==3U && !arm_motion_get_read_recovery(&recovery));
    ++tests;
    reset();device.empty_query=12U;device.empty_count=3U;
    assert(!arm_motion_start(ARM_MODE_FRONT,device.now));finish();
    assert(device.queries==14U && device.stops==6U && !arm_motion_get_read_recovery(&recovery));
    ++tests;
    const unsigned close_q=visual_phase_query(ARM_PHASE_CLOSE,1U);
    start_empty_approach(close_q,3U);finish();
    assert(device.queries==close_q+2U && device.stops==6U && !arm_motion_get_read_recovery(&recovery));
    assert(!strcmp(arm_motion_last_error(),"BUS_RESULT"));
    ++tests;
    reset();device.partial_query=q;device.partial_count=3U;
    assert(!arm_motion_start_visual(&visual_target,device.now));finish();
    assert(device.queries==q+2U && device.stops==6U && !arm_motion_get_read_recovery(&recovery));
    ++tests;
    start_empty_approach(q,3U);device.inject_line_query=q+1U;device.line_query_count=1U;
    finish();assert(device.queries==q+2U && device.stops==6U && !arm_motion_get_read_recovery(&recovery));
    assert(arm_motion_query_line_errors()==1U);++tests;
    

    const unsigned home_q=visual_phase_query(ARM_PHASE_HOME,5U);
    start_empty_approach(home_q,3U);recovery=wait_for_recovery();
    assert(recovery.read_mask==0x7cU);finish();verify_trace(3);
    assert(arm_motion_get_read_recovery(&recovery) && recovery.succeeded && recovery.fresh_mask==0x7cU);
    for(unsigned k=0;k<5U;++k)assert(device.query[home_q+2U+k].id==2U+k);
    assert(device.queries==48U && !device.stops);++tests;
    puts("EMPTY_RECOVERY_GATES_PASS: permanent outage STOPs under1s without MOVE replay; full reread exposes ID3/4 ARRIVAL and range errors; cancel never resumes; second fault cannot recover; preflight/nonvisual/gripper stay strict");
    puts("READ_RECOVERY_INTEGRATION_PASS:13 new real-bus scenarios; pure-empty-only; mixedLINE/partial reject; mask78/mask7c fully reread; fresh_mask and terminal error distinguish attempted from succeeded");
}

int main(int argc,char **argv)
{
    if(argc==2 && !strcmp(argv[1],"benchmark-smoothing")){benchmark_smoothing();return 0;}
    test_bounded_empty_recheck();
    unsigned before;
    reset();for(before=0;before<100;++before)tick();
    assert(!device.moves && !device.queries && !device.stops);++tests;

    reset();assert(arm_motion_start(ARM_MODE_FRONT,device.now)==0);finish();
    verify_trace(ARM_MODE_FRONT);assert(device.moves==143 && !device.stops);
    assert(arm_motion_last_position(1)==565);++tests;
    printf("FRONT moves=%u queries=%u elapsed_us=%llu ticks=%u idle_ticks=%u\n",
           device.moves,device.queries,(unsigned long long)(device.now-1000000),
           device.ticks,device.idle_ticks);

    reset();assert(arm_motion_start(ARM_MODE_NINE,device.now)==0);finish();
    verify_trace(ARM_MODE_NINE);assert(device.moves==1315 && device.queries==259);
    assert(!device.stops && !arm_motion_query_retries());++tests;
    printf("NINE moves=%u queries=%u elapsed_us=%llu ticks=%u idle_ticks=%u\n",
           device.moves,device.queries,(unsigned long long)(device.now-1000000),
           device.ticks,device.idle_ticks);

    reset();device.partial_query=25;device.partial_count=1;
    assert(arm_motion_start(ARM_MODE_NINE,device.now)==0);finish();
    verify_trace(ARM_MODE_NINE);
    assert(device.moves==1315 && device.queries==260 && !device.stops);
    assert(arm_motion_query_retries()==1);
    assert(device.query[24].id==device.query[25].id);
    assert(device.query[25].transmitted>=device.query[24].rx_enabled+105000U);
    ++tests;

    reset();device.partial_query=12;device.partial_count=3;
    assert(arm_motion_start(ARM_MODE_FRONT,device.now)==0);finish();
    assert(strcmp(arm_motion_last_error(),"BUS_RESULT")==0);
    assert(strcmp(arm_motion_bus_error(),"RX_TIMEOUT")==0);
    assert(arm_motion_query_retries()==2 && device.queries==14);
    assert(device.moves==6 && device.stops==6 && device.stop_mask==0x7eU);++tests;
    ArmBusDiagnostic timeout_fault,current_bus;
    assert(arm_motion_get_bus_fault(&timeout_fault) && arm_bus_get_diagnostic(&current_bus));
    assert(timeout_fault.command==28U && timeout_fault.servo_id==device.query[device.queries-1U].id);
    assert(!strcmp(arm_bus_phase_name(timeout_fault.phase),"RECEIVE"));
    assert(timeout_fault.error_code==ARM_BUS_ERROR_RX_TIMEOUT && timeout_fault.queued_bytes==6U && timeout_fault.received_bytes==7U);
    assert(timeout_fault.elapsed_us>=100000U && timeout_fault.elapsed_us<101000U);
    assert(current_bus.command==12U && current_bus.servo_id==6U);

    reset();device.inject_line_at_move=2;
    assert(arm_motion_start(ARM_MODE_FRONT,device.now)==0);finish();
    verify_trace(ARM_MODE_FRONT);
    assert(device.tx_noise_events==1 && device.tx_noise_before_temt && !device.rx_noise);
    assert(arm_bus_tx_rx_error_events()==1U &&
           (arm_bus_tx_rx_error_lsr()&0x89U)==0x89U);
    assert(device.moves==143 && !device.stops && !strcmp(arm_motion_bus_error(),"NONE"));
    assert(!arm_motion_query_retries());++tests;

    reset();device.opening_value=241;
    assert(arm_motion_start(ARM_MODE_FRONT,device.now)==0);finish();
    assert(device.moves==6 && device.stops==6 && device.stop_mask==0x7eU);
    assert(strcmp(arm_motion_last_error(),"ARRIVAL")==0);++tests;

    reset();assert(arm_motion_start(ARM_MODE_NINE,device.now)==0);
    while(device.moves<5){tick();}
    arm_motion_cancel();finish();
    assert(device.moves==5 && device.stops==6 && device.stop_mask==0x7eU);
    assert(strcmp(arm_motion_state_name(),"CANCELLED")==0);
    before=device.moves;for(unsigned i=0;i<100;++i)tick();assert(device.moves==before);++tests;

    reset();device.slow_tasks_enabled=1;
    assert(arm_motion_start(ARM_MODE_FRONT,device.now)==0);finish();
    verify_trace(ARM_MODE_FRONT);
    assert(device.slow_task_count>100 && !device.stops);
    assert(device.moves==143 && device.queries==29);++tests;
    printf("URGENT_SCHEDULER moves=%u queries=%u slow_tasks=%u elapsed_us=%llu; no background work inside MOVE groups\n",
           device.moves,device.queries,device.slow_task_count,
           (unsigned long long)(device.now-1000000));

    reset();device.slow_tasks_enabled=1;
    assert(arm_motion_start(ARM_MODE_FRONT,device.now)==0);
    while(device.slow_task_count<5U){tick();}
    assert(device.moves==5U);arm_motion_cancel();
    before=device.slow_task_count;finish();
    assert(device.stops==6U && device.stop_mask==0x7eU && device.moves==5U);
    assert(device.slow_task_count==before);
    assert(device.first_stop_background_epoch==device.last_stop_background_epoch);
    assert(device.last_stop_transmitted-device.first_stop_started<10000U);
    assert(strcmp(arm_motion_state_name(),"CANCELLED")==0);++tests;
    printf("URGENT_STOP packets=%u elapsed_us=%llu; no background work during STOP sequence\n",
           device.stops,(unsigned long long)(device.last_stop_transmitted-device.first_stop_started));

    reset();assert(arm_motion_start_visual(&visual_target,device.now)==0);finish();
    verify_trace(3);assert(!device.stops && arm_motion_last_position(2)==500);++tests;
    verify_vertical_feedback_gates();
    verify_pick_snapshot(0);
    printf("VISUAL_PICK moves=%u queries=%u actions=%u elapsed_us=%llu\n",device.moves,device.queries,
           arm_motion_completed_actions(),(unsigned long long)(device.now-1000000));
    test_expanded_range_repeated_picks();
    test_fresh_skip_real_bus();
    test_descent_tx_noise_and_timeout();
    test_query_transmit_boundary();
    test_visual_smooth_scheduler();
    test_persistent_failure_real_bus();
    test_buffered_reply_after_service_gap();

    reset();device.feedback_delta[4]=7;
    assert(!arm_motion_start_visual(&visual_target,device.now));
    assert(!arm_motion_get_pick_feedback(NULL));
    finish();verify_trace(3);verify_pick_snapshot(7);++tests;
    puts("PICK_FEEDBACK: production UART raw ID4+7 retained at Z-96/-90; full mask 0x7c, no extra read/MOVE, later HOME cannot overwrite snapshot");

    const unsigned fail_phases[]={ARM_PHASE_VERTICAL_ALIGN,ARM_PHASE_ORIENT,ARM_PHASE_DESCEND,ARM_PHASE_LIFT};
    const unsigned fail_ids[]={3,2,3,3};
    for(unsigned k=0;k<4;++k){
        reset();assert(!arm_motion_start_visual(&visual_target,device.now));
        unsigned budget=2000000;
        while(strcmp(arm_motion_phase_name(),arm_phase_name(fail_phases[k])) && budget--)tick();
        assert(budget>0 && arm_motion_busy());
        device.feedback_delta[fail_ids[k]]=21;
        finish();
        assert(!strcmp(arm_motion_last_error(),"ARRIVAL") && arm_motion_fault_servo()==fail_ids[k]);
        assert(device.moves==moves_through_first_phase(fail_phases[k]));
        assert(device.stops==6 && device.stop_mask==0x7eU);
        assert(arm_motion_completed_actions()<arm_motion_action_count());++tests;
        ArmPickFeedback failed_snapshot;
        int has_pick=arm_motion_get_pick_feedback(&failed_snapshot);
        assert(has_pick==(fail_phases[k]==ARM_PHASE_DESCEND || fail_phases[k]==ARM_PHASE_LIFT));
        if(fail_phases[k]==ARM_PHASE_DESCEND){
            assert(failed_snapshot.mask==0x7cU && failed_snapshot.pose[2]==-96);
            assert(failed_snapshot.measured[3]==failed_snapshot.commanded[3]+21);
        }
    }
    puts("VERTICAL_GATES: actual feedback precedes rotation/descent/tilting; +21 arrival failures STOP before the next phase");

    const double rejected_y[]={80,98.75,198,200,230};
    for(unsigned k=0;k<sizeof(rejected_y)/sizeof(rejected_y[0]);++k){
        reset();VisualPickTarget far=visual_target;far.x=0;far.y=rejected_y[k];
        assert(visual_pick_target_valid(&far));
        assert(arm_motion_start_visual(&far,device.now)!=0);
        assert(!device.moves && !device.queries && !device.stops && !strcmp(arm_motion_last_error(),"PLAN"));++tests;
        assert(!arm_motion_action_count() && !arm_motion_completed_actions());
    }
    reset();VisualPickTarget out_of_domain=visual_target;out_of_domain.x=0;out_of_domain.y=79.9;
    assert(!visual_pick_target_valid(&out_of_domain));
    assert(arm_motion_start_visual(&out_of_domain,device.now)!=0);
    assert(!device.moves && !device.queries && !device.stops && !strcmp(arm_motion_last_error(),"PLAN"));++tests;
    assert(!arm_motion_action_count() && !arm_motion_completed_actions());
    puts("RANGE_REJECTION: Y80/Y98.75/Y198/Y200/Y230 full path unreachable and Y79.9 outside input domain reject before any UART read/MOVE; protocol0..1000 retained, custom margin0");

    const int initial_id4[]={1007,1200};
    for(unsigned k=0;k<2;++k){
        reset();device.position[4]=initial_id4[k];
        assert(!arm_position_allowed(4,initial_id4[k]));
        assert(arm_motion_start_visual(&visual_target,device.now)==0);
        while(!device.moves && arm_motion_busy())tick();
        assert(device.moves && arm_motion_last_position(4)==initial_id4[k]);
        finish();verify_trace(3);
        assert(!device.stops && arm_motion_last_position(1)==231 && arm_motion_last_position(2)==500);
        assert(device.move[device.moves-1U].id==1 && device.move[device.moves-1U].position==200);
        ++tests;
    }
    reset();device.position[4]=1201;
    assert(arm_motion_start_visual(&visual_target,device.now)==0);finish();
    assert(!device.moves && !device.stops && device.queries==4);
    assert(!strcmp(arm_motion_last_error(),"POSITION_RANGE") && arm_motion_fault_servo()==4);
    assert(arm_motion_last_position(4)==1201);++tests;
    puts("FEEDBACK_UPPER120: real parsed ID4=1007/1200 completes full visual release; 1201 rejects before any MOVE");

    reset();device.feedback_delta[4]=20;
    assert(arm_motion_start_visual(&visual_target,device.now)==0);finish();
    verify_trace(3);assert(!device.stops);++tests;
    reset();device.feedback_delta[4]=21;
    assert(arm_motion_start_visual(&visual_target,device.now)==0);finish();
    assert(!strcmp(arm_motion_last_error(),"ARRIVAL") && arm_motion_fault_servo()==4);
    assert(device.moves==5 && device.stops==6 && device.stop_mask==0x7eU);
    assert(arm_motion_completed_actions()==0);++tests;
    puts("ARRIVAL_UNCHANGED: +20 passes; +21 triggers six STOPs and no further trajectory/release");

    reset();unsigned per_moves=0,per_queries=0;
    for(unsigned cycle=1;cycle<=3;++cycle){
        unsigned start_moves=device.moves,start_queries=device.queries;
        if(cycle==2){
            device.sticky_rx_error=0x08U;
            device.inject_line_query=device.queries+2U;device.line_query_count=1U;
        }
        assert(arm_motion_start_visual(&visual_target,device.now)==0);
        assert(!arm_motion_get_pick_feedback(NULL));
        finish();
        assert(!strcmp(arm_motion_state_name(),"COMPLETED") && !device.stops);
        assert(arm_motion_last_position(1)==231 && arm_motion_last_position(2)==500);
        assert(device.move[device.moves-1U].id==1 && device.move[device.moves-1U].position==200);
        verify_pick_snapshot(0);
        if(cycle==1){per_moves=device.moves;per_queries=device.queries;verify_trace(3);}
        unsigned skipped_home=cycle>1U?1U:0U;
        assert(device.moves-start_moves==per_moves-5U*skipped_home);
        assert(device.queries-start_queries==per_queries-5U*skipped_home+(cycle==2));
        assert(arm_motion_skipped_initial_actions()==skipped_home);
        assert(arm_motion_query_retries()==(cycle==2));
        assert(arm_motion_query_line_errors()==(cycle==2));
        if(cycle==2){
            assert(arm_motion_fault_lsr()&8U);
            QueryRecord *bad=&device.query[start_queries+1U],*retry=&device.query[start_queries+2U];
            assert(bad->id==2 && retry->id==2 && retry->transmitted>=bad->rx_enabled+5000U);
        }else assert(arm_motion_fault_lsr()==0U);
    }
    ++tests;printf("REPEAT_VISUAL cycles=3 init=1 moves_per_cycle=%u; sticky RX cleared, one bad ID2 query retried, final release verified\n",per_moves);

    reset();device.inject_line_query=1;device.line_query_count=3;
    assert(arm_motion_start_visual(&visual_target,device.now)==0);finish();
    assert(device.queries==3 && !device.moves && !device.stops);
    assert(!strcmp(arm_motion_last_error(),"BUS_RESULT") && !strcmp(arm_motion_bus_error(),"UART_LINE"));
    assert(arm_motion_query_retries()==2 && arm_motion_query_line_errors()==3);
    assert(arm_motion_fault_servo()==1 && (arm_motion_fault_lsr()&8U));++tests;

    reset();device.forced_line_error=0x10U;
    assert(arm_motion_start_visual(&visual_target,device.now)==0);finish();
    assert(device.queries==3U && !device.moves && !device.stops);
    assert(arm_motion_query_retries()==2 && arm_motion_query_line_errors()==3);
    assert((arm_motion_fault_lsr()&0x10U) && arm_bus_tx_rx_error_events()==3U);++tests;

    reset();assert(arm_motion_start_visual(&visual_target,device.now)==0);
    while(strcmp(arm_motion_phase_name(),"close_gripper_once"))tick();
    device.inject_line_query=device.queries+1U;device.line_query_count=3;
    finish();assert(!strcmp(arm_motion_state_name(),"ERROR"));
    assert(device.stops==6 && device.stop_mask==0x7eU && arm_motion_query_retries()==2);
    assert(device.move[device.moves-1U].id==1 && device.move[device.moves-1U].position==600);
    assert(arm_motion_completed_actions()<arm_motion_action_count());++tests;
    ArmBusDiagnostic before_stop_done,after_stop_done;
    assert(arm_motion_get_bus_fault(&before_stop_done) && arm_bus_get_diagnostic(&current_bus));
    assert(before_stop_done.command==28U && before_stop_done.error_code==ARM_BUS_ERROR_LINE);
    assert(!strcmp(arm_bus_phase_name(before_stop_done.phase),"RECEIVE"));
    assert(before_stop_done.queued_bytes==6U && !before_stop_done.received_bytes && (before_stop_done.lsr&8U));
    assert(current_bus.command==12U && current_bus.servo_id==6U);
    for(unsigned i=0;i<100U;++i)tick();
    assert(arm_motion_get_bus_fault(&after_stop_done) && !memcmp(&before_stop_done,&after_stop_done,sizeof(before_stop_done)));
    puts("FROZEN_BUS_FAULT_PASS: actual WAIT_FIFO TX timeout and RECEIVE line/partial-reply faults retained after cancel and all six STOPs");
    puts("READ_LINE_FAILURE: three attempts max; permanent preflight fault sends no MOVE; post-close failure STOPs without release");

    reset();VisualPickTarget bad=visual_target;bad.y=400;
    assert(arm_motion_start_visual(&bad,device.now)!=0);
    assert(!device.moves && !device.queries && !device.stops);++tests;
    reset();assert(arm_motion_start_visual(&visual_target,device.now)==0);
    while(strcmp(arm_motion_phase_name(),"align_gripper_above"))tick();
    arm_motion_cancel();finish();assert(device.stops==6 && !strcmp(arm_motion_state_name(),"CANCELLED"));++tests;
    printf("PASS %u production bus/motion/IK integration scenarios; physical_hardware_access=false\n",tests);
    return 0;
}
