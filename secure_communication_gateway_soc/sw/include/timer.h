/* ==========================================================================
 * timer.h  –  Timer peripheral driver
 * Countdown timer with optional auto-reload and interrupt.
 * ========================================================================== */
#ifndef TIMER_H
#define TIMER_H

#include "soc_map.h"

/* Start the timer with given reload value (in clock cycles).
 *   auto_reload : 1 = auto-reload on expire; 0 = stop at zero.
 *   irq_en      : 1 = assert timer_irq on expire.
 */
static inline void timer_start(uint32_t reload, int auto_reload, int irq_en)
{
    uint32_t ctrl = TIMER_EN_BIT;
    if (auto_reload) ctrl |= TIMER_AUTO_RELOAD_BIT;
    if (irq_en)      ctrl |= TIMER_IRQ_EN_BIT;
    TIMER_LOAD   = reload;
    TIMER_STATUS = TIMER_EXPIRED_BIT;  /* clear any stale EXPIRED */
    TIMER_CTRL   = ctrl;
}

/* Stop the timer. */
static inline void timer_stop(void)
{
    TIMER_CTRL = 0u;
}

/* Return current counter value. */
static inline uint32_t timer_read(void)
{
    return TIMER_COUNT;
}

/* Returns 1 if the EXPIRED flag is set (timer reached zero). */
static inline int timer_expired(void)
{
    return !!(TIMER_STATUS & TIMER_EXPIRED_BIT);
}

/* Clear the EXPIRED flag (write-1-to-clear). */
static inline void timer_clear_expired(void)
{
    TIMER_STATUS = TIMER_EXPIRED_BIT;
}

/* Blocking delay: wait for the timer to expire once.
 * Caller must have started the timer beforehand. */
static inline void timer_wait_expired(void)
{
    while (!timer_expired())
        ;
    timer_clear_expired();
}

/* Simple busy-wait delay in timer ticks.
 * Reconfigures the timer; does not preserve previous settings. */
static inline void timer_delay_ticks(uint32_t ticks)
{
    timer_start(ticks, 0, 0);
    timer_wait_expired();
    timer_stop();
}

#endif /* TIMER_H */
