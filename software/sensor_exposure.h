#ifndef SENSOR_EXPOSURE_H
#define SENSOR_EXPOSURE_H
#include <stdint.h>
/* SCCB uses the existing camera pins. PL grants ownership only after its ROM ends. */
#define HOST_ENABLE (1U<<16)
#define HOST_SCL_LOW (1U<<17)
#define HOST_SDA_LOW (1U<<18)
#define STATUS_SCL (1U<<10)
#define STATUS_SDA (1U<<11)
#define STATUS_INIT (1U<<12)
/* Values remain in the board-validated 0x41 divider's line units. Scaling is
 * derived afresh for each profile, so a failed switch cannot accumulate error. */
static unsigned exposure_lines[4]={1024,512,256,128};
static unsigned exposure_gain16=16;
static unsigned exposure_verified;
static unsigned active_mode;
static unsigned sensor_vts;
static unsigned verified_shutter,verified_gain;
/* These describe verified register programming, not a measured frame rate.
 * The caller must still validate complete captured frames before accepting a
 * faster profile. A failed switch clears the divider/rate until restoration. */
static unsigned sensor_clock_divider;
static unsigned camera_period_ms=400U;
static unsigned camera_expected_millifps;
static unsigned sensor_exposure_divisor=4U;
enum { SENSOR_PROFILE_NONE=0, SENSOR_PROFILE_FAST30=1, SENSOR_PROFILE_COMPACT11P7=2,
       SENSOR_PROFILE_BALANCED=3, SENSOR_PROFILE_BASELINE=4 };
static unsigned sensor_profile_id,sensor_hts,sensor_sysclk_hz;
static const char *sensor_profile_name(unsigned profile) {
    switch(profile){
    case SENSOR_PROFILE_FAST30:return "FAST30";
    case SENSOR_PROFILE_COMPACT11P7:return "COMPACT11P7";
    case SENSOR_PROFILE_BALANCED:return "BALANCED_3P3";
    case SENSOR_PROFILE_BASELINE:return "BASELINE_2P5";
    default:return "UNVERIFIED";
    }
}
/* Preview AXI master stays in reset until five gray frames validate. */
static unsigned gpio_word=0;
static void set_led(unsigned color) {
    gpio_word=(gpio_word&~(7U<<8))|color;
    Xil_Out32(GPIO_BASE,gpio_word);
}
static void bus_drive(unsigned scl_low,unsigned sda_low) {
    gpio_word=(gpio_word&~(HOST_SCL_LOW|HOST_SDA_LOW))|HOST_ENABLE;
    if(scl_low)gpio_word|=HOST_SCL_LOW;
    if(sda_low)gpio_word|=HOST_SDA_LOW;
    Xil_Out32(GPIO_BASE,gpio_word);
    usleep(10); /* Includes both GPIO CDC directions and weak-pullup rise time. */
}
static int bus_clock_high(unsigned sda_low) {
    bus_drive(0,sda_low);
    for(unsigned n=0;n<200;++n){
        if(Xil_In32(GPIO_BASE+8)&STATUS_SCL)return 0;
        usleep(10);
    }
    return -1;
}
static int bus_stop(void) {
    bus_drive(1,1);
    int result=bus_clock_high(1);
    bus_drive(0,0);
    return result;
}
static int bus_start(void) {
    bus_drive(0,0);
    if(bus_clock_high(0) || !(Xil_In32(GPIO_BASE+8)&STATUS_SDA))return -1;
    bus_drive(0,1);bus_drive(1,1);
    return 0;
}
static int bus_write_byte(unsigned value) {
    for(unsigned bit=0;bit<8;++bit){
        unsigned low=!(value&0x80U);
        bus_drive(1,low);
        if(bus_clock_high(low))return -1;
        bus_drive(1,low);value<<=1;
    }
    bus_drive(1,0);
    if(bus_clock_high(0))return -1;
    int nack=(Xil_In32(GPIO_BASE+8)&STATUS_SDA)!=0;
    bus_drive(1,0);
    return nack?-1:0;
}
static int bus_read_byte(unsigned *value) {
    unsigned result=0;
    for(unsigned bit=0;bit<8;++bit){
        bus_drive(1,0);
        if(bus_clock_high(0))return -1;
        result=(result<<1)|!!(Xil_In32(GPIO_BASE+8)&STATUS_SDA);
        bus_drive(1,0);
    }
    /* Single-byte read ends with master NACK, then STOP. */
    if(bus_clock_high(0))return -1;
    bus_drive(1,0);*value=result;return 0;
}
static int sensor_write_once(unsigned address,unsigned value) {
    int failed=bus_start() || bus_write_byte(0x78) ||
        bus_write_byte(address>>8) || bus_write_byte(address&255) || bus_write_byte(value);
    failed|=bus_stop();
    return failed?-1:0;
}
static int sensor_read_once(unsigned address,unsigned *value) {
    int failed=bus_start() || bus_write_byte(0x78) ||
        bus_write_byte(address>>8) || bus_write_byte(address&255);
    failed|=bus_stop();
    if(failed)return -1;
    failed=bus_start() || bus_write_byte(0x79) || bus_read_byte(value);
    failed|=bus_stop();
    return failed?-1:0;
}
/* Release a sensor left in an unfinished SCCB transaction, without resetting
 * the camera or the preview AXI masters. Each retry is explicitly bounded. */
static int bus_recover(void) {
    bus_drive(0,0);
    for(unsigned n=0;n<9;++n){
        if(Xil_In32(GPIO_BASE+8)&STATUS_SDA)break;
        bus_drive(1,0);
        if(bus_clock_high(0))return -1;
    }
    if(bus_stop())return -1;
    unsigned pins=Xil_In32(GPIO_BASE+8);
    return (pins&(STATUS_SCL|STATUS_SDA))==(STATUS_SCL|STATUS_SDA)?0:-1;
}
static int sensor_write(unsigned address,unsigned value) {
    for(unsigned attempt=1;attempt<=3;++attempt){
        if(!sensor_write_once(address,value))return 0;
        sample_log("SCCB_WRITE_RETRY,reg=0x%04x,value=0x%02x,attempt=%u,gpio=%08x\r\n",
                   address,value,attempt,(unsigned)Xil_In32(GPIO_BASE+8));
        if(attempt<3){bus_recover();usleep(2000);}
    }
    return -1;
}
static int sensor_read(unsigned address,unsigned *value) {
    for(unsigned attempt=1;attempt<=3;++attempt){
        if(!sensor_read_once(address,value))return 0;
        sample_log("SCCB_READ_RETRY,reg=0x%04x,attempt=%u,gpio=%08x\r\n",
                   address,attempt,(unsigned)Xil_In32(GPIO_BASE+8));
        if(attempt<3){bus_recover();usleep(2000);}
    }
    return -1;
}
static int sensor_read_exposure(unsigned *shutter,unsigned *gain) {
    unsigned a,b,c,d,e;
    if(sensor_read(0x3500,&a)||sensor_read(0x3501,&b)||sensor_read(0x3502,&c)||
       sensor_read(0x350a,&d)||sensor_read(0x350b,&e))return -1;
    *shutter=((a&15)<<12)|(b<<4)|(c>>4);
    *gain=((d&3)<<8)|e;
    return 0;
}
static int load_exposure_config(void) {
    FIL file;char text[128];UINT count=0;unsigned a,b,c,d,g;char extra;
    FRESULT result=f_open(&file,"0:/EXPOSURE.CFG",FA_READ);
    if(result==FR_NO_FILE){sample_log("EXPOSURE_CONFIG,defaults_baseline_2p5\r\n");return 0;}
    if(result!=FR_OK)return -1;
    result=f_read(&file,text,sizeof(text)-1,&count);
    FRESULT closed=f_close(&file);text[count]=0;
    if(result!=FR_OK || closed!=FR_OK || count==sizeof(text)-1)return -1;
    if(sscanf(text,"%u %u %u %u %u %c",&a,&b,&c,&d,&g,&extra)!=5)return -1;
    if(!(a>b && b>c && c>d && d>=1 && a<1964 && g>=16 && g<=64))return -1;
    exposure_lines[0]=a;exposure_lines[1]=b;exposure_lines[2]=c;exposure_lines[3]=d;exposure_gain16=g;
    sample_log("EXPOSURE_CONFIG,from_EXPOSURE.CFG\r\n");return 0;
}
static int sensor_initialize_host(void) {
    unsigned n,a,b;
    for(n=0;n<10000 && !(Xil_In32(GPIO_BASE+8)&STATUS_INIT);++n)usleep(1000);
    if(n==10000)return -1;
    bus_drive(0,0);
    if(sensor_read(0x300a,&a)||sensor_read(0x300b,&b)||a!=0x56||b!=0x40){
        sample_log("SENSOR_ID_FAIL\r\n");return -1;
    }
    if(sensor_read(0x380e,&a)||sensor_read(0x380f,&b))return -1;
    sensor_vts=(a<<8)|b;
    /* This is the previous stream's VTS, possibly COMPACT11P7 after a warm
     * processor reset. Validate the requested exposure only when configuring
     * its new profile, not against the previous profile's frame length. */
    if(sensor_vts<8)return -1;
    unsigned shutter,gain;
    if(sensor_read_exposure(&shutter,&gain))return -1;
    sample_log("SENSOR,OV5640,VTS=%u,previous_lines=%u,previous_gain16=%u\r\n",sensor_vts,shutter,gain);
    return 0;
}
/* All profiles rewrite this entire contract, including rollback after a partial
 * transaction. Baseline values match the frozen ROM, not the partially changed
 * sensor. 5001 keeps the same 1:1 central physical field in both windows.
 * COMPACT11P7 retains the board-tested BALANCED PLL/DVP clock path and uses
 * the smaller blanking window: SCLK=56M/3, HTS=1600, VTS=1000. The nominal
 * frame rate is 11.6667 Hz; complete gray and preview validation is mandatory.
 * FAST30 remains defined only for diagnostics, never selected at startup.
 * FAST30 reaches the sensor's DVP maximum; register checks do not prove that
 * this board's wiring is reliable at that frequency. */
static const unsigned sensor_profile_registers[][3]={
    {0x3034,0x1a,0x18},{0x3035,0x41,0x21},{0x3036,0x46,0x60},
    {0x3037,0x13,0x13},{0x3039,0x00,0x00},{0x3108,0x01,0x01},
    {0x3800,0x00,0x02},{0x3801,0x00,0x90},{0x3802,0x00,0x01},{0x3803,0x00,0xe8},
    {0x3804,0x0a,0x07},{0x3805,0x3f,0xaf},{0x3806,0x07,0x05},{0x3807,0x9f,0xb7},
    {0x3808,0x05,0x05},{0x3809,0x00,0x00},{0x380a,0x03,0x03},{0x380b,0xc0,0xc0},
    {0x380c,0x0b,0x06},{0x380d,0x1c,0x40},{0x380e,0x07,0x03},{0x380f,0xb0,0xe8},
    {0x3810,0x02,0x00},{0x3811,0xa0,0x10},{0x3812,0x01,0x00},{0x3813,0xf0,0x08},
    {0x3814,0x11,0x11},{0x3815,0x11,0x11},{0x3820,0x40,0x40},{0x3821,0x06,0x06},
    {0x3824,0x02,0x01},{0x4300,0x61,0x61},{0x460b,0x37,0x37},{0x460c,0x20,0x22},
    {0x4740,0x20,0x20},{0x5001,0xa3,0xa3},{0x501f,0x01,0x01},
    {0x3a00,0x78,0x78},{0x350c,0x00,0x00},{0x350d,0x00,0x00}
};
static int sensor_expect(unsigned address,unsigned expected) {
    unsigned actual;
    if(sensor_read(address,&actual)){
        sample_log("SENSOR_READ_FAIL,reg=0x%04x\r\n",address);return -1;
    }
    if(actual!=expected){
        sample_log("SENSOR_MODE_MISMATCH,reg=0x%04x,actual=0x%02x,expected=0x%02x\r\n",
                   address,actual,expected);return -1;
    }
    return 0;
}
static int sensor_write_verified(unsigned address,unsigned value) {
    if(sensor_write(address,value)){
        sample_log("SENSOR_WRITE_FAIL,reg=0x%04x\r\n",address);return -1;
    }
    return sensor_expect(address,value);
}
static void sensor_invalidate_profile(void) {
    exposure_verified=0;sensor_profile_id=SENSOR_PROFILE_NONE;
    sensor_clock_divider=camera_expected_millifps=sensor_vts=sensor_hts=sensor_sysclk_hz=0;
    verified_shutter=verified_gain=0;camera_period_ms=400U;sensor_exposure_divisor=4U;
}
static unsigned sensor_profile_value(unsigned index,unsigned profile) {
    unsigned address=sensor_profile_registers[index][0];
    unsigned fast=profile==SENSOR_PROFILE_FAST30 || profile==SENSOR_PROFILE_COMPACT11P7;
    unsigned value=sensor_profile_registers[index][fast?2:1];
    if(address==0x3035 && profile==SENSOR_PROFILE_BALANCED)value=0x31U;
    if(profile==SENSOR_PROFILE_COMPACT11P7){
        if(address==0x3034)value=0x1aU;
        if(address==0x3035)value=0x31U;
        if(address==0x3036)value=0x46U;
        if(address==0x3824)value=0x02U;
        if(address==0x460c)value=0x20U;
    }
    return value;
}
static unsigned sensor_short_exposure_lines(unsigned profile,unsigned mode) {
    static const unsigned lines_at_48mhz[4]={900U,450U,225U,112U};
    static const unsigned lines_at_56mhz_div3[4]={350U,175U,88U,44U};
    /* 85.714 us/line: 30, 15, 7.543 and 3.771 ms, nearest whole lines. */
    return profile==SENSOR_PROFILE_COMPACT11P7?lines_at_56mhz_div3[mode]:lines_at_48mhz[mode];
}
static int sensor_verify_shutter(unsigned lines,unsigned gain16) {
    unsigned manual,shutter,gain;
    if(sensor_read(0x3503,&manual)||sensor_read_exposure(&shutter,&gain))return -1;
    if(manual!=3U || shutter!=lines || gain!=gain16){
        sample_log("EXPOSURE_VERIFY_FAIL,manual=%u,lines=%u,gain16=%u,expected_lines=%u,expected_gain16=%u\r\n",
                   manual,shutter,gain,lines,gain16);return -1;
    }
    return 0;
}
static int sensor_program_shutter(unsigned lines,unsigned gain16) {
    unsigned encoded=lines<<4;
    if(sensor_write_verified(0x3503,3U) || sensor_write_verified(0x3500,(encoded>>16)&15U) ||
       sensor_write_verified(0x3501,(encoded>>8)&255U) || sensor_write_verified(0x3502,encoded&255U) ||
       sensor_write_verified(0x350a,(gain16>>8)&3U) || sensor_write_verified(0x350b,gain16&255U))return -1;
    return sensor_verify_shutter(lines,gain16);
}
static int apply_exposure(unsigned mode) {
    unsigned profile=sensor_profile_id;
    exposure_verified=0;
    if(mode>=4U || profile==SENSOR_PROFILE_NONE || sensor_vts<8U)return -1;
    unsigned fast=profile<=SENSOR_PROFILE_COMPACT11P7;
    unsigned lines=fast?sensor_short_exposure_lines(profile,mode):
        (exposure_lines[mode]*4U+sensor_exposure_divisor/2U)/sensor_exposure_divisor;
    unsigned gain=fast?111U:exposure_gain16;
    if(!lines || lines>=sensor_vts-4U || sensor_program_shutter(lines,gain))return -1;
    active_mode=mode;verified_shutter=lines;verified_gain=gain;exposure_verified=1;
    return 0;
}
static int sensor_configure_mode(unsigned profile) {
    sensor_invalidate_profile();
    if(profile<SENSOR_PROFILE_FAST30 || profile>SENSOR_PROFILE_BASELINE)return -1;
    unsigned fast=profile<=SENSOR_PROFILE_COMPACT11P7;
    unsigned divisor=profile==SENSOR_PROFILE_FAST30?2U:((profile==SENSOR_PROFILE_COMPACT11P7 || profile==SENSOR_PROFILE_BALANCED)?3U:4U);
    unsigned vts=fast?1000U:1968U;
    unsigned lines=fast?sensor_short_exposure_lines(profile,0U):(exposure_lines[0]*4U+divisor/2U)/divisor;
    unsigned gain=fast?111U:exposure_gain16;
    if(!lines || lines>=vts-4U || gain<16U || (!fast && gain>64U)){
        sample_log("SENSOR_PROFILE_EXPOSURE_REJECT,profile=%s,lines=%u,VTS=%u,gain16=%u\r\n",
                   sensor_profile_name(profile),lines,vts,gain);return -1;
    }
    unsigned power;
    if(sensor_read(0x3008,&power) || (power&0x80U))return -1;
    /* A failure leaves streaming inhibited whenever possible. A subsequent
     * mode request rewrites every changed register, irrespective of old state. */
    if(sensor_write_verified(0x3008,0x42U))return -1;
    usleep(10000);
    for(unsigned n=0;n<sizeof(sensor_profile_registers)/sizeof(sensor_profile_registers[0]);++n)
        if(sensor_write_verified(sensor_profile_registers[n][0],sensor_profile_value(n,profile)))return -1;
    if(sensor_program_shutter(lines,gain))return -1;
    usleep(10000);
    if(sensor_write_verified(0x3008,0x02U))return -1;
    usleep(20000);
    for(unsigned n=0;n<sizeof(sensor_profile_registers)/sizeof(sensor_profile_registers[0]);++n)
        if(sensor_expect(sensor_profile_registers[n][0],sensor_profile_value(n,profile)))return -1;
    if(sensor_verify_shutter(lines,gain) || sensor_expect(0x3008,0x02U))return -1;
    sensor_profile_id=profile;sensor_exposure_divisor=divisor;sensor_vts=vts;
    sensor_hts=fast?1600U:2844U;sensor_sysclk_hz=profile==SENSOR_PROFILE_FAST30?48000000U:56000000U/divisor;
    sensor_clock_divider=profile==SENSOR_PROFILE_FAST30?0x21U:((profile==SENSOR_PROFILE_COMPACT11P7 || profile==SENSOR_PROFILE_BALANCED)?0x31U:0x41U);
    camera_expected_millifps=fast?(profile==SENSOR_PROFILE_FAST30?30000U:11667U):
        (profile==SENSOR_PROFILE_BALANCED?3335U:2501U);
    camera_period_ms=fast?(profile==SENSOR_PROFILE_FAST30?34U:86U):
        (profile==SENSOR_PROFILE_BALANCED?300U:400U);
    active_mode=0;verified_shutter=lines;verified_gain=gain;exposure_verified=1;
    unsigned integration_us=(unsigned)((uint64_t)lines*sensor_hts*1000000U/sensor_sysclk_hz);
    sample_log("CAMERA_TIMING,profile=%s,3035=0x%02x,assumed_xclk_hz=24000000,sysclk_hz=%u,HTS=%u,VTS=%u,theoretical_millifps=%u,period_ms=%u,lines=%u,gain16=%u,integration_us=%u,register_verified=1,frame_probe_required=1,measured_rate_required=1\r\n",
        sensor_profile_name(profile),sensor_clock_divider,sensor_sysclk_hz,sensor_hts,sensor_vts,
        camera_expected_millifps,camera_period_ms,verified_shutter,verified_gain,integration_us);
    if(fast)sample_log("CAMERA_PHOTOMETRY,profile=%s,exposure_ms=30,gain16=111,custom_EXPOSURE_CFG_ignored=1,accuracy_impact_unmeasured=1\r\n",sensor_profile_name(profile));
    return 0;
}
/* Compatibility entry points used by initialization and older callers. */
static int sensor_configure_profile(unsigned divider) {
    if(divider==0x41U)return sensor_configure_mode(SENSOR_PROFILE_BASELINE);
    if(divider==0x31U)return sensor_configure_mode(SENSOR_PROFILE_BALANCED);
    sensor_invalidate_profile();return -1;
}
static int sensor_configure_baseline(void) {return sensor_configure_mode(SENSOR_PROFILE_BASELINE);}
static int sensor_configure_balanced(void) {return sensor_configure_mode(SENSOR_PROFILE_BALANCED);}
#endif
