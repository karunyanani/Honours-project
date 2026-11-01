// =============================================================================
// watchdog.v  –  Watchdog Timer with Scoped Datapath Reset
//
// Spec refs:
//   - Section 4  : M8, base 0x10000600, 256 B
//   - Section 5  : CPU only (DMA denied in interconnect)
//   - Section 12 : Scoped reset (DMA+AES+SPI only); CPU/memories/key/DMA cfg
//                  retain; interconnect NOT reset; AXI drain before reset.
//
// Register map (byte offsets):
//   0x00  WDT_FEED         W   : write 0xDEADFEED to reload and keep alive
//   0x04  WDT_TIMEOUT      RW  : timeout in clock cycles (retained across rst)
//   0x08  WDT_CTRL         RW  : [0]=EN  (retained across rst)
//   0x0C  WDT_RESET_CAUSE  R/W1C : [0]=WDT_FIRED (set on timeout, W1C clear)
//
// Scoped reset outputs (active-high, synchronous, single-cycle pulse):
//   wdt_reset_dma    – resets DMA controller datapath
//   wdt_reset_aes    – resets AES processing registers (NOT key)
//   wdt_reset_spi    – resets SPI shift engine
//
// Protocol:
//   1. CPU writes WDT_TIMEOUT then sets WDT_CTRL[0]=1 to start.
//   2. Every successful processing cycle the CPU writes 0xDEAD_FEED to
//      WDT_FEED to reload the counter.
//   3. If the counter reaches zero the watchdog:
//        a) De-asserts WDT_CTRL[0] (stops itself) to prevent re-firing.
//        b) Asserts wdt_reset_dma/aes/spi for one cycle.
//        c) Sets WDT_RESET_CAUSE[0]=1.
//   4. The firmware reads WDT_RESET_CAUSE to detect recovery.
//
// All registers (TIMEOUT, CTRL, RESET_CAUSE) are held in a retention domain
// that is NOT connected to the scoped reset outputs — they survive a WDT
// event and also survive any system-level reset (registers use initial blocks
// for simulation; in silicon they would be in an always-on power domain).
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module watchdog #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter DEFAULT_TIMEOUT = 32'h00FF_FFFF,   // ~16M cycles @ 50 MHz ≈ 336 ms
    parameter DRAIN_CYCLES  = 8        // drain window before asserting scoped rst
) (
    input  wire                    clk,
    input  wire                    rst,    // system reset (NOT scoped-reset)

    // AXI4-Lite slave
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,

    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,

    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,

    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    // Scoped reset outputs (1-cycle pulse, synchronous)
    output reg                     wdt_reset_dma,
    output reg                     wdt_reset_aes,
    output reg                     wdt_reset_spi,

    // Status sideband (for firmware polling)
    output wire                    wdt_fired
);

    // =========================================================================
    // Retained registers (survive scoped reset and system rst in real hw;
    //                     in simulation use initial for reset values)
    // =========================================================================
    reg [31:0] timeout_r;     // WDT_TIMEOUT
    reg        en_r;          // WDT_CTRL[0]
    reg        reset_cause_r; // WDT_RESET_CAUSE[0]

    initial begin
        timeout_r      = DEFAULT_TIMEOUT;
        en_r           = 1'b0;
        reset_cause_r  = 1'b0;
    end

    assign wdt_fired = reset_cause_r;

    // =========================================================================
    // Countdown counter
    // =========================================================================
    reg [31:0] count_r;

    // Drain / reset sequencer
    localparam WDT_RUN   = 2'd0;
    localparam WDT_DRAIN = 2'd1;
    localparam WDT_FIRE  = 2'd2;
    localparam WDT_WAIT  = 2'd3;

    reg [1:0]  wdt_state;
    reg [$clog2(DRAIN_CYCLES+1)-1:0] drain_cnt;

    // AXI write strobes decoded combinational
    reg  [ADDR_WIDTH-1:0] aw_addr_lat;
    reg                   aw_pend;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire [7:0] cur_wr_off = aw_pend ? aw_addr_lat[7:0] : s_axi_awaddr[7:0];
    wire [DATA_WIDTH-1:0] cur_wdata = s_axi_wdata;
    wire [DATA_WIDTH/8-1:0] cur_wstrb = s_axi_wstrb;
    wire wr_fire = (aw_fire && w_fire) || (aw_pend && w_fire);

    localparam WDT_MAGIC = 32'hDEAD_FEED;
    wire feed_pulse     = wr_fire && (cur_wr_off == 8'h00) && (cur_wdata == WDT_MAGIC);
    wire wdt_ctrl_wr    = wr_fire && (cur_wr_off == 8'h08) && cur_wstrb[0];
    wire wdt_rcause_clr = wr_fire && (cur_wr_off == 8'h0C) && cur_wstrb[0] && cur_wdata[0];

    always @(posedge clk) begin
        if (rst) begin
            count_r       <= timeout_r;
            wdt_state     <= WDT_RUN;
            drain_cnt     <= 0;
            wdt_reset_dma <= 1'b0;
            wdt_reset_aes <= 1'b0;
            wdt_reset_spi <= 1'b0;
            reset_cause_r <= 1'b0;
            en_r          <= 1'b0;
        end else begin
            // Default: de-assert scoped resets
            wdt_reset_dma <= 1'b0;
            wdt_reset_aes <= 1'b0;
            wdt_reset_spi <= 1'b0;

            if (wdt_rcause_clr)
                reset_cause_r <= 1'b0;

            if (wdt_ctrl_wr) begin
                en_r <= cur_wdata[0];
                if (cur_wdata[0] && !en_r)
                    count_r <= timeout_r;
            end

            case (wdt_state)
                WDT_RUN: begin
                    if (!en_r) begin
                        count_r <= timeout_r;   // hold reload value when disabled
                    end else if (feed_pulse) begin
                        count_r <= timeout_r;   // kick the dog
                    end else if (count_r == 32'd0) begin
                        // Timeout – enter drain phase
                        wdt_state <= WDT_DRAIN;
                        drain_cnt <= DRAIN_CYCLES - 1;
                    end else begin
                        count_r   <= count_r - 1'b1;
                    end
                end

                WDT_DRAIN: begin
                    // Hold off for DRAIN_CYCLES to let outstanding AXI txns
                    // complete naturally (spec §12 drain/timeout/isolation).
                    if (drain_cnt == 0) begin
                        wdt_state <= WDT_FIRE;
                    end else begin
                        drain_cnt <= drain_cnt - 1'b1;
                    end
                end

                WDT_FIRE: begin
                    // Assert scoped resets for exactly one cycle
                    wdt_reset_dma <= 1'b1;
                    wdt_reset_aes <= 1'b1;
                    wdt_reset_spi <= 1'b1;
                    reset_cause_r <= 1'b1;
                    en_r          <= 1'b0;   // self-disable to prevent re-fire
                    wdt_state     <= WDT_WAIT;
                end

                WDT_WAIT: begin
                    // Stay here until firmware clears reset_cause and re-enables.
                    if (wdt_rcause_clr || (wdt_ctrl_wr && cur_wdata[0])) begin
                        wdt_state <= WDT_RUN;
                        count_r   <= timeout_r;
                    end
                end

                default: wdt_state <= WDT_RUN;
            endcase
        end
    end

    // =========================================================================
    // AXI4-Lite slave – write path
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_pend       <= 1'b0;
            aw_addr_lat   <= {ADDR_WIDTH{1'b0}};
            timeout_r     <= DEFAULT_TIMEOUT;
        end else begin
            if (aw_fire && w_fire) begin
                if (cur_wr_off == 8'h04) begin
                    if (cur_wstrb[0]) timeout_r[ 7: 0] <= cur_wdata[ 7: 0];
                    if (cur_wstrb[1]) timeout_r[15: 8] <= cur_wdata[15: 8];
                    if (cur_wstrb[2]) timeout_r[23:16] <= cur_wdata[23:16];
                    if (cur_wstrb[3]) timeout_r[31:24] <= cur_wdata[31:24];
                end
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
                aw_pend       <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end else if (aw_fire) begin
                aw_addr_lat   <= s_axi_awaddr;
                aw_pend       <= 1'b1;
                s_axi_awready <= 1'b0;
            end else if (aw_pend && w_fire) begin
                if (cur_wr_off == 8'h04) begin
                    if (cur_wstrb[0]) timeout_r[ 7: 0] <= cur_wdata[ 7: 0];
                    if (cur_wstrb[1]) timeout_r[15: 8] <= cur_wdata[15: 8];
                    if (cur_wstrb[2]) timeout_r[23:16] <= cur_wdata[23:16];
                    if (cur_wstrb[3]) timeout_r[31:24] <= cur_wdata[31:24];
                end
                s_axi_wready  <= 1'b0;
                aw_pend       <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end

            // B
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end
        end
    end

    // Handle state return when reset_cause is cleared
    always @(posedge clk) begin
        if (!rst) begin
            if (wdt_state == WDT_WAIT && !reset_cause_r)
                wdt_state <= WDT_RUN;
        end
    end

    // =========================================================================
    // AXI4-Lite slave – read path
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                case (s_axi_araddr[7:0])
                    8'h00: s_axi_rdata <= 32'd0;               // WDT_FEED (write-only)
                    8'h04: s_axi_rdata <= timeout_r;
                    8'h08: s_axi_rdata <= {31'd0, en_r};
                    8'h0C: s_axi_rdata <= {31'd0, reset_cause_r};
                    default: s_axi_rdata <= 32'd0;
                endcase
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

endmodule

`resetall
