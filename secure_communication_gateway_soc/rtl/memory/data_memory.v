// =============================================================================
// data_memory.v  –  64 KB Data Memory with AXI4-Lite slave port
//
// Spec refs:
//   - Section 4 : M1, base 0x00010000, 64 KB
//   - Section 5 : CPU and DMA both allowed
//   - Section 7 : Write strobes honoured
//   - Section 12: Watchdog scoped recovery – memory contents retained
//   - Section 15: Verilog-2001, synchronous active-high reset
//
// Identical structure to instruction_memory but writable by both masters.
// The interconnect handles arbitration; this module sees a single AXI port.
//
// Read latency  : 1 cycle
// Write latency : 1 cycle
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module data_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter MEM_SIZE   = 65536   // bytes (64 KB)
) (
    input  wire                    clk,
    input  wire                    rst,

    // AXI4 slave interface (single-beat)
    // Write address channel
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]              s_axi_awprot,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,

    // Write data channel
    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,

    // Write response channel
    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,

    // Read address channel
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]              s_axi_arprot,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,

    // Read data channel
    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready
);

    // -------------------------------------------------------------------------
    // Memory array
    // -------------------------------------------------------------------------
    localparam MEM_DEPTH   = MEM_SIZE / (DATA_WIDTH/8);  // 16384 words
    localparam WORD_ADDR_W = $clog2(MEM_DEPTH);          // 14 bits

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // NOTE: mem contents are intentionally NOT cleared on rst (spec §12:
    //   "Instruction and data memories SHALL retain their contents" across
    //   watchdog scoped recovery).

    // -------------------------------------------------------------------------
    // Write path
    // -------------------------------------------------------------------------
    reg  [ADDR_WIDTH-1:0] aw_addr_r;
    reg                   aw_pend;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire [ADDR_WIDTH-1:0] cur_wr_addr = aw_pend ? aw_addr_r : s_axi_awaddr;

    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_pend       <= 1'b0;
            aw_addr_r     <= {ADDR_WIDTH{1'b0}};
        end else begin
            // -----------------------------------------------------------------
            // Write acceptance & execution
            // -----------------------------------------------------------------
            if (aw_fire && w_fire) begin
                if (s_axi_wstrb[0]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][ 7: 0] <= s_axi_wdata[ 7: 0];
                if (s_axi_wstrb[1]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][15: 8] <= s_axi_wdata[15: 8];
                if (s_axi_wstrb[2]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][23:16] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][31:24] <= s_axi_wdata[31:24];

                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
                aw_pend       <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end else if (aw_fire) begin
                aw_addr_r     <= s_axi_awaddr;
                aw_pend       <= 1'b1;
                s_axi_awready <= 1'b0;
            end else if (aw_pend && w_fire) begin
                if (s_axi_wstrb[0]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][ 7: 0] <= s_axi_wdata[ 7: 0];
                if (s_axi_wstrb[1]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][15: 8] <= s_axi_wdata[15: 8];
                if (s_axi_wstrb[2]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][23:16] <= s_axi_wdata[23:16];
                if (s_axi_wstrb[3]) mem[cur_wr_addr[WORD_ADDR_W+1:2]][31:24] <= s_axi_wdata[31:24];

                s_axi_wready  <= 1'b0;
                aw_pend       <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end

            // -----------------------------------------------------------------
            // B handshake
            // -----------------------------------------------------------------
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read path
    // -------------------------------------------------------------------------
    reg [WORD_ADDR_W-1:0] rd_addr_r;
    reg                   rd_pend;

    always @(posedge clk) begin
        if (rst) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            rd_pend       <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rd_addr_r     <= s_axi_araddr[WORD_ADDR_W+1:2];
                rd_pend       <= 1'b1;
                s_axi_arready <= 1'b0;
            end

            if (rd_pend) begin
                s_axi_rdata   <= mem[rd_addr_r];
                s_axi_rresp   <= 2'b00;
                s_axi_rvalid  <= 1'b1;
                rd_pend       <= 1'b0;
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

endmodule

`resetall
