/* ==========================================================================
 * gpio.h  –  GPIO peripheral driver
 * 8-bit bidirectional port; per-pin direction, IRQ enable, edge select.
 * ========================================================================== */
#ifndef GPIO_H
#define GPIO_H

#include "soc_map.h"

/* Set pin direction.
 *   dir_mask : bitmask of pins to configure (1 = set as output).
 *   outputs  : bitmask of which of dir_mask pins become outputs.
 */
static inline void gpio_set_dir(uint8_t dir_mask, uint8_t outputs)
{
    uint32_t d = GPIO_DIR;
    d = (d & ~(uint32_t)dir_mask) | ((uint32_t)outputs & (uint32_t)dir_mask);
    GPIO_DIR = d;
}

/* Set all output pins to match output_val (only pins with DIR=1 are driven). */
static inline void gpio_write(uint8_t output_val)
{
    GPIO_DATA_OUT = (uint32_t)output_val;
}

/* Read the current sampled input values. */
static inline uint8_t gpio_read(void)
{
    return (uint8_t)(GPIO_DATA_IN & 0xFFu);
}

/* Set a single output pin high. */
static inline void gpio_set_pin(uint8_t pin)
{
    GPIO_DATA_OUT |= (uint32_t)(1u << pin);
}

/* Clear a single output pin. */
static inline void gpio_clr_pin(uint8_t pin)
{
    GPIO_DATA_OUT &= ~(uint32_t)(1u << pin);
}

/* Toggle a single output pin. */
static inline void gpio_toggle_pin(uint8_t pin)
{
    GPIO_DATA_OUT ^= (uint32_t)(1u << pin);
}

/* Configure per-pin IRQ.
 *   enable_mask : pins for which to enable interrupt.
 *   edge_mask   : 1 = rising edge, 0 = falling edge (per bit).
 */
static inline void gpio_irq_config(uint8_t enable_mask, uint8_t edge_mask)
{
    GPIO_IRQ_EN   = (uint32_t)enable_mask;
    GPIO_IRQ_EDGE = (uint32_t)edge_mask;
}

/* Return and clear the pending IRQ flags (write-1-to-clear). */
static inline uint8_t gpio_irq_pending_clear(void)
{
    uint8_t pend = (uint8_t)(GPIO_IRQ_PEND & 0xFFu);
    GPIO_IRQ_PEND = (uint32_t)pend;   /* W1C */
    return pend;
}

/* Disable all GPIO interrupts. */
static inline void gpio_irq_disable_all(void)
{
    GPIO_IRQ_EN = 0u;
}

#endif /* GPIO_H */
