// =============================================================================
// tb_dma.sv  –  DMA Controller Self-Checking Testbench
//
// Tests (spec §14, DMA verification):
//   TC01 – MODE 0: SPI→AES data movement (16 bytes SPI → 4 AES input words)
//   TC02 – MODE 0: AES_CTRL START|KEY_VALID written after 4 words loaded
//   TC03 – MODE 1: AES→UART ciphertext transmission (16 bytes)
//   TC04 – FIFO back-pressure: uart_tx_dma_req de-asserted mid-transfer
//   TC05 – SPI DRDY gate: DMA waits for spi_rx_dma_req before reading
//   TC06 – Error response from slave propagated to DMA_STATUS ERR bit
//   TC07 – DMA_STATUS BUSY/DONE handshake sequence
//   TC08 – WDT reset clears FSM but retains config registers
//   TC09 – DMA cannot access its own config registers (no loopback)
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_dma;

    parameter CLK_PERIOD = 10;
    parameter AW = 32;
    parameter DW = 32;
    parameter IW = 8;

    logic clk = 0;
    logic rst = 1;
    logic wdt_rst = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // DUT – dma
    // =========================================================================

    // Config slave port (CPU → DMA cfg)
    logic [AW-1:0] cfg_awaddr; logic cfg_awvalid; logic cfg_awready;
    logic [DW-1:0] cfg_wdata;  logic [3:0] cfg_wstrb;
    logic          cfg_wvalid; logic cfg_wready;
    logic [1:0]    cfg_bresp;  logic cfg_bvalid;  logic cfg_bready;
    logic [AW-1:0] cfg_araddr; logic cfg_arvalid; logic cfg_arready;
    logic [DW-1:0] cfg_rdata;  logic [1:0] cfg_rresp;
    logic          cfg_rvalid; logic cfg_rready;

    // AXI4 master port (DMA → peripherals)
    logic [IW-1:0] m_awid;    logic [AW-1:0] m_awaddr;
    logic [7:0]    m_awlen;   logic [2:0]    m_awsize;
    logic [1:0]    m_awburst; logic          m_awlock;
    logic [3:0]    m_awcache; logic [2:0]    m_awprot;
    logic [3:0]    m_awqos;   logic          m_awvalid;
    logic          m_awready;
    logic [DW-1:0] m_wdata;   logic [3:0]    m_wstrb;
    logic          m_wlast;   logic          m_wvalid;
    logic          m_wready;
    logic [IW-1:0] m_bid;     logic [1:0]    m_bresp;
    logic          m_bvalid;  logic          m_bready;
    logic [IW-1:0] m_arid;    logic [AW-1:0] m_araddr;
    logic [7:0]    m_arlen;   logic [2:0]    m_arsize;
    logic [1:0]    m_arburst; logic          m_arlock;
    logic [3:0]    m_arcache; logic [2:0]    m_arprot;
    logic [3:0]    m_arqos;   logic          m_arvalid;
    logic          m_arready;
    logic [IW-1:0] m_rid;     logic [DW-1:0] m_rdata;
    logic [1:0]    m_rresp;   logic          m_rlast;
    logic          m_rvalid;  logic          m_rready;

    // Sideband
    logic spi_rx_dma_req  = 1;
    logic uart_tx_dma_req = 1;

    dma dut (
        .clk(clk), .rst(rst), .wdt_rst(wdt_rst),
        .s_axi_awaddr(cfg_awaddr), .s_axi_awvalid(cfg_awvalid),
        .s_axi_awready(cfg_awready),
        .s_axi_wdata(cfg_wdata),   .s_axi_wstrb(cfg_wstrb),
        .s_axi_wvalid(cfg_wvalid), .s_axi_wready(cfg_wready),
        .s_axi_bresp(cfg_bresp),   .s_axi_bvalid(cfg_bvalid),
        .s_axi_bready(cfg_bready),
        .s_axi_araddr(cfg_araddr), .s_axi_arvalid(cfg_arvalid),
        .s_axi_arready(cfg_arready),
        .s_axi_rdata(cfg_rdata),   .s_axi_rresp(cfg_rresp),
        .s_axi_rvalid(cfg_rvalid), .s_axi_rready(cfg_rready),
        .m_axi_awid(m_awid),       .m_axi_awaddr(m_awaddr),
        .m_axi_awlen(m_awlen),     .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst), .m_axi_awlock(m_awlock),
        .m_axi_awcache(m_awcache), .m_axi_awprot(m_awprot),
        .m_axi_awqos(m_awqos),     .m_axi_awvalid(m_awvalid),
        .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata),     .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast),     .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bid(m_bid),         .m_axi_bresp(m_bresp),
        .m_axi_bvalid(m_bvalid),   .m_axi_bready(m_bready),
        .m_axi_arid(m_arid),       .m_axi_araddr(m_araddr),
        .m_axi_arlen(m_arlen),     .m_axi_arsize(m_arsize),
        .m_axi_arburst(m_arburst), .m_axi_arlock(m_arlock),
        .m_axi_arcache(m_arcache), .m_axi_arprot(m_arprot),
        .m_axi_arqos(m_arqos),     .m_axi_arvalid(m_arvalid),
        .m_axi_arready(m_arready),
        .m_axi_rid(m_rid),         .m_axi_rdata(m_rdata),
        .m_axi_rresp(m_rresp),     .m_axi_rlast(m_rlast),
        .m_axi_rvalid(m_rvalid),   .m_axi_rready(m_rready),
        .spi_rx_dma_req(spi_rx_dma_req),
        .uart_tx_dma_req(uart_tx_dma_req)
    );

    // =========================================================================
    // Peripheral model: responds to AXI master reads/writes
    // Tracks what DMA writes to AES input regs and UART TX
    // =========================================================================
    logic [31:0] aes_in  [0:3];   // AES_DATA_IN0..3
    logic [31:0] aes_ctrl_w;      // last value written to AES_CTRL
    logic [7:0]  uart_bytes [0:15];
    integer      uart_byte_cnt = 0;
    integer      aes_word_cnt  = 0;
    logic        inject_slverr = 0;

    // Read data sources
    // SPI_RX_DATA = 0x10000504 → return sequential pattern
    // AES_DATA_OUT0..3 = 0x10000328..34 → return known ciphertext
    logic [31:0] spi_rx_byte_cnt = 0;
    logic [31:0] aes_out [0:3];
    initial begin
        aes_out[0] = 32'h3925841d;  // FIPS-197 B CT
        aes_out[1] = 32'h02dc09fb;
        aes_out[2] = 32'hdc118597;
        aes_out[3] = 32'h196a0b32;
    end

    reg        mem_aw_seen = 0;
    reg        mem_w_seen  = 0;
    reg [31:0] mem_wr_addr = 0;
    reg [31:0] mem_wr_data = 0;

    // AXI4 slave BFM
    always @(posedge clk) begin
        if (rst) begin
            m_awready   <= 0; m_wready <= 0; m_bvalid <= 0;
            m_arready   <= 0; m_rvalid <= 0;
            m_bid       <= 0; m_bresp <= 0; m_rid <= 0; m_rresp <= 0;
            mem_aw_seen <= 0; mem_w_seen <= 0;
        end else begin
            // Write path
            m_awready <= !m_bvalid;
            m_wready  <= !m_bvalid;
            if (m_awvalid && m_awready) begin
                mem_aw_seen <= 1'b1;
                mem_wr_addr <= m_awaddr;
            end
            if (m_wvalid && m_wready) begin
                mem_w_seen  <= 1'b1;
                mem_wr_data <= m_wdata;
            end
            if ((mem_aw_seen || (m_awvalid && m_awready)) &&
                (mem_w_seen  || (m_wvalid  && m_wready))) begin
                m_bvalid    <= 1;
                m_bid       <= m_awid;
                m_bresp     <= inject_slverr ? 2'b10 : 2'b00;
                mem_aw_seen <= 1'b0;
                mem_w_seen  <= 1'b0;
                // Track writes
                casez (mem_aw_seen ? mem_wr_addr : m_awaddr)
                    32'h10000318: begin aes_in[0] <= (mem_w_seen ? mem_wr_data : m_wdata); aes_word_cnt <= aes_word_cnt + 1; end
                    32'h1000031C: begin aes_in[1] <= (mem_w_seen ? mem_wr_data : m_wdata); aes_word_cnt <= aes_word_cnt + 1; end
                    32'h10000320: begin aes_in[2] <= (mem_w_seen ? mem_wr_data : m_wdata); aes_word_cnt <= aes_word_cnt + 1; end
                    32'h10000324: begin aes_in[3] <= (mem_w_seen ? mem_wr_data : m_wdata); aes_word_cnt <= aes_word_cnt + 1; end
                    32'h10000310: aes_ctrl_w <= (mem_w_seen ? mem_wr_data : m_wdata);
                    32'h10000000: begin
                        if (uart_byte_cnt < 16)
                            uart_bytes[uart_byte_cnt] <= (mem_w_seen ? mem_wr_data[7:0] : m_wdata[7:0]);
                        uart_byte_cnt <= uart_byte_cnt + 1;
                    end
                    default: ;
                endcase
            end else if (m_bvalid && m_bready) begin
                m_bvalid <= 0;
            end
            // Read path
            m_arready <= !m_rvalid;
            if (m_arvalid && m_arready) begin
                m_rid <= m_arid;
                casez (m_araddr)
                    32'h10000504: begin // SPI_RX_DATA
                        m_rdata <= spi_rx_byte_cnt;
                        spi_rx_byte_cnt <= spi_rx_byte_cnt + 1;
                    end
                    32'h10000328: m_rdata <= aes_out[0];
                    32'h1000032C: m_rdata <= aes_out[1];
                    32'h10000330: m_rdata <= aes_out[2];
                    32'h10000334: m_rdata <= aes_out[3];
                    default:      m_rdata <= 32'hDEAD_DEAD;
                endcase
                m_rresp  <= inject_slverr ? 2'b10 : 2'b00;
                m_rlast  <= 1;
                m_rvalid <= 1;
            end else if (m_rvalid && m_rready) begin
                m_rvalid <= 0;
            end
        end
    end

    // =========================================================================
    // Config register BFM
    // =========================================================================
    task cfg_write(input [7:0] off, input [31:0] data);
        @(posedge clk); #1;
        cfg_awaddr = 32'h10000400 | off; cfg_awvalid = 1;
        cfg_wdata  = data; cfg_wstrb = 4'hF; cfg_wvalid = 1;
        cfg_bready = 1;
        fork
            begin
                do @(posedge clk);
                while (!cfg_awready);
                #1 cfg_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!cfg_wready);
                #1 cfg_wvalid = 0;
            end
        join
        while (!cfg_bvalid) @(posedge clk) #1;
        @(posedge clk); #1;
        cfg_bready = 0;
    endtask

    task cfg_read(input [7:0] off, output [31:0] data);
        @(posedge clk); #1;
        cfg_araddr = 32'h10000400 | off; cfg_arvalid = 1;
        cfg_rready = 1;
        do @(posedge clk);
        while (!cfg_arready);
        #1 cfg_arvalid = 0;
        while (!cfg_rvalid) @(posedge clk) #1;
        data = cfg_rdata;
        @(posedge clk); #1;
        cfg_rready = 0;
    endtask

    // Wait for DMA DONE
    task wait_dma_done(output logic ok);
        logic [31:0] st;
        integer to = 0;
        ok = 0;
        st = 0;
        while (st[0] == 0 && to <= 5000) begin
            cfg_read(8'h10, st);
            to++;
        end
        if (st[0] == 1) begin
            ok = 1;
        end else begin
            $display("[FAIL] DMA timeout after %0d polls", to);
            ok = 0;
        end
    endtask

    // =========================================================================
    // Tests
    // =========================================================================
    integer pass_count = 0, fail_count = 0;

    task check(input string name, input logic cond);
        if (cond) begin $display("[PASS] %s", name); pass_count++; end
        else      begin $display("[FAIL] %s", name); fail_count++; end
    endtask

    logic        ok;
    logic [31:0] rd;
    logic [31:0] saved_src;

    initial begin
        cfg_awvalid=0; cfg_wvalid=0; cfg_bready=0;
        cfg_arvalid=0; cfg_rready=0;
        cfg_awaddr=0; cfg_wdata=0; cfg_wstrb=4'hF; cfg_araddr=0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ==================================================================
        // TC01 – MODE 0: SPI → AES  (16 bytes → 4 AES input words)
        // ==================================================================
        $display("--- TC01: DMA MODE0 SPI→AES ---");
        aes_word_cnt = 0; spi_rx_byte_cnt = 0;
        spi_rx_dma_req  = 1;
        uart_tx_dma_req = 1;

        cfg_write(8'h00, 32'h10000504); // SRC = SPI_RX_DATA
        cfg_write(8'h04, 32'h10000318); // DST = AES_DATA_IN0
        cfg_write(8'h08, 32'd16);       // LEN = 16 bytes
        cfg_write(8'h0C, 32'h01);       // START=1, MODE=0 (SPI→AES)

        wait_dma_done(ok);
        check("TC01_DONE",    ok);
        check("TC01_AES_4W",  aes_word_cnt == 4);
        check("TC01_AES_CTRL",aes_ctrl_w   == 32'h03);  // START|KEY_VALID

        // ==================================================================
        // TC02 – AES_CTRL written with START|KEY_VALID after data
        // ==================================================================
        $display("--- TC02: AES_CTRL trigger ---");
        check("TC02_CTRL_VAL", aes_ctrl_w == 32'h03);

        // ==================================================================
        // TC03 – MODE 1: AES → UART  (4×32-bit words = 16 bytes)
        // ==================================================================
        $display("--- TC03: DMA MODE1 AES→UART ---");
        uart_byte_cnt = 0;
        cfg_write(8'h00, 32'h10000328); // SRC = AES_DATA_OUT0
        cfg_write(8'h04, 32'h10000000); // DST = UART_TX_DATA
        cfg_write(8'h08, 32'd16);
        cfg_write(8'h0C, 32'h03);       // START=1, MODE=1 (AES→UART)

        wait_dma_done(ok);
        check("TC03_DONE",      ok);
        check("TC03_BYTES",     uart_byte_cnt == 16);
        // Verify byte order: word 0 MSB first
        check("TC03_BYTE0", uart_bytes[0] == 8'h39);  // aes_out[0][31:24]
        check("TC03_BYTE3", uart_bytes[3] == 8'h1d);  // aes_out[0][7:0]
        check("TC03_BYTE15",uart_bytes[15]== 8'h32);  // aes_out[3][7:0]

        // ==================================================================
        // TC04 – FIFO back-pressure: uart_tx_dma_req de-asserted
        // ==================================================================
        $display("--- TC04: UART back-pressure ---");
        uart_byte_cnt   = 0;
        uart_tx_dma_req = 0;  // hold UART full

        cfg_write(8'h0C, 32'h03);  // restart MODE 1

        // DMA should stall – wait a few cycles, check not yet done
        repeat(20) @(posedge clk);
        cfg_read(8'h10, rd);
        check("TC04_STALL", rd[1] == 1 && rd[0] == 0);  // BUSY=1, DONE=0

        // Release UART space
        uart_tx_dma_req = 1;
        wait_dma_done(ok);
        check("TC04_COMPLETE", ok);

        // ==================================================================
        // TC05 – SPI DRDY gate: DMA waits for spi_rx_dma_req
        // ==================================================================
        $display("--- TC05: SPI DRDY gate ---");
        aes_word_cnt    = 0;
        spi_rx_dma_req  = 0;   // SPI not ready
        spi_rx_byte_cnt = 0;

        cfg_write(8'h0C, 32'h01);   // restart MODE 0

        repeat(20) @(posedge clk);
        cfg_read(8'h10, rd);
        check("TC05_WAIT", rd[1] == 1);  // BUSY, not done

        spi_rx_dma_req = 1;
        wait_dma_done(ok);
        check("TC05_COMPLETE", ok);

        // ==================================================================
        // TC06 – Slave SLVERR sets DMA ERR bit
        // ==================================================================
        $display("--- TC06: Error response ---");
        inject_slverr = 1;
        cfg_write(8'h0C, 32'h03);   // start MODE 1
        wait_dma_done(ok);
        cfg_read(8'h10, rd);
        check("TC06_ERR_BIT", rd[2] == 1);  // ERR flag
        inject_slverr = 0;

        // ==================================================================
        // TC07 – BUSY/DONE sequence
        // ==================================================================
        $display("--- TC07: BUSY/DONE handshake ---");
        // After DONE, STATUS[0] must be 1 and STATUS[1] must be 0
        cfg_write(8'h0C, 32'h03);
        wait_dma_done(ok);
        cfg_read(8'h10, rd);
        check("TC07_DONE_SET",  rd[0] == 1);
        check("TC07_BUSY_CLR",  rd[1] == 0);

        // ==================================================================
        // TC08 – WDT reset: FSM cleared, config retained
        // ==================================================================
        $display("--- TC08: WDT reset retains config ---");
        cfg_write(8'h00, 32'hDEAD_1234);  // SRC_ADDR = known value
        saved_src = 32'hDEAD_1234;

        // Start a transfer, then immediately wdt_rst
        cfg_write(8'h0C, 32'h01);
        @(posedge clk); @(posedge clk);
        wdt_rst = 1; @(posedge clk); wdt_rst = 0;

        // Give it a cycle to settle
        repeat(3) @(posedge clk);
        // DMA must be idle (FSM cleared)
        cfg_read(8'h10, rd);
        check("TC08_FSM_IDLE",    rd[1] == 0);  // BUSY=0
        // Config registers must survive
        cfg_read(8'h00, rd);
        check("TC08_SRC_RETAINED",rd == saved_src);

        // ==================================================================
        // TC09 – DMA cannot issue to its own cfg registers
        //        (enforced by interconnect; verify DMA doesn't try)
        //        DMA AXI master address never touches 0x10000400..4FF
        // ==================================================================
        $display("--- TC09: DMA self-access check ---");
        // Observe m_awaddr and m_araddr during a normal MODE0 transfer
        // If any access targets 0x10000400..0x100004FF → FAIL
        // Simple: run MODE0, monitor addresses in always block
        begin : selfcheck
            logic self_access_detected = 0;
            integer timeout_cnt;

            aes_word_cnt    = 0;
            spi_rx_dma_req  = 1;
            spi_rx_byte_cnt = 0;
            cfg_write(8'h00, 32'h10000504);
            cfg_write(8'h04, 32'h10000318);
            cfg_write(8'h0C, 32'h01);

            timeout_cnt = 0;
            rd = 0;
            while (timeout_cnt < 1000 && !rd[0]) begin
                @(posedge clk);
                if ((m_awvalid && m_awaddr[31:8] == 24'h100004) ||
                    (m_arvalid && m_araddr[31:8] == 24'h100004))
                    self_access_detected = 1;
                timeout_cnt++;
                cfg_read(8'h10, rd);
            end
            check("TC09_NO_SELF_ACCESS", !self_access_detected);
        end

        // ==================================================================
        repeat(2) @(posedge clk);
        $display("========================================");
        $display(" tb_dma RESULTS");
        $display(" PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish(fail_count > 0 ? 1 : 0);
    end

    initial begin #2_000_000; $display("[FAIL] TIMEOUT"); $finish(1); end

endmodule
