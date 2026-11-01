/* ==========================================================================
 * dma.h  –  DMA Controller driver
 *
 * Two modes:
 *   DMA_MODE_SPI_AES  (0) : reads bytes from SPI_RX_DATA → AES_DATA_IN,
 *                            then triggers AES encryption.
 *   DMA_MODE_AES_UART (1) : reads AES_DATA_OUT words → streams 16 bytes
 *                            to UART_TX_DATA.
 *
 * The CPU writes config registers, asserts START, then polls STATUS.DONE.
 * The DMA hardware handles all AXI transactions autonomously.
 * ========================================================================== */
#ifndef DMA_H
#define DMA_H

#include "soc_map.h"

/* Launch a DMA transfer.
 *   mode     : DMA_MODE_SPI_AES or DMA_MODE_AES_UART (use constants below)
 *   src_addr : source AXI address  (ignored by HW for MODE1 – AES OUT fixed)
 *   dst_addr : dest AXI address    (ignored by HW for MODE0 – AES IN fixed)
 *   length   : transfer length in bytes (max 255; 16 for AES blocks)
 *
 * The hardware uses fixed internal addresses for the AES/SPI/UART registers.
 * src_addr/dst_addr are stored in config regs but the FSM overrides them
 * with the appropriate peripheral addresses for each mode.
 */
static inline void dma_start(uint32_t mode,
                              uint32_t src_addr,
                              uint32_t dst_addr,
                              uint32_t length)
{
    DMA_SRC_ADDR = src_addr;
    DMA_DST_ADDR = dst_addr;
    DMA_LEN      = length;
    /* Write START=1 and mode bit together */
    DMA_CTRL     = DMA_START_BIT | ((mode & 1u) << 1);
}

/* Start MODE 0: SPI → AES (reads 16 bytes from SPI, writes to AES). */
static inline void dma_start_spi_to_aes(void)
{
    dma_start(DMA_MODE_SPI_AES, SPI_BASE + 0x04u, AES_BASE + 0x18u, 16u);
}

/* Start MODE 1: AES → UART (reads 16 ciphertext bytes from AES output,
 * streams them to UART TX). */
static inline void dma_start_aes_to_uart(void)
{
    dma_start(1u, AES_BASE + 0x28u, UART_BASE + 0x00u, 16u);
}

/* Poll until DMA is done (DONE or ERR set). Returns DMA_STATUS value. */
static inline uint32_t dma_wait_done(void)
{
    uint32_t status;
    do {
        status = DMA_STATUS;
    } while (!(status & (DMA_DONE_BIT | DMA_ERR_BIT)));
    return status;
}

/* Returns 1 if the DMA engine is currently running. */
static inline int dma_busy(void)
{
    return !!(DMA_STATUS & DMA_BUSY_BIT);
}

/* Returns 1 if the last transfer completed without error. */
static inline int dma_ok(void)
{
    return !!(DMA_STATUS & DMA_DONE_BIT) && !(DMA_STATUS & DMA_ERR_BIT);
}

#endif /* DMA_H */
