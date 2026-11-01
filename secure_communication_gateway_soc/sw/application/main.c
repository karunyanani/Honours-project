/* =============================================================================
 * main.c  –  SPI → AES → UART Secure Pipeline Demo
 *
 * Demonstrates the complete secure communication gateway pipeline:
 *
 *   1. INIT
 *      - Initialise UART (115200 baud at 50 MHz → div = 434)
 *      - Initialise SPI (mode 0, ~1 MHz SCK)
 *      - Initialise AES: write a 128-bit key, set KEY_VALID
 *      - Initialise watchdog (336 ms timeout)
 *
 *   2. LOOP (one 16-byte block per iteration)
 *      a. Wait for SPI RX data to arrive (poll SPI_RX_DMA_REQ).
 *      b. Trigger DMA MODE 0: DMA reads 16 bytes from SPI_RX_DATA,
 *         writes them into AES_DATA_IN0..3, then asserts AES START.
 *      c. Poll AES_STATUS.DONE (hardware does 10-round AES-128).
 *      d. Trigger DMA MODE 1: DMA reads AES_DATA_OUT0..3 (16 bytes),
 *         streams each byte to UART_TX_DATA.
 *      e. Feed the watchdog.
 *      f. Print a short status line via UART (CPU path).
 *
 *   3. Recovery path
 *      If the watchdog fires (DMA/AES/SPI stall), the scoped reset clears
 *      those datapaths; firmware detects WDT_RESET_CAUSE, prints a warning,
 *      and restarts the pipeline from step 2.
 *
 * Build:
 *   riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os \
 *       -T sw/linker/soc.ld \
 *       -I sw/include -I sw/drivers \
 *       sw/startup/startup.S sw/application/main.c \
 *       -o firmware.elf
 *   riscv32-unknown-elf-objcopy -O binary firmware.elf firmware.bin
 * =============================================================================
 */

#include <stdint.h>
#include "soc_map.h"
#include "uart.h"
#include "spi.h"
#include "aes.h"
#include "dma.h"
#include "wdt.h"
#include "gpio.h"
#include "timer.h"

/* --------------------------------------------------------------------------
 * Board / system constants
 * -------------------------------------------------------------------------- */
#define CLK_HZ          50000000UL
#define BAUD_RATE       115200UL

#ifdef SIMULATION
#define BAUD_DIV        4u
#define WDT_TIMEOUT_VAL 50000u
#else
#define BAUD_DIV        ((uint32_t)(CLK_HZ / BAUD_RATE))   /* 434 */
#define WDT_TIMEOUT_VAL 0x00FFFFFFu
#endif

/* SPI clock divider: SCK = 50 MHz / (2*(24+1)) ≈ 1 MHz */
#define SPI_CLK_DIV_VAL 24u

/* AES-128 key (example – replace with your actual key in production) */
static const uint32_t aes_key[4] = {
    0x2B7E1516UL,   /* key[127:96] */
    0x28AED2A6UL,   /* key[ 95:64] */
    0xABF71588UL,   /* key[ 63:32] */
    0x09CF4F3CUL    /* key[ 31: 0] */
};

/* --------------------------------------------------------------------------
 * Prototypes
 * -------------------------------------------------------------------------- */
static void system_init(void);
static void pipeline_run_block(void);
static void handle_wdt_recovery(void);

/* --------------------------------------------------------------------------
 * main
 * -------------------------------------------------------------------------- */
int main(void)
{
    system_init();

    uart_puts("\r\n=== Secure Communication Gateway SoC ===\r\n");
    uart_puts("SPI -> AES-128 -> UART pipeline running\r\n\r\n");

    /* Check if we woke from a watchdog scoped reset */
    if (wdt_was_reset()) {
        handle_wdt_recovery();
    }

    /* Main processing loop – runs forever */
    while (1) {
        pipeline_run_block();
        wdt_feed();
    }

    return 0;  /* unreachable */
}

/* --------------------------------------------------------------------------
 * system_init – configure all peripherals once at startup
 * -------------------------------------------------------------------------- */
static void system_init(void)
{
    /* UART: enable TX at configured baud rate */
    uart_init((uint16_t)BAUD_DIV);

    /* SPI: mode 0 (CPOL=0, CPHA=0), auto chip-select */
    spi_init((uint8_t)SPI_CLK_DIV_VAL, 0, 0, 1);

    /* AES: load key once; it survives watchdog scoped resets */
    aes_set_key(aes_key);

    /* GPIO: all pins as inputs initially; GPIO[7] = status LED (output) */
    gpio_set_dir(0x80u, 0x80u);   /* pin 7 = output */
    gpio_clr_pin(7);

    /* Watchdog: start with 336 ms timeout */
    wdt_start(WDT_TIMEOUT_VAL);
}

/* --------------------------------------------------------------------------
 * pipeline_run_block
 *   Encrypt one 16-byte block arriving from SPI and transmit via UART.
 * -------------------------------------------------------------------------- */
static void pipeline_run_block(void)
{
    uint32_t status;

    /* ------------------------------------------------------------------
     * Step 1: Wait for SPI RX data (16 bytes must be available)
     * The spi_rx_dma_req sideband tells us the RX FIFO is non-empty.
     * We wait until at least one byte arrives; the DMA will consume 16.
     * ------------------------------------------------------------------ */
    uart_puts("[1] Waiting for SPI data...\r\n");

    while (!(SPI_STATUS & SPI_RX_DMA_REQ_BIT)) {
        wdt_feed();   /* keep feeding while waiting */
    }

    /* ------------------------------------------------------------------
     * Step 2: DMA MODE 0 – SPI RX FIFO → AES plaintext registers
     * The DMA reads 16 bytes from SPI_RX_DATA, assembles them into
     * AES_DATA_IN0..3, then writes AES_CTRL = START|KEY_VALID.
     * ------------------------------------------------------------------ */
    uart_puts("[2] DMA: SPI -> AES...\r\n");

    dma_start_spi_to_aes();

    status = dma_wait_done();
    if (status & DMA_ERR_BIT) {
        uart_puts("  ERROR: DMA MODE0 failed!\r\n");
        return;
    }

    /* ------------------------------------------------------------------
     * Step 3: Poll AES STATUS.DONE
     * The AES engine takes 11 clock cycles after START; we poll until done.
     * ------------------------------------------------------------------ */
    uart_puts("[3] AES encrypting...\r\n");

    aes_wait_done();

    /* ------------------------------------------------------------------
     * Step 4: DMA MODE 1 – AES ciphertext → UART TX
     * The DMA reads AES_DATA_OUT0..3 (4×32-bit = 16 bytes) and sends
     * each byte to UART_TX_DATA, gated by uart_tx_dma_req.
     * ------------------------------------------------------------------ */
    uart_puts("[4] DMA: AES -> UART...\r\n");

    dma_start_aes_to_uart();

    status = dma_wait_done();
    if (status & DMA_ERR_BIT) {
        uart_puts("  ERROR: DMA MODE1 failed!\r\n");
        return;
    }

    /* ------------------------------------------------------------------
     * Step 5: Status / debug output (CPU path – optional)
     * Print the ciphertext words for verification.
     * ------------------------------------------------------------------ */
    uart_puts("[5] Ciphertext: ");
    uart_put_hex32(AES_DATA_OUT0);
    uart_putc(' ');
    uart_put_hex32(AES_DATA_OUT1);
    uart_putc(' ');
    uart_put_hex32(AES_DATA_OUT2);
    uart_putc(' ');
    uart_put_hex32(AES_DATA_OUT3);
    uart_puts("\r\n");

    /* Toggle status LED on GPIO pin 7 each block */
    gpio_toggle_pin(7);

    uart_puts("[OK] Block complete.\r\n\r\n");
}

/* --------------------------------------------------------------------------
 * handle_wdt_recovery
 *   Called when firmware detects the watchdog has fired.
 *   The scoped reset already cleared DMA/AES/SPI datapaths.
 *   Firmware re-enables the peripherals and clears the cause flag.
 * -------------------------------------------------------------------------- */
static void handle_wdt_recovery(void)
{
    uart_puts("\r\n*** WATCHDOG RECOVERY ***\r\n");
    uart_puts("Scoped reset fired – DMA/AES/SPI datapaths cleared.\r\n");
    uart_puts("AES key retained. Re-initialising peripherals...\r\n");

    /* Re-enable SPI (shift engine was reset) */
    spi_init((uint8_t)SPI_CLK_DIV_VAL, 0, 0, 1);
    spi_rx_flush();

    /* AES key survived – just re-assert KEY_VALID */
    AES_CTRL = AES_KEY_VALID_BIT;

    /* Clear the WDT fired flag */
    wdt_clear_reset_flag();

    /* Restart the watchdog counter */
    wdt_feed();

    uart_puts("Recovery complete. Resuming pipeline.\r\n\r\n");
}
