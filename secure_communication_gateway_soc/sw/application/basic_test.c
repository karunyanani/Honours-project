/* =============================================================================
 * basic_test.c  –  Basic RISC-V C Code Test for Gateway SoC
 *
 * Exercises core CPU and SoC functionality:
 *   1. ALU arithmetic, bitwise logic, and shifts (RV32I core instructions)
 *   2. Function calls, stack frame allocation, and recursion (fibonacci)
 *   3. Data Memory (DMEM) write, readback, and byte/half/word store strobes
 *   4. GPIO output direction and pin pattern driving
 *   5. Hardware Timer countdown verification
 *   6. UART status formatting and reporting
 * =============================================================================
 */

#include <stdint.h>
#include "soc_map.h"
#include "uart.h"
#include "gpio.h"
#include "timer.h"

#define BAUD_DIV_FAST 4u /* 4 clock cycles per bit for simulation */

/* --------------------------------------------------------------------------
 * UART Formatting Helpers
 * -------------------------------------------------------------------------- */
static void print_str(const char *s)
{
    uart_puts(s);
}

__attribute__((unused)) static void print_hex(uint32_t val)
{
    static const char hex_digits[] = "0123456789ABCDEF";
    char buf[11];
    buf[0] = '0';
    buf[1] = 'x';
    for (int i = 7; i >= 0; i--) {
        buf[2 + (7 - i)] = hex_digits[(val >> (i * 4)) & 0x0F];
    }
    buf[10] = '\0';
    uart_puts(buf);
}

static void print_dec(uint32_t val)
{
    char buf[12];
    int idx = 10;
    buf[11] = '\0';

    if (val == 0) {
        uart_putc('0');
        return;
    }

    while (val > 0 && idx >= 0) {
        buf[idx--] = (char)('0' + (val % 10));
        val /= 10;
    }
    uart_puts(&buf[idx + 1]);
}

/* --------------------------------------------------------------------------
 * Test 1: Core ALU & Arithmetic Operations
 * -------------------------------------------------------------------------- */
static int test_alu(void)
{
    volatile int32_t a = 1250;
    volatile int32_t b = 375;
    volatile int32_t add_res = a + b;         /* 1625 */
    volatile int32_t sub_res = a - b;         /* 875 */
    /* (1250 << 3) | (375 >> 2) = 10000 | 93 = 0x2710 | 0x005D = 0x275D = 10077 */
    volatile uint32_t shift_res = ((uint32_t)a << 3) | ((uint32_t)b >> 2);
    volatile uint32_t logic_res = (a ^ b) & 0x0FFF; /* 1250 ^ 375 = 0x04E2 ^ 0x0177 = 0x0595 */

    if (add_res != 1625) return 0;
    if (sub_res != 875)  return 0;
    if (shift_res != 10077) return 0;
    if (logic_res != 0x0595) return 0;

    return 1;
}

/* --------------------------------------------------------------------------
 * Test 2: Control Flow, Stack Frame, and Recursion
 * -------------------------------------------------------------------------- */
static uint32_t fibonacci(uint32_t n)
{
    if (n == 0) return 0;
    if (n == 1) return 1;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

static int test_stack_and_recursion(void)
{
    /* fib(10) must equal 55 */
    uint32_t res = fibonacci(10);
    return (res == 55);
}

/* --------------------------------------------------------------------------
 * Test 3: Data Memory (DMEM) Multi-Width Access
 * -------------------------------------------------------------------------- */
static volatile uint32_t dmem_buffer[8];

static int test_dmem_access(void)
{
    /* Word access */
    dmem_buffer[0] = 0xCAFEBABE;
    dmem_buffer[1] = 0x12345678;
    if (dmem_buffer[0] != 0xCAFEBABE) return 0;
    if (dmem_buffer[1] != 0x12345678) return 0;

    /* Byte access verification */
    volatile uint8_t *byte_ptr = (volatile uint8_t *)&dmem_buffer[2];
    byte_ptr[0] = 0xAA;
    byte_ptr[1] = 0xBB;
    byte_ptr[2] = 0xCC;
    byte_ptr[3] = 0xDD;

    if (dmem_buffer[2] != 0xDDCCBBAA) return 0;
    if (byte_ptr[1] != 0xBB) return 0;

    /* Half-word access verification */
    volatile uint16_t *half_ptr = (volatile uint16_t *)&dmem_buffer[3];
    half_ptr[0] = 0x55AA;
    half_ptr[1] = 0x33CC;

    if (dmem_buffer[3] != 0x33CC55AA) return 0;
    if (half_ptr[0] != 0x55AA) return 0;

    return 1;
}

/* --------------------------------------------------------------------------
 * Test 4: GPIO Peripheral Driving
 * -------------------------------------------------------------------------- */
static int test_gpio_peripheral(void)
{
    /* Configure all pins as output */
    gpio_set_dir(0xFF, 0xFF);

    /* Write test pattern */
    gpio_write(0xA5);
    if ((GPIO_DATA_OUT & 0xFF) != 0xA5) return 0;

    gpio_write(0x5A);
    if ((GPIO_DATA_OUT & 0xFF) != 0x5A) return 0;

    /* Walking one */
    for (int i = 0; i < 7; i++) {
        gpio_write(1 << i);
    }

    return 1;
}

/* --------------------------------------------------------------------------
 * Test 5: Hardware Timer Countdown
 * -------------------------------------------------------------------------- */
static int test_timer_peripheral(void)
{
    /* Load timer with 5000 cycles, no auto-reload, no IRQ */
    timer_start(5000, 0, 0);

    uint32_t val1 = timer_read();
    /* Small delay loop */
    for (volatile int d = 0; d < 50; d++);
    uint32_t val2 = timer_read();

    timer_stop();

    /* Counter must have decremented */
    if (val2 >= val1 && val1 != 0) return 0;

    return 1;
}

/* --------------------------------------------------------------------------
 * main: Entry Point
 * -------------------------------------------------------------------------- */
int main(void)
{
    int pass_count = 0;
    int fail_count = 0;

    /* Initialize UART */
    uart_init(BAUD_DIV_FAST);

    print_str("\r\n========================================\r\n");
    print_str("  RISC-V SOC BASIC C CODE TEST SUITE\r\n");
    print_str("========================================\r\n\r\n");

    /* TEST 1: ALU */
    print_str("[1/5] Testing Core ALU & Logic: ");
    if (test_alu()) {
        print_str("PASS\r\n");
        pass_count++;
    } else {
        print_str("FAIL\r\n");
        fail_count++;
    }

    /* TEST 2: Stack & Recursion */
    print_str("[2/5] Testing Stack & Recursion (fib=55): ");
    if (test_stack_and_recursion()) {
        print_str("PASS\r\n");
        pass_count++;
    } else {
        print_str("FAIL\r\n");
        fail_count++;
    }

    /* TEST 3: Data Memory */
    print_str("[3/5] Testing DMEM Multi-Width Access: ");
    if (test_dmem_access()) {
        print_str("PASS\r\n");
        pass_count++;
    } else {
        print_str("FAIL\r\n");
        fail_count++;
    }

    /* TEST 4: GPIO */
    print_str("[4/5] Testing GPIO Outputs: ");
    if (test_gpio_peripheral()) {
        print_str("PASS\r\n");
        pass_count++;
    } else {
        print_str("FAIL\r\n");
        fail_count++;
    }

    /* TEST 5: Hardware Timer */
    print_str("[5/5] Testing Hardware Timer: ");
    if (test_timer_peripheral()) {
        print_str("PASS\r\n");
        pass_count++;
    } else {
        print_str("FAIL\r\n");
        fail_count++;
    }

    /* Summary */
    print_str("\r\n========================================\r\n");
    print_str("  TEST SUMMARY: ");
    print_dec(pass_count);
    print_str(" PASSED, ");
    print_dec(fail_count);
    print_str(" FAILED\r\n");

    if (fail_count == 0) {
        print_str("  >>> RESULT: ALL BASIC C TESTS PASSED! <<<\r\n");
        print_str("========================================\r\n\r\n");
        /* All LEDs ON = SUCCESS indicator */
        gpio_write(0xFF);
    } else {
        print_str("  >>> RESULT: BASIC C TESTS FAILED! <<<\r\n");
        print_str("========================================\r\n\r\n");
        gpio_write(0xEE);
    }

    /* Halt loop */
    while (1);
    return 0;
}
