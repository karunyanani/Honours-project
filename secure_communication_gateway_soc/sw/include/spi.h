/* ==========================================================================
 * spi.h  –  SPI peripheral driver
 * Master mode; configurable CPOL/CPHA; TX/RX FIFO polling.
 * ========================================================================== */
#ifndef SPI_H
#define SPI_H

#include "soc_map.h"

/* Initialise SPI with given clock divider and mode.
 *   clk_div  : SCK = clk / (2*(clk_div+1))
 *   cpol     : clock polarity  (0 or 1)
 *   cpha     : clock phase     (0 or 1)
 *   cs_auto  : assert CS automatically around each transfer (1) or manual (0)
 */
static inline void spi_init(uint8_t clk_div, int cpol, int cpha, int cs_auto)
{
    uint32_t ctrl = SPI_EN_BIT;
    if (cpol)    ctrl |= SPI_CPOL_BIT;
    if (cpha)    ctrl |= SPI_CPHA_BIT;
    if (cs_auto) ctrl |= SPI_CS_AUTO_BIT;
    SPI_CLK_DIV = (uint32_t)clk_div;
    SPI_CTRL    = ctrl;
}

/* Disable SPI. */
static inline void spi_disable(void)
{
    SPI_CTRL = 0u;
}

/* Block until TX FIFO has space, then send one byte.
 * Returns the received byte that comes back from the shift register. */
static inline uint8_t spi_transfer(uint8_t tx_byte)
{
    /* Wait for TX FIFO space */
    while (SPI_STATUS & SPI_TX_FULL_BIT)
        ;
    SPI_TX_DATA = (uint32_t)tx_byte;

    /* Wait for RX data */
    while (SPI_STATUS & SPI_RX_EMPTY_BIT)
        ;
    return (uint8_t)(SPI_RX_DATA & 0xFFu);
}

/* Send n bytes from tx_buf, capture replies into rx_buf (may be NULL). */
static inline void spi_transfer_buf(const uint8_t *tx_buf,
                                    uint8_t       *rx_buf,
                                    uint32_t       n)
{
    uint32_t i;
    for (i = 0; i < n; i++) {
        uint8_t r = spi_transfer(tx_buf ? tx_buf[i] : 0x00u);
        if (rx_buf) rx_buf[i] = r;
    }
}

/* Wait until SPI shift engine is idle. */
static inline void spi_wait_idle(void)
{
    while (SPI_STATUS & SPI_BUSY_BIT)
        ;
}

/* Returns 1 if RX FIFO has unread data. */
static inline int spi_rx_ready(void)
{
    return !(SPI_STATUS & SPI_RX_EMPTY_BIT);
}

/* Drain all bytes currently in the RX FIFO. */
static inline void spi_rx_flush(void)
{
    while (spi_rx_ready())
        (void)SPI_RX_DATA;
}

#endif /* SPI_H */
