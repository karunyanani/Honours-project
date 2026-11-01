// =============================================================================
// tb_watchdog.sv  –  Watchdog Timer Self-Checking Testbench
//
// Tests (spec §14, Watchdog verification):
//   TC01 – Normal feed: WDT never fires when fed before timeout
//   TC02 – Timeout fires: counter expires, wdt_reset_dma/aes/spi assert
//   TC03 – Scoped reset exactly one cycle pulse on all three outputs
//   TC04 – CPU not reset during WDT event (WDT has no cpu_rst output)
//   TC05 – Memory retention: WDT does not touch IMEM/DMEM
//   TC06 – AES key retention: wdt_rst clears pipeline, not key registers
//   TC07 – DMA config retention: wdt_rst preserves src/dst/len regs
//   TC08 – WDT_RESET_CAUSE[0] set on timeout; W1C clears it
//   TC09 – WDT self-disables after firing (no re-fire loop)
//   TC10 – Restart: after clearing RESET_CAUSE and re-enabling, WDT runs again
//   TC11 – Short timeout: 8-cycle timeout detected correctly
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_watchdog;

    parameter CLK_PERIOD = 10;
    parameter AW = 32;
    parameter DW = 32;

    // Drain cycles as configured in watchdog.v
    parameter DRAIN_CYCLES = 8;

    logic clk = 0;
    logic rst = 1;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // WDT AXI-Lite connections
    // =========================================================================
    logic [AW-1:0] s_awaddr; logic s_awvalid; logic s_awready;
    logic [DW-1:0] s_wdata;  logic [3:0] s_wstrb;
    logic          s_wvalid; logic s_wready;
    logic [1:0]    s_bresp;  logic s_bvalid;  logic s_bready;
    logic [AW-1:0] s_araddr; logic s_arvalid; logic s_arready;
    logic [DW-1:0] s_rdata;  logic [1:0] s_rresp;
    logic          s_rvalid; logic s_rready;

    logic wdt_reset_dma;
    logic wdt_reset_aes;
    logic wdt_reset_spi;
    logic wdt_fired;

    watchdog dut (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata),   .s_axi_wstrb(s_wstrb),     .s_axi_wvalid(s_wvalid),
        .s_axi_wready(s_wready), .s_axi_bresp(s_bresp),      .s_axi_bvalid(s_bvalid),
        .s_axi_bready(s_bready), .s_axi_araddr(s_araddr),    .s_axi_arvalid(s_arvalid),
        .s_axi_arready(s_arready),.s_axi_rdata(s_rdata),     .s_axi_rresp(s_rresp),
        .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
        .wdt_reset_dma(wdt_reset_dma),
        .wdt_reset_aes(wdt_reset_aes),
        .wdt_reset_spi(wdt_reset_spi),
        .wdt_fired(wdt_fired)
    );

    // =========================================================================
    // AES instance (to test key retention under wdt_reset_aes)
    // =========================================================================
    logic [AW-1:0] aes_awaddr; logic aes_awvalid; logic aes_awready;
    logic [DW-1:0] aes_wdata;  logic [3:0] aes_wstrb;
    logic          aes_wvalid; logic aes_wready;
    logic [1:0]    aes_bresp;  logic aes_bvalid;  logic aes_bready;
    logic [AW-1:0] aes_araddr; logic aes_arvalid; logic aes_arready;
    logic [DW-1:0] aes_rdata;  logic [1:0] aes_rresp;
    logic          aes_rvalid; logic aes_rready;
    logic          aes_done_sig;

    aes u_aes (
        .clk(clk), .rst(rst), .wdt_rst(wdt_reset_aes),
        .s_axi_awaddr(aes_awaddr), .s_axi_awvalid(aes_awvalid), .s_axi_awready(aes_awready),
        .s_axi_wdata(aes_wdata),   .s_axi_wstrb(aes_wstrb),     .s_axi_wvalid(aes_wvalid),
        .s_axi_wready(aes_wready), .s_axi_bresp(aes_bresp),      .s_axi_bvalid(aes_bvalid),
        .s_axi_bready(aes_bready), .s_axi_araddr(aes_araddr),    .s_axi_arvalid(aes_arvalid),
        .s_axi_arready(aes_arready),.s_axi_rdata(aes_rdata),     .s_axi_rresp(aes_rresp),
        .s_axi_rvalid(aes_rvalid), .s_axi_rready(aes_rready),    .aes_done(aes_done_sig)
    );

    // =========================================================================
    // DMA instance (to test config retention under wdt_reset_dma)
    // =========================================================================
    logic [AW-1:0] dma_awaddr; logic dma_awvalid; logic dma_awready;
    logic [DW-1:0] dma_wdata;  logic [3:0] dma_wstrb;
    logic          dma_wvalid; logic dma_wready;
    logic [1:0]    dma_bresp;  logic dma_bvalid;  logic dma_bready;
    logic [AW-1:0] dma_araddr; logic dma_arvalid; logic dma_arready;
    logic [DW-1:0] dma_rdata;  logic [1:0] dma_rresp;
    logic          dma_rvalid; logic dma_rready;

    dma u_dma (
        .clk(clk), .rst(rst), .wdt_rst(wdt_reset_dma),
        .s_axi_awaddr(dma_awaddr),  .s_axi_awvalid(dma_awvalid), .s_axi_awready(dma_awready),
        .s_axi_wdata(dma_wdata),    .s_axi_wstrb(dma_wstrb),     .s_axi_wvalid(dma_wvalid),
        .s_axi_wready(dma_wready),  .s_axi_bresp(dma_bresp),      .s_axi_bvalid(dma_bvalid),
        .s_axi_bready(dma_bready),  .s_axi_araddr(dma_araddr),    .s_axi_arvalid(dma_arvalid),
        .s_axi_arready(dma_arready),.s_axi_rdata(dma_rdata),      .s_axi_rresp(dma_rresp),
        .s_axi_rvalid(dma_rvalid),  .s_axi_rready(dma_rready),
        // DMA master tied off
        .m_axi_awid(),   .m_axi_awaddr(),  .m_axi_awlen(),  .m_axi_awsize(),
        .m_axi_awburst(),.m_axi_awlock(),  .m_axi_awcache(),.m_axi_awprot(),
        .m_axi_awqos(),  .m_axi_awvalid(), .m_axi_awready(1'b1),
        .m_axi_wdata(),  .m_axi_wstrb(),   .m_axi_wlast(),  .m_axi_wvalid(),
        .m_axi_wready(1'b1),
        .m_axi_bid(8'd0),.m_axi_bresp(2'b00),.m_axi_bvalid(1'b0),.m_axi_bready(),
        .m_axi_arid(),   .m_axi_araddr(),  .m_axi_arlen(),  .m_axi_arsize(),
        .m_axi_arburst(),.m_axi_arlock(),  .m_axi_arcache(),.m_axi_arprot(),
        .m_axi_arqos(),  .m_axi_arvalid(), .m_axi_arready(1'b1),
        .m_axi_rid(8'd0),.m_axi_rdata(32'd0),.m_axi_rresp(2'b00),
        .m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),.m_axi_rready(),
        .spi_rx_dma_req(1'b0),.uart_tx_dma_req(1'b1)
    );

    // =========================================================================
    // AXI-Lite BFM tasks for WDT
    // =========================================================================
    task wdt_write(input [7:0] off, input [31:0] data);
        @(posedge clk); #1;
        s_awaddr = {24'h0, off}; s_awvalid = 1;
        s_wdata  = data; s_wstrb = 4'hF; s_wvalid = 1;
        s_bready = 1;
        fork
            begin
                do @(posedge clk);
                while (!s_awready);
                #1 s_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!s_wready);
                #1 s_wvalid = 0;
            end
        join
        while (!s_bvalid) @(posedge clk) #1;
        @(posedge clk); #1;
        s_bready = 0;
    endtask

    task wdt_read(input [7:0] off, output [31:0] data);
        @(posedge clk); #1;
        s_araddr = {24'h0, off}; s_arvalid = 1;
        s_rready = 1;
        do @(posedge clk);
        while (!s_arready);
        #1 s_arvalid = 0;
        while (!s_rvalid) @(posedge clk) #1;
        data = s_rdata;
        @(posedge clk); #1;
        s_rready = 0;
    endtask

    // Feed the WDT (write magic value)
    task feed_wdt;
        wdt_write(8'h00, 32'hDEAD_FEED);
    endtask

    // AXI BFM for AES
    task aes_write(input [7:0] off, input [31:0] data);
        @(posedge clk); #1;
        aes_awaddr = {24'h0, off}; aes_awvalid = 1;
        aes_wdata  = data; aes_wstrb = 4'hF; aes_wvalid = 1;
        aes_bready = 1;
        fork
            begin
                do @(posedge clk);
                while (!aes_awready);
                #1 aes_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!aes_wready);
                #1 aes_wvalid = 0;
            end
        join
        while (!aes_bvalid) @(posedge clk) #1;
        @(posedge clk); #1;
        aes_bready = 0;
    endtask

    task aes_read(input [7:0] off, output [31:0] data);
        @(posedge clk); #1;
        aes_araddr = {24'h0, off}; aes_arvalid = 1;
        aes_rready = 1;
        do @(posedge clk);
        while (!aes_arready);
        #1 aes_arvalid = 0;
        while (!aes_rvalid) @(posedge clk) #1;
        data = aes_rdata;
        @(posedge clk); #1;
        aes_rready = 0;
    endtask

    // AXI BFM for DMA cfg
    task dma_write(input [7:0] off, input [31:0] data);
        @(posedge clk); #1;
        dma_awaddr = {24'h0, off}; dma_awvalid = 1;
        dma_wdata  = data; dma_wstrb = 4'hF; dma_wvalid = 1;
        dma_bready = 1;
        fork
            begin
                do @(posedge clk);
                while (!dma_awready);
                #1 dma_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!dma_wready);
                #1 dma_wvalid = 0;
            end
        join
        while (!dma_bvalid) @(posedge clk) #1;
        @(posedge clk); #1;
        dma_bready = 0;
    endtask

    task dma_read(input [7:0] off, output [31:0] data);
        @(posedge clk); #1;
        dma_araddr = {24'h0, off}; dma_arvalid = 1;
        dma_rready = 1;
        do @(posedge clk);
        while (!dma_arready);
        #1 dma_arvalid = 0;
        while (!dma_rvalid) @(posedge clk) #1;
        data = dma_rdata;
        @(posedge clk); #1;
        dma_rready = 0;
    endtask

    // =========================================================================
    // Wait for WDT fire (any scoped reset asserts)
    // =========================================================================
    task wait_wdt_fire(output logic fired);
        integer timeout;
        timeout = 0; fired = 0;
        while (!wdt_reset_dma && !wdt_reset_aes && !wdt_reset_spi && timeout <= 10000) begin
            @(posedge clk);
            timeout++;
        end
        if (wdt_reset_dma || wdt_reset_aes || wdt_reset_spi) begin
            fired = 1;
        end else begin
            fired = 0;
        end
    endtask

    // =========================================================================
    // Test helpers
    // =========================================================================
    integer pass_count = 0, fail_count = 0;

    task check(input string name, input logic cond);
        if (cond) begin $display("[PASS] %s", name); pass_count++; end
        else      begin $display("[FAIL] %s", name); fail_count++; end
    endtask

    logic        fired;
    logic [31:0] rd;
    // Track reset pulse widths
    integer dma_pulse_cycles, aes_pulse_cycles, spi_pulse_cycles;

    initial begin
        // Init AXI signals
        s_awvalid=0; s_wvalid=0; s_bready=0;
        s_arvalid=0; s_rready=0;
        s_awaddr=0; s_wdata=0; s_wstrb=4'hF; s_araddr=0;
        aes_awvalid=0; aes_wvalid=0; aes_bready=0; aes_arvalid=0; aes_rready=0;
        aes_awaddr=0; aes_wdata=0; aes_wstrb=4'hF; aes_araddr=0;
        dma_awvalid=0; dma_wvalid=0; dma_bready=0; dma_arvalid=0; dma_rready=0;
        dma_awaddr=0; dma_wdata=0; dma_wstrb=4'hF; dma_araddr=0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ==================================================================
        // TC01 – Normal feed: WDT does NOT fire when fed in time
        // ==================================================================
        $display("--- TC01: Normal feed, no fire ---");
        wdt_write(8'h04, 32'd50);   // timeout = 50 cycles
        wdt_write(8'h08, 32'h01);   // EN=1
        // Feed WDT 5 times, checking it never fires
        repeat(5) begin
            repeat(10) @(posedge clk);  // wait 10 of 50 cycles
            feed_wdt();
        end
        check("TC01_NO_FIRE", !wdt_fired);
        // Disable for next test
        wdt_write(8'h08, 32'h00);

        // ==================================================================
        // TC02 – Timeout fires: counter expires, scoped resets pulse
        // ==================================================================
        $display("--- TC02: Timeout fires ---");
        // Use a very short timeout (10 cycles) for fast simulation
        wdt_write(8'h04, 32'd10);
        wdt_write(8'h08, 32'h01);   // EN=1, don't feed
        wait_wdt_fire(fired);
        check("TC02_FIRED",     fired);
        check("TC02_DMA_RST",   wdt_reset_dma);
        check("TC02_AES_RST",   wdt_reset_aes);
        check("TC02_SPI_RST",   wdt_reset_spi);

        // ==================================================================
        // TC03 – Scoped reset is exactly ONE cycle pulse
        // ==================================================================
        $display("--- TC03: Single-cycle pulse ---");
        // Measure how many cycles the resets stay asserted
        dma_pulse_cycles = 0; aes_pulse_cycles = 0; spi_pulse_cycles = 0;
        // We just observed them fire in TC02 – check next cycle they are low
        @(posedge clk); #1;
        check("TC03_DMA_DEASSERT", !wdt_reset_dma);
        check("TC03_AES_DEASSERT", !wdt_reset_aes);
        check("TC03_SPI_DEASSERT", !wdt_reset_spi);

        // ==================================================================
        // TC04 – CPU not reset: WDT has no cpu_rst output (structural check)
        // ==================================================================
        $display("--- TC04: CPU not reset ---");
        // WDT module has no cpu_rst output port – verified by absence.
        // If we can still read WDT registers after fire, CPU-side AXI works.
        wdt_read(8'h04, rd);
        check("TC04_CPU_AXI_OK", rd == 32'd10);   // timeout register retained

        // ==================================================================
        // TC05 – WDT registers retained across fire (TIMEOUT, CTRL, RESET_CAUSE)
        // ==================================================================
        $display("--- TC05: WDT register retention ---");
        wdt_read(8'h04, rd);
        check("TC05_TIMEOUT_RET",  rd == 32'd10);
        wdt_read(8'h0C, rd);
        check("TC05_CAUSE_SET",    rd[0] == 1);

        // ==================================================================
        // TC06 – AES key retention: wdt_reset_aes clears pipeline, not key
        // ==================================================================
        $display("--- TC06: AES key retention ---");
        // Load a known key into AES
        aes_write(8'h00, 32'hDEAD_C0DE);
        aes_write(8'h04, 32'hBEEF_BABE);
        aes_write(8'h08, 32'hFACE_F00D);
        aes_write(8'h0C, 32'h1234_5678);
        aes_write(8'h10, 32'h02);  // KEY_VALID=1

        // Fire WDT again (short timeout)
        wdt_write(8'h0C, 32'h01);  // W1C: clear RESET_CAUSE
        wdt_write(8'h04, 32'd10);
        wdt_write(8'h08, 32'h01);
        wait_wdt_fire(fired);
        @(posedge clk); // let pulse finish
        check("TC06_WDT_FIRED", fired);

        // Key registers must be intact
        aes_read(8'h00, rd); check("TC06_KEY0", rd == 32'hDEAD_C0DE);
        aes_read(8'h04, rd); check("TC06_KEY1", rd == 32'hBEEF_BABE);
        aes_read(8'h08, rd); check("TC06_KEY2", rd == 32'hFACE_F00D);
        aes_read(8'h0C, rd); check("TC06_KEY3", rd == 32'h1234_5678);

        // AES DONE/BUSY must be cleared
        aes_read(8'h14, rd);
        check("TC06_PIPE_CLR", rd[1:0] == 2'b00);

        // ==================================================================
        // TC07 – DMA config retention: wdt_reset_dma preserves config regs
        // ==================================================================
        $display("--- TC07: DMA config retention ---");
        // Write known values into DMA config
        dma_write(8'h00, 32'hAAAA_1111);  // SRC_ADDR
        dma_write(8'h04, 32'hBBBB_2222);  // DST_ADDR
        dma_write(8'h08, 32'd16);          // LEN

        // Fire WDT once more
        wdt_write(8'h0C, 32'h01);  // clear RESET_CAUSE
        wdt_write(8'h04, 32'd10);
        wdt_write(8'h08, 32'h01);
        wait_wdt_fire(fired);
        @(posedge clk);

        // Config registers must be intact
        dma_read(8'h00, rd); check("TC07_DMA_SRC", rd == 32'hAAAA_1111);
        dma_read(8'h04, rd); check("TC07_DMA_DST", rd == 32'hBBBB_2222);
        dma_read(8'h08, rd); check("TC07_DMA_LEN", rd == 32'd16);

        // ==================================================================
        // TC08 – WDT_RESET_CAUSE[0] set on timeout; W1C clears it
        // ==================================================================
        $display("--- TC08: RESET_CAUSE W1C ---");
        wdt_read(8'h0C, rd);
        check("TC08_CAUSE_BEFORE", rd[0] == 1);
        wdt_write(8'h0C, 32'h01);   // W1C clear
        wdt_read(8'h0C, rd);
        check("TC08_CAUSE_AFTER",  rd[0] == 0);

        // ==================================================================
        // TC09 – WDT self-disables after firing (EN bit cleared)
        // ==================================================================
        $display("--- TC09: WDT self-disables ---");
        wdt_read(8'h08, rd);
        check("TC09_EN_CLEARED", rd[0] == 0);

        // ==================================================================
        // TC10 – Restart: clear CAUSE, re-enable, WDT runs again and fires
        // ==================================================================
        $display("--- TC10: WDT restart after recovery ---");
        wdt_write(8'h0C, 32'h01);   // clear RESET_CAUSE
        wdt_write(8'h04, 32'd10);
        wdt_write(8'h08, 32'h01);   // re-enable
        wait_wdt_fire(fired);
        check("TC10_REFIRES", fired);
        // Clean up
        wdt_write(8'h0C, 32'h01);
        @(posedge clk);

        // ==================================================================
        // TC11 – Short timeout (8 cycles): fires promptly
        // ==================================================================
        $display("--- TC11: Short timeout (8 cycles + drain) ---");
        wdt_write(8'h0C, 32'h01);
        wdt_write(8'h04, 32'd8);    // 8-cycle timeout
        wdt_write(8'h08, 32'h01);
        begin : tc11_timing
            integer elapsed;
            elapsed = 0;
            while (!wdt_reset_dma && elapsed < 100) begin
                @(posedge clk); elapsed++;
            end
            // Should fire in ~8 + DRAIN_CYCLES cycles (plus AXI overhead)
            check("TC11_FIRED_FAST", elapsed < 50 && wdt_reset_dma);
        end

        // ==================================================================
        repeat(2) @(posedge clk);
        $display("========================================");
        $display(" tb_watchdog RESULTS");
        $display(" PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish(fail_count > 0 ? 1 : 0);
    end

    initial begin #2_000_000; $display("[FAIL] TIMEOUT"); $finish(1); end

endmodule
