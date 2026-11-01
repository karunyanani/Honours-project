// Address map verification (from generator):
//   M0 IMEM    0x00000000 - 0x0000FFFF  (65536 B)  mask=01
//   M1 DMEM    0x00010000 - 0x0001FFFF  (65536 B)  mask=11
//   M2 UART    0x10000000 - 0x100000FF  (256 B)  mask=11
//   M3 TIMER   0x10000100 - 0x100001FF  (256 B)  mask=01
//   M4 GPIO    0x10000200 - 0x100002FF  (256 B)  mask=01
//   M5 AES     0x10000300 - 0x100003FF  (256 B)  mask=11
//   M6 DMA     0x10000400 - 0x100004FF  (256 B)  mask=01
//   M7 SPI     0x10000500 - 0x100005FF  (256 B)  mask=11
//   M8 WDT     0x10000600 - 0x100006FF  (256 B)  mask=01
//
// M_BASE_ADDR  = 288'h100006001000050010000400100003001000020010000100100000000001000000000000
// M_ADDR_WIDTH = 288'h000000080000000800000008000000080000000800000008000000080000001000000010
// M_CONNECT    = 18'h1DD7D

// =============================================================================
// soc_axi_interconnect_wrap_2x9.v
//
// AXI4 interconnect wrapper: 2 masters (S-side) x 9 slaves (M-side)
//
// THIS FILE IS GENERATED.  Do not edit by hand.
// Re-generate:
//   python3 scripts/gen_interconnect_wrap.py > rtl/soc_axi_interconnect_wrap_2x9.v
//
// Address map and connectivity are defined in:
//   rtl/soc_defines.vh   (Verilog)
//   scripts/gen_interconnect_wrap.py  (generator / ground truth)
//
// Arbitration policy: round-robin across 4 request channels
//   (one write-request + one read-request channel per master).
//   ARB_LSB_HIGH_PRIORITY=1 means the lower-indexed channel wins ties.
//   Channel encoding: channel 0 = S0-write, 1 = S0-read,
//                     2 = S1-write, 3 = S1-read.
//   DMA (S1) is channels 2/3; RISC-V core (S0) is channels 0/1.
//   Under equal contention, S0 (lower index) wins.  This is documented
//   and tested in tb/tb_interconnect.sv (arbitration test).
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "soc_defines.vh"

module soc_axi_interconnect_wrap_2x9 (
    input  wire clk,
    input  wire rst,

    //
    // S-side (AXI master interfaces – drives these ports)
    //
    // AW channel
    input  wire [2*`AXI_ID_WIDTH-1:0]     s_axi_awid,
    input  wire [2*`AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2*8-1:0]          s_axi_awlen,
    input  wire [2*3-1:0]          s_axi_awsize,
    input  wire [2*2-1:0]          s_axi_awburst,
    input  wire [2-1:0]              s_axi_awlock,
    input  wire [2*4-1:0]          s_axi_awcache,
    input  wire [2*3-1:0]          s_axi_awprot,
    input  wire [2*4-1:0]          s_axi_awqos,
    input  wire [2-1:0]              s_axi_awvalid,
    output wire [2-1:0]              s_axi_awready,

    // W channel
    input  wire [2*`AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [2*`AXI_STRB_WIDTH-1:0]     s_axi_wstrb,
    input  wire [2-1:0]              s_axi_wlast,
    input  wire [2-1:0]              s_axi_wvalid,
    output wire [2-1:0]              s_axi_wready,

    // B channel
    output wire [2*`AXI_ID_WIDTH-1:0]     s_axi_bid,
    output wire [2*2-1:0]          s_axi_bresp,
    output wire [2-1:0]              s_axi_bvalid,
    input  wire [2-1:0]              s_axi_bready,

    // AR channel
    input  wire [2*`AXI_ID_WIDTH-1:0]     s_axi_arid,
    input  wire [2*`AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2*8-1:0]          s_axi_arlen,
    input  wire [2*3-1:0]          s_axi_arsize,
    input  wire [2*2-1:0]          s_axi_arburst,
    input  wire [2-1:0]              s_axi_arlock,
    input  wire [2*4-1:0]          s_axi_arcache,
    input  wire [2*3-1:0]          s_axi_arprot,
    input  wire [2*4-1:0]          s_axi_arqos,
    input  wire [2-1:0]              s_axi_arvalid,
    output wire [2-1:0]              s_axi_arready,

    // R channel
    output wire [2*`AXI_ID_WIDTH-1:0]     s_axi_rid,
    output wire [2*`AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [2*2-1:0]          s_axi_rresp,
    output wire [2-1:0]              s_axi_rlast,
    output wire [2-1:0]              s_axi_rvalid,
    input  wire [2-1:0]              s_axi_rready,

    //
    // M-side (AXI slave interfaces – drives these ports)
    //
    // AW channel
    output wire [9*`AXI_ID_WIDTH-1:0]     m_axi_awid,
    output wire [9*`AXI_ADDR_WIDTH-1:0]     m_axi_awaddr,
    output wire [9*8-1:0]          m_axi_awlen,
    output wire [9*3-1:0]          m_axi_awsize,
    output wire [9*2-1:0]          m_axi_awburst,
    output wire [9-1:0]              m_axi_awlock,
    output wire [9*4-1:0]          m_axi_awcache,
    output wire [9*3-1:0]          m_axi_awprot,
    output wire [9*4-1:0]          m_axi_awqos,
    output wire [9*4-1:0]          m_axi_awregion,
    output wire [9-1:0]              m_axi_awvalid,
    input  wire [9-1:0]              m_axi_awready,

    // W channel
    output wire [9*`AXI_DATA_WIDTH-1:0]     m_axi_wdata,
    output wire [9*`AXI_STRB_WIDTH-1:0]     m_axi_wstrb,
    output wire [9-1:0]              m_axi_wlast,
    output wire [9-1:0]              m_axi_wvalid,
    input  wire [9-1:0]              m_axi_wready,

    // B channel
    input  wire [9*`AXI_ID_WIDTH-1:0]     m_axi_bid,
    input  wire [9*2-1:0]          m_axi_bresp,
    input  wire [9-1:0]              m_axi_bvalid,
    output wire [9-1:0]              m_axi_bready,

    // AR channel
    output wire [9*`AXI_ID_WIDTH-1:0]     m_axi_arid,
    output wire [9*`AXI_ADDR_WIDTH-1:0]     m_axi_araddr,
    output wire [9*8-1:0]          m_axi_arlen,
    output wire [9*3-1:0]          m_axi_arsize,
    output wire [9*2-1:0]          m_axi_arburst,
    output wire [9-1:0]              m_axi_arlock,
    output wire [9*4-1:0]          m_axi_arcache,
    output wire [9*3-1:0]          m_axi_arprot,
    output wire [9*4-1:0]          m_axi_arqos,
    output wire [9*4-1:0]          m_axi_arregion,
    output wire [9-1:0]              m_axi_arvalid,
    input  wire [9-1:0]              m_axi_arready,

    // R channel
    input  wire [9*`AXI_ID_WIDTH-1:0]     m_axi_rid,
    input  wire [9*`AXI_DATA_WIDTH-1:0]     m_axi_rdata,
    input  wire [9*2-1:0]          m_axi_rresp,
    input  wire [9-1:0]              m_axi_rlast,
    input  wire [9-1:0]              m_axi_rvalid,
    output wire [9-1:0]              m_axi_rready

);

    // USER / xUSER signals are disabled (AWUSER_ENABLE = 0)
    wire [2-1:0]  s_axi_awuser_tieoff = 2'b0;
    wire [2-1:0]  s_axi_wuser_tieoff  = 2'b0;
    wire [2-1:0]  s_axi_aruser_tieoff = 2'b0;
    wire [2*1-1:0] s_axi_buser_nc;
    wire [2*1-1:0] s_axi_ruser_nc;
    wire [9*1-1:0] m_axi_awuser_nc;
    wire [9*1-1:0] m_axi_wuser_nc;
    wire [9*1-1:0] m_axi_aruser_nc;
    wire [9*1-1:0] m_axi_buser_tieoff = 9'b0;
    wire [9*1-1:0] m_axi_ruser_tieoff = 9'b0;

    axi_interconnect #(
        .S_COUNT          (2),
        .M_COUNT          (9),
        .DATA_WIDTH       (`AXI_DATA_WIDTH),
        .ADDR_WIDTH       (`AXI_ADDR_WIDTH),
        .STRB_WIDTH       (`AXI_STRB_WIDTH),
        .ID_WIDTH         (`AXI_ID_WIDTH),
        .AWUSER_ENABLE    (0),
        .WUSER_ENABLE     (0),
        .BUSER_ENABLE     (0),
        .ARUSER_ENABLE    (0),
        .RUSER_ENABLE     (0),
        .FORWARD_ID       (0),
        .M_REGIONS        (1),
        .M_BASE_ADDR      (288'h100006001000050010000400100003001000020010000100100000000001000000000000),
        .M_ADDR_WIDTH     (288'h000000080000000800000008000000080000000800000008000000080000001000000010),
        .M_CONNECT_READ   (18'h1DD7D),
        .M_CONNECT_WRITE  (18'h1DD7D),
        .M_SECURE         (9'b0)
    ) u_axi_interconnect (
        .clk              (clk),
        .rst              (rst),
        // S-side (from masters)
        .s_axi_awid       (s_axi_awid),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awlen      (s_axi_awlen),
        .s_axi_awsize     (s_axi_awsize),
        .s_axi_awburst    (s_axi_awburst),
        .s_axi_awlock     (s_axi_awlock),
        .s_axi_awcache    (s_axi_awcache),
        .s_axi_awprot     (s_axi_awprot),
        .s_axi_awqos      (s_axi_awqos),
        .s_axi_awuser     (s_axi_awuser_tieoff),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wlast      (s_axi_wlast),
        .s_axi_wuser      (s_axi_wuser_tieoff),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bid        (s_axi_bid),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_buser      (s_axi_buser_nc),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_arid       (s_axi_arid),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arlen      (s_axi_arlen),
        .s_axi_arsize     (s_axi_arsize),
        .s_axi_arburst    (s_axi_arburst),
        .s_axi_arlock     (s_axi_arlock),
        .s_axi_arcache    (s_axi_arcache),
        .s_axi_arprot     (s_axi_arprot),
        .s_axi_arqos      (s_axi_arqos),
        .s_axi_aruser     (s_axi_aruser_tieoff),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rid        (s_axi_rid),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rlast      (s_axi_rlast),
        .s_axi_ruser      (s_axi_ruser_nc),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        // M-side (to slaves)
        .m_axi_awid       (m_axi_awid),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awlock     (m_axi_awlock),
        .m_axi_awcache    (m_axi_awcache),
        .m_axi_awprot     (m_axi_awprot),
        .m_axi_awqos      (m_axi_awqos),
        .m_axi_awregion   (m_axi_awregion),
        .m_axi_awuser     (m_axi_awuser_nc),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wuser      (m_axi_wuser_nc),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),
        .m_axi_bid        (m_axi_bid),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_buser      (m_axi_buser_tieoff),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready),
        .m_axi_arid       (m_axi_arid),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arlock     (m_axi_arlock),
        .m_axi_arcache    (m_axi_arcache),
        .m_axi_arprot     (m_axi_arprot),
        .m_axi_arqos      (m_axi_arqos),
        .m_axi_arregion   (m_axi_arregion),
        .m_axi_aruser     (m_axi_aruser_nc),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_rid        (m_axi_rid),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_ruser      (m_axi_ruser_tieoff),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready)
    );

endmodule

`resetall

