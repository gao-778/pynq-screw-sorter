#include "../software/arm_bus.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define DATA 0x1000U
#define IER  0x1004U
#define FCR  0x1008U
#define LCR  0x100CU
#define MCR  0x1010U
#define LSR  0x1014U
#define SCR  0x101CU

typedef struct {
    uint64_t now, tx_end, tx_enabled_at, first_tx_at;
    uint8_t rx[1024], tx[1024], response[128], wire[128];
    unsigned rx_head, rx_tail, tx_count, response_size;
    unsigned direction, dll, dlm, lcr, ier, mcr, scr;
    unsigned gpio_writes, fcr_writes, rx_enables, line_error, sticky_rx_error;
    unsigned hold_busy, bad_scratch, bad_lcr, wrong_order;
    unsigned thre_early, inject_rx_error_at_byte, tx_disable_before_empty;
    unsigned post_tx_rx_resets;
    uint64_t last_tx_disable_at;
    uint64_t reply_start_at, reply_delay_us, rx_enabled_at, first_reply_delivered_at;
    unsigned wire_size, wire_index, wire_scheduled, wire_inflight, wire_captured;
    unsigned wire_delivered, wire_lost;
} mock_t;

static mock_t mock;
static unsigned tests;

static void queue_byte(unsigned byte)
{
    assert(mock.rx_tail < sizeof(mock.rx));
    mock.rx[mock.rx_tail++] = (uint8_t)byte;
}

/* The servo starts replying relative to the last transmitted stop bit, not
 * relative to our receiver enable. Apply past events using the old direction
 * before each GPIO write: missed start bits stay lost and cannot be replayed.
 * UART bytes last 87 us; the byte is captured only if RX was open at its start
 * and remains open through its end. FIFO stress tests also inject bytes below. */
static void pump_wire(void)
{
    uint64_t byte_start, byte_end;
    if (!mock.wire_scheduled || mock.hold_busy) return;
    while (mock.wire_index < mock.wire_size) {
        byte_start = mock.reply_start_at + 87U * mock.wire_index;
        byte_end = byte_start + 87U;
        if (!mock.wire_inflight) {
            if (mock.now < byte_start) return;
            mock.wire_captured = mock.direction == 2U;
            mock.wire_inflight = 1U;
        }
        if (mock.now < byte_end) return;
        if (mock.wire_captured) {
            queue_byte(mock.wire[mock.wire_index]);
            if (!mock.wire_delivered) mock.first_reply_delivered_at = byte_end;
            ++mock.wire_delivered;
        } else ++mock.wire_lost;
        ++mock.wire_index;
        mock.wire_inflight = 0U;
    }
    mock.wire_scheduled = 0U;
}

static uint32_t mock_read(void *user, uintptr_t address)
{
    mock_t *m = user;
    unsigned offset;
    assert(m == &mock);
    pump_wire();
    assert(address >= ARM_BUS_UART_BASE);
    offset = (unsigned)(address - ARM_BUS_UART_BASE);
    switch (offset) {
    case DATA:
        if (m->lcr & 0x80U) return m->dll;
        assert(m->rx_head < m->rx_tail);
        return m->rx[m->rx_head++];
    case IER: return (m->lcr & 0x80U) ? m->dlm : m->ier;
    case LCR: return m->bad_lcr ? 0U : m->lcr;
    case MCR: return m->mcr;
    case SCR: return m->bad_scratch ? 0U : m->scr;
    case LSR:
        return m->line_error | m->sticky_rx_error |
            ((m->now >= m->tx_end && !m->hold_busy) ? 0x60U : 0U) |
            ((m->thre_early && !m->hold_busy) ? 0x20U : 0U) |
            (m->rx_head < m->rx_tail ? 1U : 0U);
    default: assert(0); return 0;
    }
}

static void mock_write(void *user, uintptr_t address, uint32_t value)
{
    mock_t *m = user;
    unsigned offset;
    assert(m == &mock);
    pump_wire();
    if (address == ARM_BUS_GPIO_BASE + 4U) { assert(value == 0U); return; }
    if (address == ARM_BUS_GPIO_BASE) {
        assert(value < 3U); /* Mutual exclusion must hold at every write. */
        if (!value && m->direction == 1U) {
            m->last_tx_disable_at = m->now;
            if (m->now < m->tx_end || m->hold_busy) ++m->tx_disable_before_empty;
        }
        if (value == 1U) { assert(m->direction == 0U); m->tx_enabled_at = m->now; }
        if (value == 2U) {
            assert(m->direction == 0U);
            assert(m->now >= m->tx_end);
            ++m->rx_enables;
            m->rx_enabled_at = m->now;
        }
        if (m->direction == 2U && value != 2U && m->wire_inflight)
            m->wire_captured = 0U;
        m->direction = value;
        ++m->gpio_writes;
        return;
    }
    assert(address >= ARM_BUS_UART_BASE);
    offset = (unsigned)(address - ARM_BUS_UART_BASE);
    switch (offset) {
    case DATA:
        if (m->lcr & 0x80U) { m->dll = value; break; }
        assert(m->direction == 1U);
        assert(m->now - m->tx_enabled_at >= 10U);
        assert(m->tx_count < sizeof(m->tx));
        if (!m->tx_count) m->first_tx_at = m->now;
        m->tx[m->tx_count++] = (uint8_t)value;
        if (m->inject_rx_error_at_byte == m->tx_count) {
            m->sticky_rx_error = 0x88U;
            queue_byte(0x00U); /* Invalid RX while the command is still sending. */
        }
        if (m->tx_end < m->now) m->tx_end = m->now;
        m->tx_end += 87U; /* 10 bits at approximately 115200 baud. */
        if (m->tx_count >= 6U && m->tx_count == (unsigned)m->tx[3] + 3U &&
            m->tx[4] == 28U) {
            memcpy(m->wire, m->response, m->response_size);
            m->wire_size = m->response_size;
            m->reply_start_at = m->tx_end + m->reply_delay_us;
            m->wire_index = m->wire_inflight = m->wire_captured = 0U;
            m->wire_delivered = m->wire_lost = 0U;
            m->first_reply_delivered_at = 0U;
            m->wire_scheduled = 1U;
        }
        break;
    case IER:
        if (m->lcr & 0x80U) m->dlm = value; else m->ier = value;
        break;
    case LCR: m->lcr = value; break;
    case MCR: m->mcr = value; break;
    case SCR: m->scr = value; break;
    case FCR:
        assert(value == 7U || value == 3U);
        if(value == 3U) {
            assert(m->now>=m->tx_end && !m->hold_busy && !m->direction);
            if(m->tx_count)++m->post_tx_rx_resets;
        }
        ++m->fcr_writes;
        m->rx_head = m->rx_tail = 0;
        m->sticky_rx_error = 0;
        if(value & 4U)m->tx_end = m->now;
        break;
    default: assert(0);
    }
}

static arm_bus_hal_t hal = {mock_read, mock_write, &mock};

static void reset_mock(void)
{
    if (arm_bus_busy()) arm_bus_cancel();
    memset(&mock, 0, sizeof(mock));
    mock.now = 1000U;
    mock.reply_delay_us = 20U;
    assert(arm_bus_init(&hal) == 0);
    assert(mock.tx_count == 0 && mock.direction == 0);
    assert(mock.dll == 54U && mock.dlm == 0 && mock.lcr == 3U && mock.ier == 0);
    assert(arm_bus_result() == ARM_BUS_NONE);
    assert(!arm_bus_tx_rx_error_events() && !arm_bus_tx_rx_error_lsr());
}

static void step(unsigned us)
{
    mock.now += us;
    arm_bus_service(mock.now);
}

static void finish_transaction(unsigned budget)
{
    unsigned count = 0;
    while (arm_bus_busy() && count++ < budget) step(10);
    assert(!arm_bus_busy());
    assert(mock.direction == 0U);
}

static void response(unsigned id, int position)
{
    unsigned raw = (unsigned)position & 0xFFFFU, sum = 0, i;
    uint8_t *p = mock.response;
    p[0] = p[1] = 0x55U; p[2] = (uint8_t)id; p[3] = 5; p[4] = 28;
    p[5] = (uint8_t)raw; p[6] = (uint8_t)(raw >> 8);
    for (i = 2; i < 7; ++i) sum += p[i];
    p[7] = (uint8_t)~sum;
    mock.response_size = 8;
}

static void expect_packet(unsigned id, unsigned cmd, unsigned position, unsigned duration)
{
    unsigned size = cmd == 1U ? 10U : 6U, sum = 0, i;
    assert(mock.tx_count == size);
    assert(mock.tx[0] == 0x55 && mock.tx[1] == 0x55);
    assert(mock.tx[2] == id && mock.tx[3] == size - 3U && mock.tx[4] == cmd);
    if (cmd == 1U) {
        assert(mock.tx[5] == (position & 255U) && mock.tx[6] == position >> 8);
        assert(mock.tx[7] == (duration & 255U) && mock.tx[8] == duration >> 8);
    }
    for (i = 2; i < size; ++i) sum += mock.tx[i];
    assert((sum & 255U) == 255U);
}

static void test_init_and_arguments(void)
{
    reset_mock();
    assert(arm_bus_init(NULL) < 0);
    assert(arm_bus_start_read(1, mock.now) < 0);
    assert(arm_bus_error() == ARM_BUS_ERROR_NOT_INITIALIZED);
    reset_mock();
    assert(arm_bus_start_read(0, mock.now) < 0);
    assert(arm_bus_start_read(7, mock.now) < 0);
    assert(arm_bus_start_stop(254, mock.now) < 0);
    assert(arm_bus_start_move(1, 1001, 300, mock.now) < 0);
    assert(arm_bus_start_move(1, 200, 9, mock.now) < 0);
    assert(arm_bus_start_move(1, 200, 30001, mock.now) < 0);
    assert(mock.tx_count == 0U && mock.direction == 0U);
    mock.bad_scratch = 1;
    assert(arm_bus_init(&hal) < 0 && mock.direction == 0U && mock.tx_count == 0U);
    reset_mock(); mock.bad_lcr = 1;
    assert(arm_bus_init(&hal) < 0 && mock.direction == 0U && mock.tx_count == 0U);
    ++tests;
}

static void test_move_and_stop(void)
{
    unsigned id;
    for (id = 1; id <= 6; ++id) {
        reset_mock();
        assert(arm_bus_start_move(id, 600, 800, mock.now) == 0);
        assert(arm_bus_start_move(id, 200, 300, mock.now) < 0);
        assert(arm_bus_init(&hal) < 0); /* Cannot reinitialize an active transfer. */
        assert(arm_bus_result() == ARM_BUS_BUSY);
        finish_transaction(1000);
        assert(arm_bus_result() == ARM_BUS_OK && mock.rx_enables == 0U);
        expect_packet(id, 1, 600, 800);
        reset_mock();
        assert(arm_bus_start_stop(id, mock.now) == 0);
        finish_transaction(1000);
        assert(arm_bus_result() == ARM_BUS_OK && mock.rx_enables == 0U);
        expect_packet(id, 12, 0, 0);
    }
    ++tests;
}

static void test_positions(void)
{
    static const int positions[] = {0, 500, 1026, -1, -32768, 32767};
    unsigned k;
    for (k = 0; k < sizeof(positions) / sizeof(positions[0]); ++k) {
        reset_mock(); response(k + 1U, positions[k]);
        queue_byte(0x12); queue_byte(0x55); /* Stale bytes must drain before TX. */
        assert(arm_bus_start_read(k + 1U, mock.now) == 0);
        finish_transaction(1000);
        assert(arm_bus_result() == ARM_BUS_OK && mock.rx_enables == 1U);
        assert(arm_bus_position() == positions[k]);
        assert(arm_bus_received_bytes() == 8U);
        expect_packet(k + 1U, 28, 0, 0);
    }
    ++tests;
}

static void test_stream_resynchronization(void)
{
    uint8_t good[8];
    reset_mock(); response(3, 721); memcpy(good, mock.response, 8);
    memset(mock.response, 0, sizeof(mock.response));
    mock.response[0] = 0x12;
    memcpy(mock.response + 1, good, 8); mock.response[3] = 4; /* Wrong ID. */
    memcpy(mock.response + 9, good, 8); mock.response[12] = 32; /* Wrong length. */
    memcpy(mock.response + 17, good, 8); mock.response[21] = 1; /* Wrong command. */
    memcpy(mock.response + 25, good, 8); mock.response[32] ^= 1; /* Bad checksum. */
    memcpy(mock.response + 33, good, 8); mock.response_size = 41;
    assert(arm_bus_start_read(3, mock.now) == 0);
    finish_transaction(1000);
    assert(arm_bus_result() == ARM_BUS_OK && arm_bus_position() == 721);
    assert(arm_bus_received_bytes() == 41U);
    ++tests;
}

static void test_partial_reply(void)
{
    uint8_t checksum;
    unsigned polls = 0;
    reset_mock(); response(1, 238); checksum = mock.response[7]; mock.response_size = 7;
    assert(arm_bus_start_read(1, mock.now) == 0);
    while (!mock.rx_enables) step(10);
    while (arm_bus_received_bytes() < 7U && polls++ < 100U) step(10);
    assert(arm_bus_busy() && arm_bus_received_bytes() == 7U);
    step(1000); queue_byte(checksum); step(10);
    assert(arm_bus_result() == ARM_BUS_OK && arm_bus_position() == 238);
    assert(mock.direction == 0U);
    ++tests;
}

static void test_rx_timeout(void)
{
    reset_mock(); response(2, 500); mock.response_size = 7;
    assert(arm_bus_start_read(2, mock.now) == 0);
    finish_transaction(11000);
    assert(arm_bus_result() == ARM_BUS_RX_TIMEOUT);
    assert(arm_bus_error() == ARM_BUS_ERROR_RX_TIMEOUT);
    assert(mock.rx_enables == 1U && arm_bus_received_bytes() == 7U);
    expect_packet(2, 28, 0, 0); /* No automatic retransmission. */
    ++tests;
}

static void test_tx_timeouts(void)
{
    reset_mock(); mock.hold_busy = 1;
    assert(arm_bus_start_read(1, mock.now) == 0);
    finish_transaction(6000);
    assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_TX_TIMEOUT);
    assert(mock.tx_count == 0U && mock.rx_enables == 0U);
    reset_mock();
    assert(arm_bus_start_read(1, mock.now) == 0);
    while (!mock.tx_count) step(10);
    mock.hold_busy = 1; finish_transaction(6000);
    assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_TX_TIMEOUT);
    assert(mock.tx_count == 6U && mock.rx_enables == 0U);
    ++tests;
}

static void test_line_errors(void)
{
    unsigned flag;
    for (flag = 2; flag <= 16; flag <<= 1) {
        reset_mock(); assert(arm_bus_start_read(2, mock.now) == 0);
        while (!mock.rx_enables) step(10);
        mock.line_error = flag; step(10);
        assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_LINE);
        assert(arm_bus_last_lsr() & flag); assert(mock.direction == 0U);
    }
    ++tests;
}

static void test_budgets(void)
{
    unsigned i, count;
    reset_mock();
    assert(arm_bus_start_read(1, mock.now) == 0);
    step(10); /* First TEMT boundary clears stale RX before any transmit. */
    for (i = 0; i < 300; ++i) queue_byte(0xAA);
    finish_transaction(100);
    assert(arm_bus_error() == ARM_BUS_ERROR_STALE_RX_BUDGET && mock.tx_count == 0U);
    reset_mock(); assert(arm_bus_start_read(1, mock.now) == 0);
    while (!mock.rx_enables) step(10);
    for (i = 0; i < 300; ++i) queue_byte(0x55);
    count = mock.rx_head; step(10);
    assert(mock.rx_head - count <= 32U && arm_bus_busy());
    finish_transaction(100);
    assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_RX_BUDGET);
    assert(arm_bus_received_bytes() == 256U);
    ++tests;
}

static void test_rx_recovery(void)
{
    unsigned resets;
    reset_mock(); response(2,500); queue_byte(0x00);mock.sticky_rx_error=0x08U;
    resets=mock.fcr_writes;
    assert(arm_bus_start_read(2,mock.now)==0);finish_transaction(1000);
    assert(arm_bus_result()==ARM_BUS_OK && arm_bus_position()==500);
    assert(mock.fcr_writes==resets+2U && !mock.sticky_rx_error);

    /* An error belonging to the current response must never be accepted. */
    mock.tx_count=0;assert(arm_bus_start_read(2,mock.now)==0);
    resets=mock.rx_enables;while(mock.rx_enables==resets)step(10);
    mock.sticky_rx_error=0x08U;step(10);
    assert(arm_bus_result()==ARM_BUS_ERR && arm_bus_error()==ARM_BUS_ERROR_LINE);
    assert(arm_bus_last_lsr()&0x08U);
    /* A fresh transaction clears the stale errored FIFO without reinit. */
    mock.tx_count=0;assert(arm_bus_start_read(2,mock.now)==0);
    finish_transaction(1000);assert(arm_bus_result()==ARM_BUS_OK);

    reset_mock();mock.tx_end=mock.now+1000U;queue_byte(0x00);mock.sticky_rx_error=0x08U;
    resets=mock.fcr_writes;response(1,231);
    assert(arm_bus_start_read(1,mock.now)==0);step(500);
    assert(arm_bus_busy() && !mock.tx_count && mock.fcr_writes==resets);
    finish_transaction(1000);assert(arm_bus_result()==ARM_BUS_OK);
    ++tests;
}

static void test_cancel_and_clock(void)
{
    unsigned i;
    for (i = 0; i < 3; ++i) {
        reset_mock(); assert(arm_bus_start_read(2, mock.now) == 0);
        if (i == 1) while (!mock.tx_count) step(10);
        if (i == 2) while (!mock.rx_enables) step(10);
        arm_bus_cancel();
        assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_CANCELLED);
        assert(mock.direction == 0U && !arm_bus_busy());
        mock.tx_count = 0;
        assert(arm_bus_start_stop(2, mock.now) == 0);
        finish_transaction(1000); expect_packet(2, 12, 0, 0);
    }
    reset_mock(); assert(arm_bus_start_move(1, 600, 800, mock.now) == 0);
    arm_bus_service(mock.now - 1U);
    assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_CLOCK);
    assert(mock.direction == 0U && mock.tx_count == 0U);
    ++tests;
}

static void start_nonreply(unsigned command)
{
    if (command == 1U) assert(arm_bus_start_move(3, 80, 300, mock.now) == 0);
    else if (command == 28U) assert(arm_bus_start_read(3, mock.now) == 0);
    else assert(arm_bus_start_stop(3, mock.now) == 0);
}

static void add_framing_noise(void)
{
    mock.sticky_rx_error = 0x88U;
    queue_byte(0U);
}

static void test_nonreply_noise_all_phases(void)
{
    static const unsigned commands[] = {1U, 12U, 28U};
    unsigned command, index, stage;
    for (index = 0; index < sizeof(commands)/sizeof(commands[0]); ++index) {
        command = commands[index];
        for (stage = 0; stage < 6; ++stage) {
            reset_mock();
            response(3, 80);
            if (stage == 4U) mock.inject_rx_error_at_byte = 5U;
            start_nonreply(command);
            if (stage == 1U) step(10); /* After initial clear, in RX drain. */
            if (stage == 2U) { step(10); step(10); } /* Direction=TX, setup. */
            if (stage == 3U) { step(10); step(10); step(10); } /* WAIT_FIFO. */
            if (stage >= 4U) while (!mock.tx_count) step(10);
            if (stage != 4U) add_framing_noise();
            if (stage >= 4U) {
                unsigned resets = mock.fcr_writes;
                assert(mock.now < mock.tx_end && mock.direction == 1U);
                step(10);
                assert(arm_bus_busy() && arm_bus_last_lsr() == 0x89U);
                assert(mock.fcr_writes == resets && mock.direction == 1U);
                /* THRE alone must not complete a packet whose shift register
                 * is still transmitting its final byte. */
                mock.thre_early = 1U;
                while (mock.now + 10U < mock.tx_end) {
                    step(10);
                    assert(arm_bus_busy() && mock.direction == 1U);
                    assert(mock.fcr_writes == resets);
                    assert(arm_bus_tx_rx_error_events() == 1U);
                }
            }
            finish_transaction(1000);
            assert(arm_bus_result() == ARM_BUS_OK && arm_bus_error() == ARM_BUS_ERROR_NONE);
            expect_packet(3, command, 80, 300); /* Exactly one complete packet. */
            assert(arm_bus_tx_rx_error_events() == 1U);
            assert((arm_bus_tx_rx_error_lsr() & 0x89U) == 0x89U);
            assert(mock.rx_enables == (command == 28U ? 1U : 0U));
            assert(!mock.sticky_rx_error && mock.rx_head == mock.rx_tail);
            if (command == 28U) assert(arm_bus_position() == 80 && arm_bus_received_bytes() == 8U);
            assert(mock.post_tx_rx_resets == 1U && !mock.tx_disable_before_empty);
            assert(mock.last_tx_disable_at >= mock.tx_end);
        }
    }
    ++tests;
    puts("ARM_BUS_CHECK_PASS all_commands_noise_all_six_tx_phases");
}

static void test_nonreply_error_flags(void)
{
    static const unsigned commands[] = {1U, 12U, 28U};
    unsigned command, index, flag;
    for (index = 0; index < sizeof(commands)/sizeof(commands[0]); ++index) {
        command = commands[index];
        for (flag = 2; flag <= 128; flag <<= 1) {
            if (flag == 32U || flag == 64U) continue;
            reset_mock(); response(3, 80); start_nonreply(command);
            while (!mock.tx_count) step(10);
            mock.sticky_rx_error = flag;
            finish_transaction(1000);
            assert(arm_bus_result() == ARM_BUS_OK);
            expect_packet(3, command, 80, 300);
            assert(arm_bus_tx_rx_error_events() == 1U);
            assert(arm_bus_tx_rx_error_lsr() & flag);
            assert(!mock.tx_disable_before_empty && mock.post_tx_rx_resets == 1U);
        }
    }
    ++tests;
    puts("ARM_BUS_CHECK_PASS all_commands_tx_rx_error_flags");
}

static void test_nonreply_noise_tx_timeout(void)
{
    static const unsigned commands[] = {1U, 12U, 28U};
    unsigned command, index, after_enqueue;
    for (index = 0; index < sizeof(commands)/sizeof(commands[0]); ++index) {
        command = commands[index];
        for (after_enqueue = 0; after_enqueue < 2; ++after_enqueue) {
            uint64_t started;
            unsigned resets;
            ArmBusDiagnostic fault;
            reset_mock(); started = mock.now; start_nonreply(command);
            if (after_enqueue) while (!mock.tx_count) step(10);
            add_framing_noise(); mock.hold_busy = 1;
            resets = mock.fcr_writes;
            finish_transaction(6000);
            assert(mock.now - started == 50000U);
            assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_TX_TIMEOUT);
            assert(mock.fcr_writes == resets && !mock.rx_enables);
            assert(arm_bus_get_diagnostic(&fault) && fault.command == command && fault.servo_id == 3U);
            assert(!strcmp(arm_bus_phase_name(fault.phase), after_enqueue ? "WAIT_SENT" : "WAIT_IDLE"));
            assert(fault.error_code == ARM_BUS_ERROR_TX_TIMEOUT && fault.elapsed_us == 50000U);
            assert(fault.queued_bytes == (after_enqueue ? (command == 1U ? 10U : 6U) : 0U));
            assert(!fault.received_bytes && (fault.lsr & 0x89U) == 0x89U);
            assert(arm_bus_tx_rx_error_events() == 1U);
            assert((arm_bus_tx_rx_error_lsr() & 0x89U) == 0x89U);
            if (after_enqueue) expect_packet(3, command, 80, 300);
            else assert(!mock.tx_count);
            step(100000); /* A later idle transmitter must not retry/complete. */
            assert(arm_bus_result() == ARM_BUS_ERR);
            if (after_enqueue) expect_packet(3, command, 80, 300);
            else assert(!mock.tx_count);
        }
    }
    ++tests;
    puts("ARM_BUS_CHECK_PASS noisy_tx_still_times_out_at_50ms_without_retry");
}

static void test_nonreply_stale_drain_stays_bounded(void)
{
    unsigned i;
    reset_mock(); start_nonreply(1);
    step(10); /* Add noise after the initial reset so actual drain is tested. */
    mock.sticky_rx_error = 8U;
    for (i = 0; i < 300; ++i) queue_byte(0U);
    step(10);
    assert(mock.rx_head == 32U && arm_bus_busy());
    finish_transaction(100);
    assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_STALE_RX_BUDGET);
    assert(!mock.tx_count && mock.rx_head == 256U && arm_bus_tx_rx_error_events() == 1U);
    ++tests;
    puts("ARM_BUS_CHECK_PASS noisy_stale_drain_bounded");
}

static void test_query_strict_after_nonreply_noise(void)
{
    ArmBusDiagnostic fault;
    reset_mock(); start_nonreply(1);
    while (!mock.tx_count) step(10);
    add_framing_noise(); finish_transaction(1000);
    assert(arm_bus_result() == ARM_BUS_OK && arm_bus_tx_rx_error_events() == 1U);
    mock.tx_count = 0; mock.post_tx_rx_resets = 0; response(3, 80);
    assert(arm_bus_start_read(3, mock.now) == 0);
    finish_transaction(1000);
    assert(arm_bus_result() == ARM_BUS_OK && arm_bus_position() == 80);
    assert(mock.rx_enables == 1U && arm_bus_received_bytes() == 8U);
    assert(mock.post_tx_rx_resets == 1U); /* Before RX only; wire reply runs independently. */
    assert(arm_bus_tx_rx_error_events() == 1U);
    reset_mock(); response(3, 80);
    assert(arm_bus_start_read(3, mock.now) == 0);
    while (!mock.rx_enables) step(10);
    mock.sticky_rx_error = 8U;
    step(10);
    assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_LINE);
    assert(!arm_bus_tx_rx_error_events() && !arm_bus_tx_rx_error_lsr());
    assert(mock.post_tx_rx_resets == 1U && mock.direction == 0U);
    assert(arm_bus_get_diagnostic(&fault));
    assert(!strcmp(arm_bus_phase_name(fault.phase), "RECEIVE") && fault.command == 28U && fault.servo_id == 3U);
    assert(fault.error_code == ARM_BUS_ERROR_LINE && fault.queued_bytes == 6U && !fault.received_bytes);
    assert((fault.lsr & 8U) && fault.elapsed_us > 0U);
    ++tests;
    puts("ARM_BUS_CHECK_PASS query_strict_no_valid_reply_reset");
}

static void test_noise_diagnostic_lifetime(void)
{
    unsigned first_lsr;
    reset_mock(); start_nonreply(1);
    while (!mock.tx_count) step(10);
    add_framing_noise(); finish_transaction(1000);
    assert(arm_bus_tx_rx_error_events() == 1U);
    first_lsr = arm_bus_tx_rx_error_lsr();
    assert((first_lsr & 0x89U) == 0x89U);
    assert(arm_bus_start_move(3, 1001, 300, mock.now) < 0);
    assert(arm_bus_tx_rx_error_events() == 1U && arm_bus_tx_rx_error_lsr() == first_lsr);
    arm_bus_cancel();
    assert(arm_bus_tx_rx_error_events() == 1U && arm_bus_tx_rx_error_lsr() == first_lsr);
    mock.tx_count = 0; start_nonreply(12);
    while (!mock.tx_count) step(10);
    mock.sticky_rx_error = 4U; finish_transaction(1000);
    assert(arm_bus_result() == ARM_BUS_OK && arm_bus_tx_rx_error_events() == 2U);
    assert((arm_bus_tx_rx_error_lsr() & (first_lsr | 4U)) == (first_lsr | 4U));
    assert(arm_bus_init(&hal) == 0);
    assert(!arm_bus_tx_rx_error_events() && !arm_bus_tx_rx_error_lsr());
    ++tests;
    puts("ARM_BUS_CHECK_PASS boot_cumulative_diagnostics_lifetime");
}

static void test_transaction_diagnostic_lifetime(void)
{
    ArmBusDiagnostic current, frozen;
    reset_mock();
    assert(!arm_bus_get_diagnostic(&current) && !current.valid);
    assert(!arm_bus_get_diagnostic(NULL));
    assert(arm_bus_start_read(2, mock.now) == 0);
    while (!mock.tx_count) step(10);
    assert(arm_bus_get_diagnostic(&current) && current.command == 28U && current.servo_id == 2U);
    assert(!strcmp(arm_bus_phase_name(current.phase), "WAIT_SENT") && current.queued_bytes == 6U);
    /* BUSY rejection must preserve the active transaction and its diagnostic. */
    assert(arm_bus_start_stop(6, mock.now) < 0);
    assert(arm_bus_get_diagnostic(&frozen) && !memcmp(&current, &frozen, sizeof(current)));
    finish_transaction(11000);
    assert(arm_bus_result() == ARM_BUS_RX_TIMEOUT && arm_bus_get_diagnostic(&frozen));
    assert(frozen.error_code == ARM_BUS_ERROR_RX_TIMEOUT && frozen.queued_bytes == 6U);
    assert(frozen.command == 28U && frozen.servo_id == 2U && !frozen.received_bytes);
    assert(!strcmp(arm_bus_phase_name(frozen.phase), "RECEIVE") && frozen.elapsed_us >= 100000U);
    arm_bus_cancel();
    mock.tx_count = 0; assert(arm_bus_start_stop(2, mock.now) == 0); finish_transaction(1000);
    assert(arm_bus_get_diagnostic(&current) && current.command == 12U && current.error_code == ARM_BUS_ERROR_NONE);
    assert(frozen.command == 28U && frozen.error_code == ARM_BUS_ERROR_RX_TIMEOUT); /* Caller copy is stable. */
    assert(arm_bus_start_move(6, 1001, 300, mock.now) < 0);
    assert(arm_bus_get_diagnostic(&current) && current.command == 1U && current.servo_id == 6U);
    assert(current.error_code == ARM_BUS_ERROR_ARGUMENT && !current.queued_bytes && !current.elapsed_us);
    assert(!strcmp(arm_bus_phase_name(999U), "UNKNOWN"));
    ++tests;
    puts("ARM_BUS_CHECK_PASS exact_transaction_diagnostic_lifetime");
}

static void enter_receive(void)
{
    unsigned polls = 0;
    assert(arm_bus_start_read(3, mock.now) == 0);
    while (!mock.rx_enables && arm_bus_busy() && polls++ < 1000U) step(10);
    assert(mock.rx_enables == 1U && mock.direction == 2U && arm_bus_busy());
    assert(!mock.rx_tail && !arm_bus_received_bytes());
}

static void test_deadline_fifo_strict_bounded(void)
{
    ArmBusDiagnostic diag;
    uint8_t good[8];
    unsigned scenario, i;
    uint64_t started;
    /* Full valid, partial, bad CRC, wrong ID, no reply, and a real line error.
     * The wire completes while the CPU is not servicing the receive phase. */
    for (scenario = 0U; scenario < 6U; ++scenario) {
        reset_mock(); response(3, 721); started = mock.now;
        if (scenario == 1U) mock.response_size = 7U;
        if (scenario == 2U) mock.response[7] ^= 1U;
        if (scenario == 3U) response(4, 721);
        if (scenario == 4U) mock.response_size = 0U;
        enter_receive();
        if (scenario == 5U) mock.line_error = 8U;
        step(100000U); /* Exactly the existing RX timeout, with no intermediate service. */
        assert(!arm_bus_busy() && !mock.direction && arm_bus_get_diagnostic(&diag));
        assert(diag.deadline_fifo_check == 1U);
        assert(diag.max_service_gap_us == 100000U);
        assert(diag.rx_enabled_elapsed_us == mock.rx_enabled_at - started);
        assert(diag.elapsed_us == diag.rx_enabled_elapsed_us + 100000U);
        assert(diag.queued_bytes == 6U && mock.tx_count == 6U);
        if (!scenario) {
            assert(arm_bus_result() == ARM_BUS_OK && arm_bus_position() == 721);
            assert(diag.accepted_at_deadline == 1U && diag.received_bytes == 8U);
            assert(diag.first_rx_elapsed_us == diag.elapsed_us);
            assert(mock.wire_delivered == 8U && !mock.wire_lost);
            assert(mock.first_reply_delivered_at < mock.now - 99000U);
        } else {
            assert(!diag.accepted_at_deadline);
            if (scenario == 5U) {
                assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_LINE);
                assert(!diag.received_bytes && !diag.first_rx_elapsed_us && (diag.lsr & 8U));
            } else {
                assert(arm_bus_result() == ARM_BUS_RX_TIMEOUT);
                assert(arm_bus_error() == ARM_BUS_ERROR_RX_TIMEOUT);
                assert(diag.received_bytes == (scenario == 1U ? 7U : (scenario == 4U ? 0U : 8U)));
                assert(diag.first_rx_elapsed_us == (scenario == 4U ? 0U : diag.elapsed_us));
            }
            /* No extra wait and no resurrection after the deadline, even when
             * a later byte would complete the previously partial response. */
            queue_byte(mock.response[7]); step(1000U);
            assert(!arm_bus_busy() && arm_bus_result() != ARM_BUS_OK);
            assert(mock.tx_count == 6U);
        }
    }
    /* FIFO stress injection verifies the normal 32-byte service budget also
     * bounds deadline parsing. A good frame beyond that batch is not accepted. */
    reset_mock(); response(3, 721); memcpy(good, mock.response, sizeof(good));
    mock.response_size = 0U; enter_receive();
    for (i = 0U; i < 33U; ++i) queue_byte(0xAAU);
    for (i = 0U; i < sizeof(good); ++i) queue_byte(good[i]);
    step(100000U);
    assert(arm_bus_result() == ARM_BUS_RX_TIMEOUT && arm_bus_received_bytes() == 32U);
    assert(mock.rx_head == 32U && mock.rx_tail == 41U);
    assert(arm_bus_get_diagnostic(&diag) && diag.deadline_fifo_check && !diag.accepted_at_deadline);

    /* Exhausting the transaction's 256-byte noise budget still reports the
     * original budget error, including on the final bounded deadline batch. */
    reset_mock(); enter_receive();
    for (i = 0U; i < 255U; ++i) queue_byte(0xAAU);
    for (i = 0U; i < 8U; ++i) step(10U);
    assert(arm_bus_busy() && arm_bus_received_bytes() == 255U);
    queue_byte(0xAAU); step(100000U);
    assert(arm_bus_result() == ARM_BUS_ERR && arm_bus_error() == ARM_BUS_ERROR_RX_BUDGET);
    assert(arm_bus_received_bytes() == 256U);
    assert(arm_bus_get_diagnostic(&diag) && diag.deadline_fifo_check && !diag.accepted_at_deadline);
    ++tests;
    puts("ARM_BUS_CHECK_PASS deadline_fifo_strict_bounded");
}

static void test_wire_timing_no_replay(void)
{
    unsigned delay;
    ArmBusDiagnostic diag;
    /* Ordinary prompt service opens RX before an independently scheduled reply.
     * Enabling RX cannot itself deliver even the first byte. */
    reset_mock(); response(3, 721); enter_receive();
    assert(mock.reply_start_at == mock.tx_end + 20U);
    assert(mock.rx_enabled_at < mock.reply_start_at);
    assert(mock.wire_delivered == 0U && mock.wire_lost == 0U);
    finish_transaction(1000U);
    assert(arm_bus_result() == ARM_BUS_OK && arm_bus_received_bytes() == 8U);
    assert(mock.first_reply_delivered_at == mock.reply_start_at + 87U);
    assert(arm_bus_get_diagnostic(&diag) && !diag.deadline_fifo_check && !diag.accepted_at_deadline);

    /* Delay observation of TEMT, rather than delaying the servo's wire clock.
     * 1 ms misses part of the response; 2 ms misses the entire response. Lost
     * bytes stay lost after RX enable and are never replayed by the mock. */
    for (delay = 1000U; delay <= 2000U; delay += 1000U) {
        reset_mock(); response(3, 721);
        assert(arm_bus_start_read(3, mock.now) == 0);
        while (!mock.tx_count) step(10U);
        assert(mock.direction == 1U && mock.now < mock.tx_end);
        step(delay);
        assert(mock.rx_enables == 1U && mock.direction == 2U && !mock.rx_tail);
        finish_transaction(11000U);
        assert(arm_bus_result() == ARM_BUS_RX_TIMEOUT && mock.wire_lost > 0U);
        assert(mock.wire_delivered + mock.wire_lost == 8U);
        assert(arm_bus_received_bytes() == mock.wire_delivered && mock.wire_delivered < 8U);
        if (delay == 2000U) assert(mock.wire_lost == 8U && !mock.wire_delivered);
        assert(arm_bus_get_diagnostic(&diag) && diag.max_service_gap_us == delay);
        assert(diag.deadline_fifo_check && !diag.accepted_at_deadline && mock.tx_count == 6U);
    }
    ++tests;
    puts("ARM_BUS_CHECK_PASS wire_timing_independent_tx_end_no_replay");
}

static void test_service_observation_diagnostics(void)
{
    ArmBusDiagnostic diag, frozen;
    uint64_t started;
    reset_mock(); response(3, 721); started = mock.now;
    enter_receive();
    step(1000U); /* All bytes are buffered by now, within the normal deadline. */
    assert(arm_bus_result() == ARM_BUS_OK && arm_bus_get_diagnostic(&diag));
    assert(diag.max_service_gap_us == 1000U);
    assert(diag.rx_enabled_elapsed_us == mock.rx_enabled_at - started);
    assert(diag.first_rx_elapsed_us == mock.now - started);
    assert(!diag.deadline_fifo_check && !diag.accepted_at_deadline);
    frozen = diag; step(200000U);
    assert(arm_bus_get_diagnostic(&diag) && !memcmp(&diag, &frozen, sizeof(diag)));
    mock.tx_count = 0U; mock.response_size = 0U;
    assert(arm_bus_start_read(3, mock.now) == 0);
    assert(arm_bus_get_diagnostic(&diag));
    assert(!diag.max_service_gap_us && !diag.rx_enabled_elapsed_us && !diag.first_rx_elapsed_us);
    assert(!diag.deadline_fifo_check && !diag.accepted_at_deadline);
    step(37U); assert(arm_bus_get_diagnostic(&diag) && diag.max_service_gap_us == 37U);
    arm_bus_service(mock.now - 1U);
    assert(arm_bus_error() == ARM_BUS_ERROR_CLOCK && arm_bus_get_diagnostic(&diag));
    assert(diag.max_service_gap_us == 37U && diag.elapsed_us == 37U);
    assert(arm_bus_init(&hal) == 0 && !arm_bus_get_diagnostic(&diag));
    assert(!diag.max_service_gap_us && !diag.rx_enabled_elapsed_us && !diag.first_rx_elapsed_us);
    assert(!diag.deadline_fifo_check && !diag.accepted_at_deadline);
    ++tests;
    puts("ARM_BUS_CHECK_PASS service_observation_diagnostics_lifetime");
}

int main(void)
{
    test_init_and_arguments();
    test_move_and_stop();
    test_positions();
    test_stream_resynchronization();
    test_partial_reply();
    test_rx_timeout();
    test_tx_timeouts();
    test_line_errors();
    test_rx_recovery();
    test_budgets();
    test_cancel_and_clock();
    test_nonreply_noise_all_phases();
    test_nonreply_error_flags();
    test_nonreply_noise_tx_timeout();
    test_nonreply_stale_drain_stays_bounded();
    test_query_strict_after_nonreply_noise();
    test_noise_diagnostic_lifetime();
    test_transaction_diagnostic_lifetime();
    test_deadline_fifo_strict_bounded();
    test_wire_timing_no_replay();
    test_service_observation_diagnostics();
    printf("ARM_BUS_TEST_PASS groups=%u hardware_access=false\n", tests);
    return 0;
}
