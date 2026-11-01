#include "arm_bus.h"
#include <string.h>

#define UART_DATA 0x1000U
#define UART_IER  0x1004U
#define UART_FCR  0x1008U
#define UART_LCR  0x100CU
#define UART_MCR  0x1010U
#define UART_LSR  0x1014U
#define UART_SCR  0x101CU
#define LSR_DR   0x01U
#define LSR_ERR  0x1EU
#define LSR_THRE 0x20U
#define LSR_TEMT 0x40U
#define LSR_RX_FIFO_ERROR 0x80U
#define TX_TIMEOUT_US 50000ULL
#define RX_TIMEOUT_US 100000ULL
#define TX_SETUP_US 10ULL
#define RX_BYTE_LIMIT 256U
#define SERVICE_BYTE_LIMIT 32U

typedef enum {
    PHASE_IDLE,
    PHASE_WAIT_IDLE,
    PHASE_DRAIN,
    PHASE_SETUP,
    PHASE_WAIT_FIFO,
    PHASE_WAIT_SENT,
    PHASE_RECEIVE
} bus_phase_t;

static arm_bus_hal_t io;
static int initialized;
static bus_phase_t phase;
static arm_bus_result_t result_code;
static arm_bus_error_t error_code;
static uint8_t transmit[10], receive[8];
static unsigned transmit_size, receive_size, stale_count, receive_count;
static unsigned wanted_id, wanted_command, lsr_snapshot;
static unsigned tx_rx_error_events, tx_rx_error_lsr, tx_rx_error_seen;
static unsigned transmit_queued;
static ArmBusDiagnostic diagnostic;
static int position_value;
static uint64_t transaction_started, phase_started, last_service;
static uint64_t max_service_gap, rx_enabled_elapsed, first_rx_elapsed;
static unsigned deadline_fifo_check, accepted_at_deadline;

static uint32_t read_uart(unsigned offset)
{
    return io.read32(io.user, ARM_BUS_UART_BASE + offset) & 0xFFU;
}

static void write_uart(unsigned offset, unsigned value)
{
    io.write32(io.user, ARM_BUS_UART_BASE + offset, value);
}

static void direction(unsigned value)
{
    io.write32(io.user, ARM_BUS_GPIO_BASE, value);
}

static void capture_diagnostic(arm_bus_error_t error)
{
    diagnostic.valid = 1U;
    diagnostic.phase = (unsigned)phase;
    diagnostic.command = wanted_command;
    diagnostic.servo_id = wanted_id;
    diagnostic.lsr = lsr_snapshot;
    diagnostic.queued_bytes = transmit_queued;
    diagnostic.received_bytes = receive_count;
    diagnostic.elapsed_us = last_service >= transaction_started ?
                            last_service - transaction_started : 0U;
    diagnostic.error_code = (unsigned)error;
    diagnostic.max_service_gap_us = max_service_gap;
    diagnostic.rx_enabled_elapsed_us = rx_enabled_elapsed;
    diagnostic.first_rx_elapsed_us = first_rx_elapsed;
    diagnostic.deadline_fifo_check = deadline_fifo_check;
    diagnostic.accepted_at_deadline = accepted_at_deadline;
}

static void finish(arm_bus_result_t result, arm_bus_error_t error)
{
    capture_diagnostic(error);
    direction(0);
    phase = PHASE_IDLE;
    result_code = result;
    error_code = error;
}

static void record_transmit_rx_error(void)
{
    if (phase != PHASE_RECEIVE &&
        (lsr_snapshot & (LSR_ERR | LSR_RX_FIFO_ERROR))) {
        /* Count affected transactions, not repeated polls of a sticky LSR. */
        if (!tx_rx_error_seen) {
            if (tx_rx_error_events != ~0U) ++tx_rx_error_events;
            tx_rx_error_seen = 1U;
        }
        tx_rx_error_lsr |= lsr_snapshot;
    }
}

static int line_status(void)
{
    lsr_snapshot = read_uart(UART_LSR);
    if (phase != PHASE_RECEIVE) {
        /* RX is disabled during every command's TX, including QUERY. Those
         * samples cannot describe TX progress; THRE/TEMT still must pass. */
        record_transmit_rx_error();
        return 0;
    }
    if (lsr_snapshot & LSR_ERR) {
        finish(ARM_BUS_ERR, ARM_BUS_ERROR_LINE);
        return -1;
    }
    return 0;
}

int arm_bus_init(const arm_bus_hal_t *hal)
{
    unsigned old_scratch, i;
    static const unsigned patterns[] = {0x00U, 0x55U, 0xAAU, 0xFFU};
    if (arm_bus_busy()) return -1;
    initialized = 0;
    phase = PHASE_IDLE;
    result_code = ARM_BUS_ERR;
    error_code = ARM_BUS_ERROR_INITIALIZATION;
    if (!hal || !hal->read32 || !hal->write32) return -1;
    io = *hal;
    direction(0);
    io.write32(io.user, ARM_BUS_GPIO_BASE + 4U, 0U);
    old_scratch = read_uart(UART_SCR);
    for (i = 0; i < sizeof(patterns) / sizeof(patterns[0]); ++i) {
        write_uart(UART_SCR, patterns[i]);
        if (read_uart(UART_SCR) != patterns[i]) {
            write_uart(UART_SCR, old_scratch);
            return -1;
        }
    }
    write_uart(UART_SCR, old_scratch);
    write_uart(UART_LCR, 0x03U); /* Clear DLAB before disabling interrupts. */
    write_uart(UART_IER, 0x00U);
    write_uart(UART_LCR, 0x83U);
    write_uart(UART_DATA, 54U); /* DLL, not THR, while DLAB is set. */
    write_uart(UART_IER, 0U);
    write_uart(UART_LCR, 0x03U);
    write_uart(UART_MCR, 0U);
    write_uart(UART_FCR, 0x07U);
    if (read_uart(UART_LCR) != 0x03U) return -1;
    initialized = 1;
    result_code = ARM_BUS_NONE;
    error_code = ARM_BUS_ERROR_NONE;
    position_value = 0;
    lsr_snapshot = receive_count = stale_count = receive_size = 0;
    tx_rx_error_events = tx_rx_error_lsr = tx_rx_error_seen = 0;
    transmit_queued = 0;
    max_service_gap = rx_enabled_elapsed = first_rx_elapsed = 0U;
    deadline_fifo_check = accepted_at_deadline = 0U;
    memset(&diagnostic, 0, sizeof(diagnostic));
    return 0;
}

static int start(unsigned id, unsigned command, unsigned position,
                 unsigned duration, uint64_t now_us)
{
    unsigned sum, i;
    if (arm_bus_busy()) return -1;
    /* An invalid new request must not expose the preceding transaction. */
    memset(&diagnostic, 0, sizeof(diagnostic));
    diagnostic.valid = 1U;
    diagnostic.command = command;
    diagnostic.servo_id = id;
    if (!initialized) {
        result_code = ARM_BUS_ERR;
        error_code = ARM_BUS_ERROR_NOT_INITIALIZED;
        diagnostic.error_code = (unsigned)error_code;
        return -1;
    }
    if (id < 1U || id > 6U ||
        (command == 1U && (position > 1000U || duration < 10U || duration > 30000U))) {
        result_code = ARM_BUS_ERR;
        error_code = ARM_BUS_ERROR_ARGUMENT;
        diagnostic.error_code = (unsigned)error_code;
        direction(0);
        return -1;
    }
    wanted_id = id;
    wanted_command = command;
    transmit[0] = transmit[1] = 0x55U;
    transmit[2] = (uint8_t)id;
    transmit[3] = (uint8_t)(command == 1U ? 7U : 3U);
    transmit[4] = (uint8_t)command;
    transmit_size = command == 1U ? 10U : 6U;
    if (command == 1U) {
        transmit[5] = (uint8_t)position;
        transmit[6] = (uint8_t)(position >> 8);
        transmit[7] = (uint8_t)duration;
        transmit[8] = (uint8_t)(duration >> 8);
    }
    sum = 0;
    for (i = 2; i < transmit_size - 1U; ++i) sum += transmit[i];
    transmit[transmit_size - 1U] = (uint8_t)~sum;
    receive_size = receive_count = stale_count = 0;
    transmit_queued = 0;
    lsr_snapshot = 0;
    tx_rx_error_seen = 0;
    position_value = 0;
    transaction_started = phase_started = last_service = now_us;
    max_service_gap = rx_enabled_elapsed = first_rx_elapsed = 0U;
    deadline_fifo_check = accepted_at_deadline = 0U;
    direction(0);
    error_code = ARM_BUS_ERROR_NONE;
    result_code = ARM_BUS_BUSY;
    phase = PHASE_WAIT_IDLE;
    return 0;
}

int arm_bus_start_read(unsigned id, uint64_t now_us)
{
    return start(id, 28U, 0U, 0U, now_us);
}

int arm_bus_start_move(unsigned id, unsigned position, unsigned duration_ms,
                       uint64_t now_us)
{
    return start(id, 1U, position, duration_ms, now_us);
}

int arm_bus_start_stop(unsigned id, uint64_t now_us)
{
    return start(id, 12U, 0U, 0U, now_us);
}

static void drop_receive_byte(void)
{
    if (receive_size) {
        --receive_size;
        memmove(receive, receive + 1, receive_size);
    }
}

static int consume_byte(uint8_t byte)
{
    unsigned i, sum, raw;
    /* The parser retains at most seven bytes between calls. */
    receive[receive_size++] = byte;
    while (receive_size) {
        if (receive[0] != 0x55U) { drop_receive_byte(); continue; }
        if (receive_size < 2U) return 0;
        if (receive[1] != 0x55U) { drop_receive_byte(); continue; }
        if (receive_size < 4U) return 0;
        if (receive[2] != wanted_id || receive[3] != 5U) {
            drop_receive_byte(); continue;
        }
        if (receive_size < 5U) return 0;
        if (receive[4] != wanted_command) { drop_receive_byte(); continue; }
        if (receive_size < 8U) return 0;
        sum = 0;
        for (i = 2; i < 8U; ++i) sum += receive[i];
        if ((sum & 0xFFU) != 0xFFU) { drop_receive_byte(); continue; }
        raw = (unsigned)receive[5] | ((unsigned)receive[6] << 8);
        position_value = (raw & 0x8000U) ? (int)raw - 65536 : (int)raw;
        receive_size = 0;
        return 1;
    }
    return 0;
}

void arm_bus_service(uint64_t now_us)
{
    unsigned i, receive_expired;
    if (!arm_bus_busy()) return;
    if (now_us < last_service) {
        finish(ARM_BUS_ERR, ARM_BUS_ERROR_CLOCK);
        return;
    }
    if (now_us-last_service > max_service_gap) max_service_gap = now_us-last_service;
    last_service = now_us;
    if (phase != PHASE_RECEIVE && now_us - transaction_started >= TX_TIMEOUT_US) {
        finish(ARM_BUS_ERR, ARM_BUS_ERROR_TX_TIMEOUT);
        return;
    }
    receive_expired = phase == PHASE_RECEIVE && now_us-phase_started >= RX_TIMEOUT_US;
    if (receive_expired) deadline_fifo_check = 1U;
    /* A completed prior response, idle noise or a receiver error may still be
     * in the RX FIFO. Before a new packet, wait for the actual transmitter to
     * empty, then clear RX only. Never reset or discard an unfinished TX.
     * Only PHASE_RECEIVE contains valid reply bytes. All transmit phases record
     * invalid RX errors but still require actual THRE/TEMT before completion. */
    if (phase != PHASE_WAIT_IDLE && line_status()) return;
    switch (phase) {
    case PHASE_WAIT_IDLE:
        lsr_snapshot = read_uart(UART_LSR);
        record_transmit_rx_error();
        if (wanted_command == 28U &&
            now_us-transaction_started < ARM_BUS_QUERY_QUIET_US) break;
        if (lsr_snapshot & LSR_TEMT) {
            write_uart(UART_FCR, 0x03U); /* FIFO enable + RX reset; TX unchanged. */
            phase = PHASE_DRAIN;
        }
        break;
    case PHASE_DRAIN:
        for (i = 0; i < SERVICE_BYTE_LIMIT; ++i) {
            if (line_status()) return;
            if (!(lsr_snapshot & LSR_DR)) {
                direction(1);
                phase_started = now_us;
                phase = PHASE_SETUP;
                return;
            }
            (void)read_uart(UART_DATA);
            if (++stale_count >= RX_BYTE_LIMIT) {
                finish(ARM_BUS_ERR, ARM_BUS_ERROR_STALE_RX_BUDGET);
                return;
            }
        }
        break;
    case PHASE_SETUP:
        if (now_us - phase_started >= TX_SETUP_US) phase = PHASE_WAIT_FIFO;
        break;
    case PHASE_WAIT_FIFO:
        if (lsr_snapshot & LSR_THRE) {
            /* Complete supported packets fit in the 16-byte hardware FIFO. */
            for (i = 0; i < transmit_size; ++i) {
                write_uart(UART_DATA, transmit[i]);
                ++transmit_queued;
            }
            phase = PHASE_WAIT_SENT;
        }
        break;
    case PHASE_WAIT_SENT:
        if (lsr_snapshot & LSR_TEMT) {
            direction(0);
            /* The command's final stop bit is sent and RX is still disabled.
             * Clear only invalid RX FIFO/status now; never after enabling RX.
             * The hardware RX mask holds its internal UART input high outside
             * receive windows, preventing a partial noise byte crossing here. */
            write_uart(UART_FCR, 0x03U);
            lsr_snapshot = read_uart(UART_LSR);
            record_transmit_rx_error();
            if (wanted_command == 28U) {
                /* No slow work or further RX cleanup after this boundary. */
                direction(2);
                rx_enabled_elapsed = now_us-transaction_started;
                phase_started = now_us;
                phase = PHASE_RECEIVE;
            } else {
                finish(ARM_BUS_OK, ARM_BUS_ERROR_NONE);
            }
        }
        break;
    case PHASE_RECEIVE:
        for (i = 0; i < SERVICE_BYTE_LIMIT; ++i) {
            if (line_status()) return;
            if (!(lsr_snapshot & LSR_DR)) {
                if (receive_expired) finish(ARM_BUS_RX_TIMEOUT, ARM_BUS_ERROR_RX_TIMEOUT);
                return;
            }
            if (!receive_count) first_rx_elapsed = now_us-transaction_started;
            ++receive_count;
            if (consume_byte((uint8_t)read_uart(UART_DATA))) {
                accepted_at_deadline = receive_expired;
                finish(ARM_BUS_OK, ARM_BUS_ERROR_NONE);
                return;
            }
            if (receive_count >= RX_BYTE_LIMIT) {
                finish(ARM_BUS_ERR, ARM_BUS_ERROR_RX_BUDGET);
                return;
            }
        }
        /* A delayed service may find a complete reply already in the FIFO.
         * Parse only this normal bounded batch; never extend the wait window.
         * LINE and byte-budget failures above retain their strict precedence. */
        if (receive_expired) finish(ARM_BUS_RX_TIMEOUT, ARM_BUS_ERROR_RX_TIMEOUT);
        break;
    default:
        finish(ARM_BUS_ERR, ARM_BUS_ERROR_NOT_INITIALIZED);
        break;
    }
}

int arm_bus_busy(void) { return result_code == ARM_BUS_BUSY; }
arm_bus_result_t arm_bus_result(void) { return result_code; }
arm_bus_error_t arm_bus_error(void) { return error_code; }
int arm_bus_position(void) { return position_value; }
unsigned arm_bus_received_bytes(void) { return receive_count; }
unsigned arm_bus_last_lsr(void) { return lsr_snapshot; }
unsigned arm_bus_tx_rx_error_events(void) { return tx_rx_error_events; }
unsigned arm_bus_tx_rx_error_lsr(void) { return tx_rx_error_lsr; }

int arm_bus_get_diagnostic(ArmBusDiagnostic *out)
{
    if (arm_bus_busy()) capture_diagnostic(error_code);
    if (out) *out = diagnostic;
    return (int)diagnostic.valid;
}

const char *arm_bus_phase_name(unsigned value)
{
    static const char *const names[] = {
        "IDLE", "WAIT_IDLE", "DRAIN", "SETUP", "WAIT_FIFO", "WAIT_SENT", "RECEIVE"
    };
    return value < sizeof(names) / sizeof(names[0]) ? names[value] : "UNKNOWN";
}

void arm_bus_cancel(void)
{
    if (!initialized) return;
    capture_diagnostic(ARM_BUS_ERROR_CANCELLED);
    direction(0);
    write_uart(UART_FCR, 0x07U);
    phase = PHASE_IDLE;
    receive_size = 0;
    result_code = ARM_BUS_ERR;
    error_code = ARM_BUS_ERROR_CANCELLED;
}

const char *arm_bus_error_name(void)
{
    static const char *const names[] = {
        "NONE", "NOT_INITIALIZED", "INITIALIZATION", "ARGUMENT", "TX_TIMEOUT",
        "UART_LINE", "RX_BUDGET", "STALE_RX_BUDGET", "CLOCK_REVERSED",
        "CANCELLED", "RX_TIMEOUT"
    };
    unsigned error = (unsigned)error_code;
    return error < sizeof(names) / sizeof(names[0]) ? names[error] : "UNKNOWN";
}
