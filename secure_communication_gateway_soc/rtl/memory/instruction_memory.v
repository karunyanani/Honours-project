// =============================================================================
// instruction_memory.v  –  64 KB Instruction Memory with AXI4-Lite slave port
//
// Spec refs:
//   - Section 4 : M0, base 0x00000000, 64 KB
//   - Section 5 : CPU access allowed, DMA access denied (enforced in interconnect)
//   - Section 7 : Write strobes honoured; unimplemented reads return 0/OKAY
//   - Section 15: Verilog-2001, synchronous active-high reset
//
// The memory is a simple single-port synchronous SRAM.  Because the
// interconnect guarantees only one master (CPU) can reach this port, no
// internal arbitration is needed here.
//
// Read latency  : 1 cycle (registered address → combinational data mux).
// Write latency : 1 cycle (data written on rising edge when AWVALID & WVALID).
//
// AXI handshake model:
//   AR/AW channels: accept immediately (ARREADY/AWREADY = 1 whenever not busy).
//   W  channel    : accept together with AW (single-beat only, AxLEN=0).
//   R  channel    : data presented one cycle after AR acceptance.
//   B  channel    : write response one cycle after W acceptance.
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module instruction_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter MEM_SIZE   = 65536,  // bytes  (64 KB)
    parameter HEX_FILE   = ""
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
    // Memory array: word-addressable 32-bit words
    // -------------------------------------------------------------------------
    localparam MEM_DEPTH = MEM_SIZE / (DATA_WIDTH/8);   // 16384 words

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    initial begin
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, mem);
        end
    end

    // Word address (drop 2 LSBs for byte→word conversion, keep enough bits)
    localparam WORD_ADDR_W = $clog2(MEM_DEPTH);

    // -------------------------------------------------------------------------
    // Write path
    // -------------------------------------------------------------------------
    reg  [ADDR_WIDTH-1:0] aw_addr_r;
    reg                   aw_pend;   // AW accepted, waiting for W

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
    // Read path  (1-cycle latency: addr registered, data output next cycle)
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
                s_axi_rresp   <= 2'b00; // OKAY
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
