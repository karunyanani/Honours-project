/* ==========================================================================
 * uart.h  –  UART peripheral driver
 * Polling (TX FIFO not full), no interrupt support.
 * ========================================================================== */
#ifndef UART_H
#define UART_H

#include "soc_map.h"

/* Initialise UART: set baud divider and enable TX. */
static inline void uart_init(uint32_t baud_div)
{
    UART_BAUD_DIV = baud_div;
    UART_CTRL     = UART_TX_EN_BIT | UART_RX_EN_BIT;
}

/* Block until TX FIFO has space, then write one byte. */
static inline void uart_putc(char c)
{
    while (UART_STATUS & UART_TX_FULL_BIT)
        ;
    UART_TX_DATA = (uint32_t)(uint8_t)c;
}

/* Write a null-terminated string. */
static inline void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* Write n bytes from a buffer. */
static inline void uart_write(const uint8_t *buf, uint32_t n)
{
    uint32_t i;
    for (i = 0; i < n; i++)
        uart_putc((char)buf[i]);
}

/* Non-blocking TX FIFO check. Returns 1 if space available. */
static inline int uart_tx_ready(void)
{
    return !(UART_STATUS & UART_TX_FULL_BIT);
}

/* Read one byte (blocks until available). Stub – RX not implemented in HW. */
static inline char uart_getc(void)
{
    while (UART_STATUS & UART_RX_EMPTY_BIT)
        ;
    return (char)(UART_RX_DATA & 0xFFu);
}

/* Print a 32-bit value as 8 hex digits. */
static inline void uart_put_hex32(uint32_t v)
{
    int i;
    static const char * const hex = "0123456789abcdef";
    for (i = 28; i >= 0; i -= 4)
        uart_putc(hex[(v >> i) & 0xF]);
}

#endif /* UART_H */
