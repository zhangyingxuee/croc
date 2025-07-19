// Copyright (c) 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0/
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

#include "uart.h"
#include "print.h"
#include "gpio.h"
#include "util.h"
#include "config.h"
#include "timer.h"

#define TB_FREQUENCY 10000000
#define TB_BAUDRATE    115200

int main() {
    uart_init();

    printf("Testing Rom Function: \n");

    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x0));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x1));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x2));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x3));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x4));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x5));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x6));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x7));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x8));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0x9));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0xA));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0xB));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0xC));
    printf("%x\n", *reg8(USER_ROM_BASE_ADDR, 0xD));

    uart_write_flush();

    printf("Testing Single Log Function: \n");
    uint32_t test_input = 0x790000;
    printf("Testing input: 0x%x\n", test_input);
    uart_write_flush();

    printf("sending inputs...\n");
    uart_write_flush();
        // Write input to hardware module
    *reg32(USER_LOG_BASE_ADDR, 0x4) = test_input;
    
    printf("waiting...\n");
    uart_write_flush();
    // Wait for pipeline to complete (5 cycles + margin)
    for(volatile int j = 0; j < 200; j++) {
        asm volatile("nop");
    }
    
    // Read result from hardware
    printf("Reading result...\n");
    uart_write_flush();
    uint32_t hw_result = *reg32(USER_LOG_BASE_ADDR, 0x4);

    printf("Hardware result: 0x%x\n", hw_result);
    
    uart_write_flush();

    printf("Testing Pipeline...\n");
    uart_write_flush();

    uint32_t test_input0 = 0x800000;
    uint32_t test_input1 = 0x400000;
    uint32_t test_input2 = 0x200000;
    uint32_t test_input3 = 0x100000;
    uint32_t test_input4 = 0x820000;
    uint32_t test_input5 = 0x808000;
    uint32_t test_input6 = 0x808000;
    uint32_t test_input7 = 0x808000;
    

    printf("Sending Inputs...\n");
    uart_write_flush();

    int start_cycle = get_mcycle();
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input0;
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input1;
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input2;
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input3;
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input4;
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input5;
    asm volatile("nop");
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input6;
    asm volatile("nop");
    *reg32(USER_LOG_BASE_ADDR, 0x8) = test_input7;

    int end_cycle = get_mcycle();

    printf("Waiting...\n");
    for(volatile int j = 0; j < 200; j++) {
        asm volatile("nop");
    }

    printf("Reading results...\n");
    uart_write_flush();
    start_cycle = get_mcycle();
    uint32_t hw_result0 = *reg32(USER_LOG_BASE_ADDR, 0xC);
    uint32_t hw_result1 = *reg32(USER_LOG_BASE_ADDR, 0xC);
    uint32_t hw_result2 = *reg32(USER_LOG_BASE_ADDR, 0xC);
    uint32_t hw_result3 = *reg32(USER_LOG_BASE_ADDR, 0xC);
    uint32_t hw_result4 = *reg32(USER_LOG_BASE_ADDR, 0xC);
    uint32_t hw_result5 = *reg32(USER_LOG_BASE_ADDR, 0xC);
    uint32_t hw_result6 = *reg32(USER_LOG_BASE_ADDR, 0xC);
    uint32_t hw_result7 = *reg32(USER_LOG_BASE_ADDR, 0xC);

    end_cycle = get_mcycle();
    printf("Cycle number for one inference: %x\n", end_cycle - start_cycle);

    printf("Hardware result 0: 0x%x\n", hw_result0);
    printf("Hardware result 1: 0x%x\n", hw_result1);
    printf("Hardware result 2: 0x%x\n", hw_result2);
    printf("Hardware result 3: 0x%x\n", hw_result3);
    printf("Hardware result 4: 0x%x\n", hw_result4);
    printf("Hardware result 5: 0x%x\n", hw_result5);
    printf("Hardware result 6: 0x%x\n", hw_result6);
    printf("Hardware result 7: 0x%x\n", hw_result7);

    uart_write_flush();

    printf("Testing Single request AGAIN...\n");
    uart_write_flush();
    // Write input to hardware module
    *reg32(USER_LOG_BASE_ADDR, 0x4) = test_input3;
    
    printf("waiting...\n");
    uart_write_flush();
    // Wait for pipeline to complete (5 cycles + margin)
    for(volatile int j = 0; j < 200; j++) {
        asm volatile("nop");
    }
    
    // Read result from hardware
    printf("Reading result...\n");
    uart_write_flush();
    hw_result = *reg32(USER_LOG_BASE_ADDR, 0x4);

    printf("Hardware result: 0x%x\n", hw_result);
    
    uart_write_flush();
    return 1;
}
