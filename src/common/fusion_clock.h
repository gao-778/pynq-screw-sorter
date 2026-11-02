/* Convert timer ticks through a captured frequency to preserve units and avoid overflow. */
#ifndef FUSION_CLOCK_H
#define FUSION_CLOCK_H

#include <stdint.h>
#include "xiltimer.h"

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
