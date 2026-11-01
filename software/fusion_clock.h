#ifndef FUSION_CLOCK_H
#define FUSION_CLOCK_H

#include <stdint.h>
#include "xiltimer.h"

/* Vitis 2026.1 expands COUNTS_PER_SECOND to CPU_FREQ/2 WITHOUT parentheses.
 * Capture its value first; never divide/modulo by that macro in an expression.
 * Split whole seconds and remainder to avoid multiplying the full tick count.
 * Preserve genuine backwards clock readings for the motion safety check.
 */
static inline uint64_t fusion_ticks_us(uint64_t ticks)
{
    const uint64_t hz = (COUNTS_PER_SECOND);
    return (ticks / hz) * UINT64_C(1000000) +
           (ticks % hz) * UINT64_C(1000000) / hz;
}

static inline unsigned fusion_ticks_ms(uint64_t ticks)
{
    const uint64_t hz = (COUNTS_PER_SECOND);
    return (unsigned)((ticks / hz) * UINT64_C(1000) +
                      (ticks % hz) * UINT64_C(1000) / hz);
}

#endif
