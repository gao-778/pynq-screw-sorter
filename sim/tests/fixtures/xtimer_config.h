/******************************************************************************
* Copyright (c) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
#ifndef _XTIMER_CONFIG_H
#define _XTIMER_CONFIG_H

#include "xparameters.h"

#define XSLEEPTIMER_FREQ	     XPAR_CPU_CORE_CLOCK_FREQ_HZ/2
#define COUNTS_PER_SECOND       XSLEEPTIMER_FREQ
#define XTIMER_IS_DEFAULT_TIMER 1
 
/* #undef XTIMER_DEFAULT_TIMER_IS_MB_RISCV */

#define XTIMER_NO_TICK_TIMER   1

#endif  
