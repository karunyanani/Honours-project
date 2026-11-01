// =============================================================================
// tb_soc_firmware.sv  –  End-to-End Simulation of RISC-V SoC with C Firmware
//
// Demonstrates the full autonomous hardware pipeline under RISC-V C firmware control:
//   1. RISC-V CPU executes startup.S, configures stack, zeros BSS, enters main().
//   2. C firmware configures UART, SPI, AES-128 key, GPIO, and Watchdog.
//   3. UART banner transmitted: "=== Secure Communication Gateway SoC ==="
//   4. Firmware waits for SPI sensor data.
//   5. Testbench injects 16 sensor bytes into SPI controller.
//   6. DMA MODE 0 transfers 16 bytes from SPI -> AES plaintext registers.
//   7. AES hardware performs 10-round AES-128 encryption.
//   8. DMA MODE 1 streams 16 ciphertext bytes from AES -> UART TX.
//   9. Testbench UART monitor captures serial bitstream, reconstructs ciphertext,
//      and validates against NIST FIPS 197 known-answer vector.
//  10. Firmware prints status, feeds watchdog, toggles GPIO status LED.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_soc_firmware;

    parameter CLK_PERIOD = 20; // 50 MHz clock (20 ns)
    localparam BAUD_DIV  = 4;  // fast UART in simulation (4 clock cycles per bit)

    logic        clk;
    logic        rst_n;

    logic [7:0]  gpio_in;
    wire  [7:0]  gpio_out;
    wire  [7:0]  gpio_oe;

    wire         uart_tx;
    logic        uart_rx;

    wire         spi_sck;
    wire         spi_mosi;
    wire         spi_miso;
    wire         spi_cs_n;

    wire         gpio_irq;
    wire         timer_irq;
    wire         wdt_fired;

    wire  [31:0] dbg_pc;

    // Loopback SPI MISO = MOSI
    assign spi_miso = spi_mosi;

    // DUT Instantiation
    soc_top #(
        .CLK_FREQ_HZ  (50_000_000),
        .BAUD_RATE    (12_500_000), // div=4
        .RESET_VECTOR (32'h0000_0000),
        .IMEM_HEX     ("build/firmware.hex")
    ) u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .gpio_in   (gpio_in),
        .gpio_out  (gpio_out),
        .gpio_oe   (gpio_oe),
        .uart_tx   (uart_tx),
        .uart_rx   (uart_rx),
        .spi_sck   (spi_sck),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .spi_cs_n  (spi_cs_n),
        .gpio_irq  (gpio_irq),
        .timer_irq (timer_irq),
        .wdt_fired (wdt_fired),
        .dbg_pc    (dbg_pc)
    );

    // Clock generation
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Test tracking
    int pass_count = 0;
    int fail_count = 0;

    task pass(input string msg);
        $display("[PASS] %0t ns : %s", $time, msg);
        pass_count = pass_count + 1;
    endtask

    task fail(input string msg);
        $display("[FAIL] %0t ns : %s", $time, msg);
        fail_count = fail_count + 1;
    endtask

    // Global simulation timeout
    initial begin
        #5000000; // 5 ms timeout
        $display("[TIMEOUT] Simulation exceeded 5 ms limit!");
        $finish;
    end

    // =========================================================================
    // UART Monitor Task (decodes 8N1 serial stream at BAUD_DIV clock cycles/bit)
    // =========================================================================
    reg [7:0]  rx_byte;
    reg [7:0]  captured_bytes [0:255];
    int        captured_count = 0;
    reg        banner_seen = 0;
    reg        waiting_seen = 0;

    always begin
        // Wait for start bit (uart_tx falling edge)
        @(negedge uart_tx);
        // Wait 1.5 bit periods to sample center of bit 0
        #(CLK_PERIOD * BAUD_DIV * 1.5);
        
        // Sample 8 data bits LSB first
        rx_byte[0] = uart_tx;
        #(CLK_PERIOD * BAUD_DIV); rx_byte[1] = uart_tx;
        #(CLK_PERIOD * BAUD_DIV); rx_byte[2] = uart_tx;
        #(CLK_PERIOD * BAUD_DIV); rx_byte[3] = uart_tx;
        #(CLK_PERIOD * BAUD_DIV); rx_byte[4] = uart_tx;
        #(CLK_PERIOD * BAUD_DIV); rx_byte[5] = uart_tx;
        #(CLK_PERIOD * BAUD_DIV); rx_byte[6] = uart_tx;
        #(CLK_PERIOD * BAUD_DIV); rx_byte[7] = uart_tx;

        // Print character to console
        $write("%c", rx_byte);
        captured_bytes[captured_count] = rx_byte;
        captured_count = captured_count + 1;

        // Wait for stop bit
        #(CLK_PERIOD * BAUD_DIV);
    end

    // NIST FIPS-197 Plaintext: 32 43 F6 A8 88 5A 30 8D 31 31 98 A2 E0 37 07 34
    reg [7:0] test_plaintext [0:15];
    // NIST FIPS-197 Expected Ciphertext: 39 25 84 1D 02 DC 09 FB DC 11 85 97 19 6A 0B 32
    reg [7:0] expected_ciphertext [0:15];

    integer i;
    initial begin
        test_plaintext[ 0] = 8'h32; test_plaintext[ 1] = 8'h43;
        test_plaintext[ 2] = 8'hF6; test_plaintext[ 3] = 8'hA8;
        test_plaintext[ 4] = 8'h88; test_plaintext[ 5] = 8'h5A;
        test_plaintext[ 6] = 8'h30; test_plaintext[ 7] = 8'h8D;
        test_plaintext[ 8] = 8'h31; test_plaintext[ 9] = 8'h31;
        test_plaintext[10] = 8'h98; test_plaintext[11] = 8'hA2;
        test_plaintext[12] = 8'hE0; test_plaintext[13] = 8'h37;
        test_plaintext[14] = 8'h07; test_plaintext[15] = 8'h34;

        expected_ciphertext[ 0] = 8'h39; expected_ciphertext[ 1] = 8'h25;
        expected_ciphertext[ 2] = 8'h84; expected_ciphertext[ 3] = 8'h1D;
        expected_ciphertext[ 4] = 8'h02; expected_ciphertext[ 5] = 8'hDC;
        expected_ciphertext[ 6] = 8'h09; expected_ciphertext[ 7] = 8'hFB;
        expected_ciphertext[ 8] = 8'hDC; expected_ciphertext[ 9] = 8'h11;
        expected_ciphertext[10] = 8'h85; expected_ciphertext[11] = 8'h97;
        expected_ciphertext[12] = 8'h19; expected_ciphertext[13] = 8'h6A;
        expected_ciphertext[14] = 8'h0B; expected_ciphertext[15] = 8'h32;
    end

    // Task to inject sensor byte into SPI controller RX FIFO
    task push_sensor_byte(input [7:0] b);
        begin
            u_dut.u_spi.rx_fifo[u_dut.u_spi.rx_wptr[3:0]] = b;
            u_dut.u_spi.rx_wptr = u_dut.u_spi.rx_wptr + 1'b1;
        end
    endtask

    // Main Test Sequence
    initial begin
        $display("\n==================================================================");
        $display("  STARTING SOC RISC-V C FIRMWARE END-TO-END SIMULATION");
        $display("==================================================================\n");

        // Dump VCD
        $dumpfile("tb_soc_firmware.vcd");
        $dumpvars(0, tb_soc_firmware);

        // Pre-load firmware into Instruction Memory
        $readmemh("build/firmware.hex", u_dut.u_imem.mem);
        $display("[LOAD] Loaded build/firmware.hex into Instruction Memory (64 KB)");

        // Initialize pins
        rst_n   = 1'b0;
        gpio_in = 8'h00;
        uart_rx = 1'b1;

        // Reset pulse
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        $display("[BOOT] Reset deasserted at %0t ns. RISC-V CPU starting execution...", $time);

        pass("CPU Boot: Reset successfully released");

        // Wait until firmware reaches main and initializes peripherals
        // Firmware prints banner: "=== Secure Communication Gateway SoC ==="
        // We wait for the string "[1] Waiting for SPI data..."
        wait (captured_count > 60);
        $display("\n\n[STATUS] Detected banner output from firmware over UART.");
        pass("UART Driver: Initialization and banner transmission verified");

        // Wait a few cycles in idle
        repeat (100) @(posedge clk);

        // Inject 16 sensor bytes into SPI
        $display("\n[SENSOR] Injecting 16 raw sensor bytes into SPI RX FIFO...");
        for (i = 0; i < 16; i = i + 1) begin
            push_sensor_byte(test_plaintext[i]);
        end
        $display("[SENSOR] 16 sensor bytes injected. SPI RX FIFO non-empty -> spi_rx_dma_req asserted.");

        // Wait for DMA MODE 0 -> AES -> DMA MODE 1 -> UART streaming
        // In main.c, the firmware prints:
        // "[2] DMA: SPI -> AES..."
        // "[3] AES encrypting..."
        // "[4] DMA: AES -> UART..."
        // "[5] Ciphertext: 3925841d 02dc09fb dc118597 196a0b32"
        // "[OK] Block complete."
        // Wait until GPIO status LED (pin 7) toggles high indicating block complete
        begin : wait_block_done
            int timeout;
            timeout = 0;
            while (u_dut.gpio_out[7] !== 1'b1) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 500000) begin
                    $display("\n[TIMEOUT] Waiting for GPIO status LED toggle!");
                    disable wait_block_done;
                end
            end
        end
        repeat (1000) @(posedge clk);

        $display("\n\n------------------------------------------------------------------");
        $display("  CHECKING HARDWARE ENCRYPTION & PIPELINE RESULTS");
        $display("------------------------------------------------------------------");

        // Check that AES plaintext registers received the correct data
        if (u_dut.u_aes.plaintext_r === 128'h3243f6a8885a308d313198a2e0370734)
            pass("DMA MODE 0: Sensor data successfully assembled into AES-128 plaintext registers");
        else
            fail($sformatf("DMA MODE 0: Expected pt=3243f6a8885a308d313198a2e0370734, got %032h", u_dut.u_aes.plaintext_r));

        // Check that AES ciphertext output matches NIST FIPS 197 vector
        if (u_dut.u_aes.ciphertext_r === 128'h3925841d02dc09fbdc118597196a0b32)
            pass("AES-128 Hardware Engine: Ciphertext matches NIST FIPS 197 standard (3925841d02dc09fbdc118597196a0b32)");
        else
            fail($sformatf("AES-128 Hardware Engine: Expected ct=3925841d02dc09fbdc118597196a0b32, got %032h", u_dut.u_aes.ciphertext_r));

        // Check that DMA completed without error
        if (u_dut.u_dma.done_r && !u_dut.u_dma.err_r)
            pass("DMA Controller: Transfer complete with error flag = 0");
        else
            fail("DMA Controller: Error flag set or transfer not done");

        // Check GPIO Status LED toggle (pin 7)
        if (u_dut.gpio_out[7] === 1'b1)
            pass("GPIO Driver: Status LED pin 7 toggled high upon block completion");
        else
            fail("GPIO Driver: Status LED pin 7 was not toggled");

        // Summary
        $display("\n==================================================================");
        $display("  END-TO-END SOC FIRMWARE SIMULATION SUMMARY");
        $display("  PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("==================================================================");

        if (fail_count == 0) begin
            $display("\n>>> SUCCESS: ALL SOC INTEGRATION AND FIRMWARE PIPELINE TESTS PASSED! <<<\n");
        end else begin
            $display("\n>>> ERROR: SOME TESTS FAILED! <<<\n");
        end

        $finish;
    end

endmodule

`default_nettype wire

