// =============================================================================
// tb_basic_c_test.sv  –  Simulation of RISC-V SoC with Basic C Test Application
//
// Verifies:
//   1. CPU Boot & execution of basic C code from Instruction Memory (64 KB)
//   2. ALU operations, recursion/stack pointer handling
//   3. Data Memory (DMEM) word, half-word, byte stores and loads
//   4. GPIO output manipulation
//   5. Hardware Timer countdown
//   6. UART transmission and ASCII output
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_basic_c_test;

    parameter CLK_PERIOD = 20; // 50 MHz clock (20 ns)
    localparam BAUD_DIV  = 4;  // Fast UART in simulation (4 clock cycles per bit)

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
        .IMEM_HEX     ("build/basic_test.hex")
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
        #2000000; // 2 ms timeout
        $display("\n[TIMEOUT] Simulation exceeded 2 ms limit!");
        $finish;
    end

    // =========================================================================
    // UART Monitor Task (decodes 8N1 serial stream at BAUD_DIV clock cycles/bit)
    // =========================================================================
    reg [7:0] rx_byte;
    int       char_count;

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

        // Print character live to console
        $write("%c", rx_byte);
        char_count = char_count + 1;

        // Wait for stop bit
        #(CLK_PERIOD * BAUD_DIV);
    end

    // =========================================================================
    // Main Test Execution Flow
    // =========================================================================
    initial begin
        $display("\n==================================================================");
        $display("  STARTING RISC-V SOC BASIC C CODE TESTBENCH SIMULATION");
        $display("==================================================================\n");

        // Dump VCD
        $dumpfile("build/tb_basic_c_test.vcd");
        $dumpvars(0, tb_basic_c_test);

        // Pre-load basic test hex into Instruction Memory
        $readmemh("build/basic_test.hex", u_dut.u_imem.mem);
        $display("[LOAD] Loaded build/basic_test.hex into Instruction Memory (64 KB)");

        // Initialize pins
        char_count = 0;
        rst_n   = 1'b0;
        gpio_in = 8'h00;
        uart_rx = 1'b1;

        // Reset deassertion
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        $display("[BOOT] Reset deasserted at %0t ns. CPU begins executing C code...", $time);

        pass("CPU Boot: Reset released successfully");

        // Wait until all tests finish (firmware sets gpio_out = 0xFF on success or 0xEE on failure)
        begin : wait_done
            int timeout;
            timeout = 0;
            while (u_dut.gpio_out !== 8'hFF && u_dut.gpio_out !== 8'hEE) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout > 200000) begin
                    $display("\n[TIMEOUT] Waiting for basic C test completion signal on GPIO!");
                    fail("Timeout waiting for GPIO completion flag");
                    disable wait_done;
                end
            end
        end

        // Allow UART buffer to drain remaining characters
        repeat (500) @(posedge clk);

        $display("\n------------------------------------------------------------------");
        $display("  CHECKING BASIC C CODE TEST RESULTS");
        $display("------------------------------------------------------------------");

        if (u_dut.gpio_out === 8'hFF) begin
            pass("Firmware Execution: All sub-tests passed (gpio_out = 0xFF)");
        end else if (u_dut.gpio_out === 8'hEE) begin
            fail("Firmware Execution: One or more sub-tests failed (gpio_out = 0xEE)");
        end else begin
            fail($sformatf("Firmware Execution: Unexpected gpio_out value (0x%02h)", u_dut.gpio_out));
        end

        if (char_count > 50) begin
            pass($sformatf("UART Output: Verified %0d characters received and decoded", char_count));
        end else begin
            fail("UART Output: Insufficient characters received");
        end

        // Final Summary
        $display("\n==================================================================");
        $display("  BASIC C CODE TEST SIMULATION SUMMARY");
        $display("  PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("==================================================================");

        if (fail_count == 0 && u_dut.gpio_out === 8'hFF) begin
            $display("\n>>> SUCCESS: BASIC C CODE TEST PASSED COMPLETELY! <<<\n");
        end else begin
            $display("\n>>> ERROR: BASIC C TEST FAILED! <<<\n");
        end

        $finish;
    end

endmodule

`default_nettype wire
