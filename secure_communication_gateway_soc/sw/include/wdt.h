/* ==========================================================================
 * wdt.h  –  Watchdog Timer driver
 * Scoped reset: on timeout, resets DMA+AES+SPI datapaths only.
 * Key registers, CPU, and memories are unaffected.
 * ========================================================================== */
#ifndef WDT_H
#define WDT_H

#include "soc_map.h"

/* Initialise and start the watchdog with the given timeout (in clock cycles).
 * The caller must call wdt_feed() periodically to prevent a reset. */
static inline void wdt_start(uint32_t timeout_cycles)
{
    WDT_TIMEOUT = timeout_cycles;
    WDT_CTRL    = WDT_EN_BIT;
}

/* Stop the watchdog (disable). */
static inline void wdt_stop(void)
{
    WDT_CTRL = 0u;
}

/* Feed the watchdog – write the magic value to reload the counter. */
static inline void wdt_feed(void)
{
    WDT_FEED = WDT_MAGIC_VAL;
}

/* Returns 1 if the watchdog has fired (scoped reset occurred). */
static inline int wdt_was_reset(void)
{
    return !!(WDT_RESET_CAUSE & WDT_FIRED_BIT);
}

/* Clear the watchdog-fired flag (write-1-to-clear). */
static inline void wdt_clear_reset_flag(void)
{
    WDT_RESET_CAUSE = WDT_FIRED_BIT;
}

#endif /* WDT_H */
