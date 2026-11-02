#ifndef ARM_BUS_H
#define ARM_BUS_H

#include <stdint.h>
#include <stddef.h>

#define ARM_BUS_UART_BASE ((uintptr_t)0x43C00000U)
#define ARM_BUS_GPIO_BASE ((uintptr_t)0x41210000U)


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

typedef struct ArmBusDiagnostic {
    unsigned valid, phase, command, servo_id, lsr, queued_bytes, received_bytes;
    uint64_t elapsed_us;
    unsigned error_code;

    uint64_t max_service_gap_us, rx_enabled_elapsed_us, first_rx_elapsed_us;
    unsigned deadline_fifo_check, accepted_at_deadline;
} ArmBusDiagnostic;

int arm_bus_init(const arm_bus_hal_t *hal);

int arm_bus_start_read(unsigned id, uint64_t now_us);
int arm_bus_start_move(unsigned id, unsigned position,
                       unsigned duration_ms, uint64_t now_us);
int arm_bus_start_stop(unsigned id, uint64_t now_us);

void arm_bus_service(uint64_t now_us);
int arm_bus_busy(void);
arm_bus_result_t arm_bus_result(void);
arm_bus_error_t arm_bus_error(void);
const char *arm_bus_error_name(void);
int arm_bus_position(void);  
unsigned arm_bus_received_bytes(void);
unsigned arm_bus_last_lsr(void);

unsigned arm_bus_tx_rx_error_events(void);
unsigned arm_bus_tx_rx_error_lsr(void);
int arm_bus_get_diagnostic(ArmBusDiagnostic *out);
const char *arm_bus_phase_name(unsigned phase);

void arm_bus_cancel(void);

#endif
