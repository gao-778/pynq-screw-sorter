#ifndef ARM_BUS_H
#define ARM_BUS_H

#include <stdint.h>
#include <stddef.h>

/* Fusion hardware ABI: 100 MHz AXI UART16550, 115200 nominal (divisor 54).
 * The caller is the sole owner of these two peripherals. No interrupt handler,
 * other core, Linux driver or second task may access them concurrently. */
#define ARM_BUS_UART_BASE ((uintptr_t)0x43C00000U)
#define ARM_BUS_GPIO_BASE ((uintptr_t)0x41210000U)
/* Quiet time BEFORE each position QUERY, not after its final stop bit.
 * This spaces read traffic without slowing MOVE/STOP or delaying RX enable. */
#define ARM_BUS_QUERY_QUIET_US UINT64_C(2000)

typedef struct {
    uint32_t (*read32)(void *user, uintptr_t address);
    void (*write32)(void *user, uintptr_t address, uint32_t value);
    void *user;
} arm_bus_hal_t;

typedef enum {
    ARM_BUS_NONE = 0,
    ARM_BUS_BUSY,
    ARM_BUS_OK,
    ARM_BUS_RX_TIMEOUT,
    ARM_BUS_ERR
} arm_bus_result_t;

typedef enum {
    ARM_BUS_ERROR_NONE = 0,
    ARM_BUS_ERROR_NOT_INITIALIZED,
    ARM_BUS_ERROR_INITIALIZATION,
    ARM_BUS_ERROR_ARGUMENT,
    ARM_BUS_ERROR_TX_TIMEOUT,
    ARM_BUS_ERROR_LINE,
    ARM_BUS_ERROR_RX_BUDGET,
    ARM_BUS_ERROR_STALE_RX_BUDGET,
    ARM_BUS_ERROR_CLOCK,
    ARM_BUS_ERROR_CANCELLED,
    ARM_BUS_ERROR_RX_TIMEOUT
} arm_bus_error_t;

/* Captured state of one transaction, including terminal state before IDLE.
 * queued_bytes counts bytes written to THR, not bytes proven on the wire.
 * elapsed_us uses the last valid monotonic service time. No MMIO is performed
 * by diagnostic getters; a valid record is not a successful transaction. */
typedef struct ArmBusDiagnostic {
    unsigned valid, phase, command, servo_id, lsr, queued_bytes, received_bytes;
    uint64_t elapsed_us;
    unsigned error_code;
    /* Service-clock observations, NOT physical pin/byte arrival timestamps.
     * first_rx_elapsed_us is zero when no byte has been read. At the receive
     * deadline one bounded FIFO parse is allowed, without further waiting. */
    uint64_t max_service_gap_us, rx_enabled_elapsed_us, first_rx_elapsed_us;
    unsigned deadline_fifo_check, accepted_at_deadline;
} ArmBusDiagnostic;

/* Bounded register initialization/scratch check only: no servo packet is sent.
 * Call once before arm_motion_init(). The HAL is copied, not retained by pointer.
 * Returns 0 on success, -1 on invalid HAL or hardware readback failure. */
int arm_bus_init(const arm_bus_hal_t *hal);

/* One outstanding transaction. start_* returns 0 when accepted, -1 if invalid,
 * uninitialized or busy. A rejected start never changes an active transaction.
 * Reads/stops accept only installed unicast IDs 1..6. MOVE additionally requires
 * raw position 0..1000 and duration 10..30000 ms; motion applies joint limits.
 * A successful start replaces the prior completed result. No internal retry. */
int arm_bus_start_read(unsigned id, uint64_t now_us);
int arm_bus_start_move(unsigned id, unsigned position,
                       unsigned duration_ms, uint64_t now_us);
int arm_bus_start_stop(unsigned id, uint64_t now_us);

/* Service with a monotonic microsecond clock. No sleeps or unbounded polling.
 * While busy, poll promptly and defer slow UI, SD, logging and inference-control
 * work. In particular, delayed TEMT observation can lose an immediate reply.
 * FPGA video/inference continue independently. Each RX service reads <=32 bytes.
 * All terminal paths disable both TX/RX enables (GPIO=00).
 * RX_TIMEOUT means a complete query was transmitted AND RX was enabled.
 * The motion layer may retry position reads after RX_TIMEOUT or UART_LINE,
 * at most three attempts total. MOVE/STOP packets are never auto-replayed.
 * Each transaction clears stale RX only after TEMT, before sending its packet.
 * All commands clear invalid RX after TEMT and TX disable, before any QUERY
 * receiver enable. RX errors outside RECEIVE are diagnostic only; TX still
 * has its 50 ms deadline and requires TEMT. Once a QUERY enables RX, line and
 * parser validation remain strict and no valid reply is cleared.
 * At the RX deadline, inspect at most 32 already available bytes using the same
 * strict parser before timing out. This handles delayed CPU service; successful
 * late inspection is reported separately and does not prove when bytes arrived.
 * A successful MOVE only confirms transmission, never physical arrival. */
void arm_bus_service(uint64_t now_us);
int arm_bus_busy(void);
arm_bus_result_t arm_bus_result(void);
arm_bus_error_t arm_bus_error(void);
const char *arm_bus_error_name(void);
int arm_bus_position(void); /* Valid only after a successful position read. */
unsigned arm_bus_received_bytes(void);
unsigned arm_bus_last_lsr(void);

/* Boot diagnostics, reset only by successful arm_bus_init(). The event count
 * saturates and counts each transaction with observed invalid RX during TX
 * errors at most once, even when TX later times out. The LSR value is the OR
 * of full affected samples, not the current UART status. Genuine QUERY RECEIVE
 * errors are excluded. These counters do not confirm reception or arrival. */
unsigned arm_bus_tx_rx_error_events(void);
unsigned arm_bus_tx_rx_error_lsr(void);
int arm_bus_get_diagnostic(ArmBusDiagnostic *out);
const char *arm_bus_phase_name(unsigned phase);

/* Abort transport, clear pending FIFO bytes and disable both directions.
 * Does NOT stop physical movement or remove torque. Motion must then attempt
 * explicit STOP for each servo. A fresh start may follow cancellation. */
void arm_bus_cancel(void);

#endif
