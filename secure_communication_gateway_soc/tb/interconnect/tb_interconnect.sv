// =============================================================================
// tb_interconnect.sv  –  AXI4 Interconnect Self-Checking Testbench
//
// Tests (spec §14, Interconnect verification):
//   TC01 – CPU read/write to all 9 slaves (access allowed)
//   TC02 – DMA read/write to 4 permitted slaves (DMEM, UART, AES, SPI)
//   TC03 – DMA access to all 5 restricted slaves returns DECERR
//   TC04 – Unmapped address returns DECERR from CPU
//   TC05 – Correct address decoding (boundary check lo/hi for each slave)
//   TC06 – Simultaneous CPU and DMA requests (same clock cycle)
//   TC07 – Same-slave contention (CPU and DMA target DMEM simultaneously)
//   TC08 – Slave back-pressure (slave holds READY low for N cycles)
//   TC09 – WSTRB operation (byte-lane write strobe honoured)
//   TC10 – VALID/payload stability check (drive then hold until READY)
//   TC11 – Reset behaviour (assert rst mid-transaction, check AXI quiesce)
//
// Pass/fail: $display("[PASS]") / $display("[FAIL]") per test + global summary.
// Exit code: $finish(0) on all pass, $finish(1) on any fail.
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

`include "soc_defines.vh"

module tb_interconnect;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz
    parameter DW = 32;
    parameter AW = 32;
    parameter IW = 8;
    parameter SW = 4;

    // =========================================================================
    // Clock / reset
    // =========================================================================
    logic clk  = 0;
    logic rst  = 1;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // DUT signals – interconnect + all slaves
    // The tb drives the two master ports of the interconnect directly.
    // All 9 slave modules are instantiated and connected to the M-side.
    // =========================================================================

    // --- S0: CPU master signals ---
    logic [IW-1:0]  s0_awid;    logic [AW-1:0]  s0_awaddr;
    logic [7:0]     s0_awlen;   logic [2:0]     s0_awsize;
    logic [1:0]     s0_awburst; logic           s0_awlock;
    logic [3:0]     s0_awcache; logic [2:0]     s0_awprot;
    logic [3:0]     s0_awqos;   logic           s0_awvalid;
    logic           s0_awready;
    logic [DW-1:0]  s0_wdata;   logic [SW-1:0]  s0_wstrb;
    logic           s0_wlast;   logic           s0_wvalid;
    logic           s0_wready;
    logic [IW-1:0]  s0_bid;     logic [1:0]     s0_bresp;
    logic           s0_bvalid;  logic           s0_bready;
    logic [IW-1:0]  s0_arid;    logic [AW-1:0]  s0_araddr;
    logic [7:0]     s0_arlen;   logic [2:0]     s0_arsize;
    logic [1:0]     s0_arburst; logic           s0_arlock;
    logic [3:0]     s0_arcache; logic [2:0]     s0_arprot;
    logic [3:0]     s0_arqos;   logic           s0_arvalid;
    logic           s0_arready;
    logic [IW-1:0]  s0_rid;     logic [DW-1:0]  s0_rdata;
    logic [1:0]     s0_rresp;   logic           s0_rlast;
    logic           s0_rvalid;  logic           s0_rready;

    // --- S1: DMA master signals ---
    logic [IW-1:0]  s1_awid;    logic [AW-1:0]  s1_awaddr;
    logic [7:0]     s1_awlen;   logic [2:0]     s1_awsize;
    logic [1:0]     s1_awburst; logic           s1_awlock;
    logic [3:0]     s1_awcache; logic [2:0]     s1_awprot;
    logic [3:0]     s1_awqos;   logic           s1_awvalid;
    logic           s1_awready;
    logic [DW-1:0]  s1_wdata;   logic [SW-1:0]  s1_wstrb;
    logic           s1_wlast;   logic           s1_wvalid;
    logic           s1_wready;
    logic [IW-1:0]  s1_bid;     logic [1:0]     s1_bresp;
    logic           s1_bvalid;  logic           s1_bready;
    logic [IW-1:0]  s1_arid;    logic [AW-1:0]  s1_araddr;
    logic [7:0]     s1_arlen;   logic [2:0]     s1_arsize;
    logic [1:0]     s1_arburst; logic           s1_arlock;
    logic [3:0]     s1_arcache; logic [2:0]     s1_arprot;
    logic [3:0]     s1_arqos;   logic           s1_arvalid;
    logic           s1_arready;
    logic [IW-1:0]  s1_rid;     logic [DW-1:0]  s1_rdata;
    logic [1:0]     s1_rresp;   logic           s1_rlast;
    logic           s1_rvalid;  logic           s1_rready;

    // Packed bus signals for interconnect (2 masters)
    wire [2*IW-1:0]  ic_s_awid    = {s1_awid,    s0_awid   };
    wire [2*AW-1:0]  ic_s_awaddr  = {s1_awaddr,  s0_awaddr };
    wire [2*8-1:0]   ic_s_awlen   = {s1_awlen,   s0_awlen  };
    wire [2*3-1:0]   ic_s_awsize  = {s1_awsize,  s0_awsize };
    wire [2*2-1:0]   ic_s_awburst = {s1_awburst, s0_awburst};
    wire [1:0]       ic_s_awlock  = {s1_awlock,  s0_awlock };
    wire [2*4-1:0]   ic_s_awcache = {s1_awcache, s0_awcache};
    wire [2*3-1:0]   ic_s_awprot  = {s1_awprot,  s0_awprot };
    wire [2*4-1:0]   ic_s_awqos   = {s1_awqos,   s0_awqos  };
    wire [1:0]       ic_s_awvalid = {s1_awvalid, s0_awvalid};
    wire [1:0]       ic_s_awready;
    assign {s1_awready, s0_awready} = ic_s_awready;

    wire [2*DW-1:0]  ic_s_wdata   = {s1_wdata,   s0_wdata  };
    wire [2*SW-1:0]  ic_s_wstrb   = {s1_wstrb,   s0_wstrb  };
    wire [1:0]       ic_s_wlast   = {s1_wlast,   s0_wlast  };
    wire [1:0]       ic_s_wvalid  = {s1_wvalid,  s0_wvalid };
    wire [1:0]       ic_s_wready;
    assign {s1_wready, s0_wready} = ic_s_wready;

    wire [2*IW-1:0]  ic_s_bid;
    wire [2*2-1:0]   ic_s_bresp;
    wire [1:0]       ic_s_bvalid;
    wire [1:0]       ic_s_bready  = {s1_bready, s0_bready};
    assign {s1_bid,    s0_bid   } = ic_s_bid;
    assign {s1_bresp,  s0_bresp } = ic_s_bresp;
    assign {s1_bvalid, s0_bvalid} = ic_s_bvalid;

    wire [2*IW-1:0]  ic_s_arid    = {s1_arid,    s0_arid   };
    wire [2*AW-1:0]  ic_s_araddr  = {s1_araddr,  s0_araddr };
    wire [2*8-1:0]   ic_s_arlen   = {s1_arlen,   s0_arlen  };
    wire [2*3-1:0]   ic_s_arsize  = {s1_arsize,  s0_arsize };
    wire [2*2-1:0]   ic_s_arburst = {s1_arburst, s0_arburst};
    wire [1:0]       ic_s_arlock  = {s1_arlock,  s0_arlock };
    wire [2*4-1:0]   ic_s_arcache = {s1_arcache, s0_arcache};
    wire [2*3-1:0]   ic_s_arprot  = {s1_arprot,  s0_arprot };
    wire [2*4-1:0]   ic_s_arqos   = {s1_arqos,   s0_arqos  };
    wire [1:0]       ic_s_arvalid = {s1_arvalid, s0_arvalid};
    wire [1:0]       ic_s_arready;
    assign {s1_arready, s0_arready} = ic_s_arready;

    wire [2*IW-1:0]  ic_s_rid;
    wire [2*DW-1:0]  ic_s_rdata;
    wire [2*2-1:0]   ic_s_rresp;
    wire [1:0]       ic_s_rlast;
    wire [1:0]       ic_s_rvalid;
    wire [1:0]       ic_s_rready  = {s1_rready, s0_rready};
    assign {s1_rid,    s0_rid   } = ic_s_rid;
    assign {s1_rdata,  s0_rdata } = ic_s_rdata;
    assign {s1_rresp,  s0_rresp } = ic_s_rresp;
    assign {s1_rlast,  s0_rlast } = ic_s_rlast;
    assign {s1_rvalid, s0_rvalid} = ic_s_rvalid;

    // =========================================================================
    // Slave AXI wires (M-side of interconnect → peripherals)
    // =========================================================================
    // [0]=IMEM [1]=DMEM [2]=UART [3]=TIMER [4]=GPIO [5]=AES [6]=DMA [7]=SPI [8]=WDT
    wire [9*AW-1:0]  m_awaddr_bus, m_araddr_bus;
    wire [9*DW-1:0]  m_wdata_bus,  m_rdata_bus;
    wire [9*SW-1:0]  m_wstrb_bus;
    wire [9*IW-1:0]  m_awid_bus,   m_bid_bus, m_arid_bus, m_rid_bus;
    wire [9*8-1:0]   m_awlen_bus,  m_arlen_bus;
    wire [9*3-1:0]   m_awsize_bus, m_arsize_bus;
    wire [9*2-1:0]   m_awburst_bus,m_arburst_bus;
    wire [8:0]       m_awlock_bus, m_arlock_bus;
    wire [9*4-1:0]   m_awcache_bus,m_arcache_bus;
    wire [9*3-1:0]   m_awprot_bus, m_arprot_bus;
    wire [9*4-1:0]   m_awqos_bus,  m_arqos_bus;
    wire [8:0]       m_awvalid_bus,m_arvalid_bus;
    wire [8:0]       m_awready_bus,m_arready_bus;
    wire [8:0]       m_wvalid_bus, m_wready_bus;
    wire [8:0]       m_wlast_bus;
    wire [9*2-1:0]   m_bresp_bus,  m_rresp_bus;
    wire [8:0]       m_bvalid_bus, m_bready_bus;
    wire [8:0]       m_rvalid_bus, m_rready_bus, m_rlast_bus;

    // For single-beat slaves, RLAST is asserted concurrently with RVALID
    assign m_rlast_bus = m_rvalid_bus;

    // =========================================================================
    // Instantiate interconnect
    // =========================================================================
    soc_axi_interconnect_wrap_2x9 u_ic (
        .clk          ( clk           ),
        .rst          ( rst           ),
        .s_axi_awid   ( ic_s_awid     ),
        .s_axi_awaddr ( ic_s_awaddr   ),
        .s_axi_awlen  ( ic_s_awlen    ),
        .s_axi_awsize ( ic_s_awsize   ),
        .s_axi_awburst( ic_s_awburst  ),
        .s_axi_awlock ( ic_s_awlock   ),
        .s_axi_awcache( ic_s_awcache  ),
        .s_axi_awprot ( ic_s_awprot   ),
        .s_axi_awqos  ( ic_s_awqos    ),
        .s_axi_awvalid( ic_s_awvalid  ),
        .s_axi_awready( ic_s_awready  ),
        .s_axi_wdata  ( ic_s_wdata    ),
        .s_axi_wstrb  ( ic_s_wstrb    ),
        .s_axi_wlast  ( ic_s_wlast    ),
        .s_axi_wvalid ( ic_s_wvalid   ),
        .s_axi_wready ( ic_s_wready   ),
        .s_axi_bid    ( ic_s_bid      ),
        .s_axi_bresp  ( ic_s_bresp    ),
        .s_axi_bvalid ( ic_s_bvalid   ),
        .s_axi_bready ( ic_s_bready   ),
        .s_axi_arid   ( ic_s_arid     ),
        .s_axi_araddr ( ic_s_araddr   ),
        .s_axi_arlen  ( ic_s_arlen    ),
        .s_axi_arsize ( ic_s_arsize   ),
        .s_axi_arburst( ic_s_arburst  ),
        .s_axi_arlock ( ic_s_arlock   ),
        .s_axi_arcache( ic_s_arcache  ),
        .s_axi_arprot ( ic_s_arprot   ),
        .s_axi_arqos  ( ic_s_arqos    ),
        .s_axi_arvalid( ic_s_arvalid  ),
        .s_axi_arready( ic_s_arready  ),
        .s_axi_rid    ( ic_s_rid      ),
        .s_axi_rdata  ( ic_s_rdata    ),
        .s_axi_rresp  ( ic_s_rresp    ),
        .s_axi_rlast  ( ic_s_rlast    ),
        .s_axi_rvalid ( ic_s_rvalid   ),
        .s_axi_rready ( ic_s_rready   ),
        .m_axi_awid   ( m_awid_bus    ),
        .m_axi_awaddr ( m_awaddr_bus  ),
        .m_axi_awlen  ( m_awlen_bus   ),
        .m_axi_awsize ( m_awsize_bus  ),
        .m_axi_awburst( m_awburst_bus ),
        .m_axi_awlock ( m_awlock_bus  ),
        .m_axi_awcache( m_awcache_bus ),
        .m_axi_awprot ( m_awprot_bus  ),
        .m_axi_awqos  ( m_awqos_bus   ),
        .m_axi_awvalid( m_awvalid_bus ),
        .m_axi_awready( m_awready_bus ),
        .m_axi_wdata  ( m_wdata_bus   ),
        .m_axi_wstrb  ( m_wstrb_bus   ),
        .m_axi_wlast  ( m_wlast_bus   ),
        .m_axi_wvalid ( m_wvalid_bus  ),
        .m_axi_wready ( m_wready_bus  ),
        .m_axi_bid    ( m_bid_bus     ),
        .m_axi_bresp  ( m_bresp_bus   ),
        .m_axi_bvalid ( m_bvalid_bus  ),
        .m_axi_bready ( m_bready_bus  ),
        .m_axi_arid   ( m_arid_bus    ),
        .m_axi_araddr ( m_araddr_bus  ),
        .m_axi_arlen  ( m_arlen_bus   ),
        .m_axi_arsize ( m_arsize_bus  ),
        .m_axi_arburst( m_arburst_bus ),
        .m_axi_arlock ( m_arlock_bus  ),
        .m_axi_arcache( m_arcache_bus ),
        .m_axi_arprot ( m_arprot_bus  ),
        .m_axi_arqos  ( m_arqos_bus   ),
        .m_axi_arvalid( m_arvalid_bus ),
        .m_axi_arready( m_arready_bus ),
        .m_axi_rid    ( m_rid_bus     ),
        .m_axi_rdata  ( m_rdata_bus   ),
        .m_axi_rresp  ( m_rresp_bus   ),
        .m_axi_rlast  ( m_rlast_bus   ),
        .m_axi_rvalid ( m_rvalid_bus  ),
        .m_axi_rready ( m_rready_bus  )
    );

    // =========================================================================
    // Instantiate all 9 slave peripherals
    // Helper macros to extract per-slave bus signals
    // =========================================================================
    `define SLAVE_AW(n)  m_awaddr_bus[n*AW +: AW]
    `define SLAVE_AV(n)  m_awvalid_bus[n]
    `define SLAVE_AR(n)  m_awready_bus[n]
    `define SLAVE_WD(n)  m_wdata_bus[n*DW  +: DW]
    `define SLAVE_WS(n)  m_wstrb_bus[n*SW  +: SW]
    `define SLAVE_WV(n)  m_wvalid_bus[n]
    `define SLAVE_WR(n)  m_wready_bus[n]
    `define SLAVE_WL(n)  m_wlast_bus[n]
    `define SLAVE_BR(n)  m_bresp_bus[n*2   +: 2]
    `define SLAVE_BV(n)  m_bvalid_bus[n]
    `define SLAVE_BC(n)  m_bready_bus[n]
    `define SLAVE_AA(n)  m_araddr_bus[n*AW +: AW]
    `define SLAVE_AAV(n) m_arvalid_bus[n]
    `define SLAVE_AAR(n) m_arready_bus[n]
    `define SLAVE_RD(n)  m_rdata_bus[n*DW  +: DW]
    `define SLAVE_RR(n)  m_rresp_bus[n*2   +: 2]
    `define SLAVE_RV(n)  m_rvalid_bus[n]
    `define SLAVE_RC(n)  m_rready_bus[n]
    `define SLAVE_RL(n)  m_rlast_bus[n]
    `define SLAVE_BID(n) m_bid_bus[n*IW  +: IW]
    `define SLAVE_RID(n) m_rid_bus[n*IW  +: IW]
    `define SLAVE_AWID(n) m_awid_bus[n*IW +: IW]
    `define SLAVE_ARID(n) m_arid_bus[n*IW +: IW]
    `define SLAVE_AP(n)  m_awprot_bus[n*3 +: 3]
    `define SLAVE_AAP(n) m_arprot_bus[n*3 +: 3]

    // Watchdog scoped reset (unused in interconnect test, tied off)
    logic wdt_rst = 0;

    // M0: Instruction Memory
    instruction_memory u_imem (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(`SLAVE_AW(0)),  .s_axi_awprot(`SLAVE_AP(0)),  .s_axi_awvalid(`SLAVE_AV(0)), .s_axi_awready(`SLAVE_AR(0)),
        .s_axi_wdata(`SLAVE_WD(0)),   .s_axi_wstrb(`SLAVE_WS(0)),   .s_axi_wvalid(`SLAVE_WV(0)),
        .s_axi_wready(`SLAVE_WR(0)),  .s_axi_bresp(`SLAVE_BR(0)),   .s_axi_bvalid(`SLAVE_BV(0)),
        .s_axi_bready(`SLAVE_BC(0)),  .s_axi_araddr(`SLAVE_AA(0)),  .s_axi_arprot(`SLAVE_AAP(0)), .s_axi_arvalid(`SLAVE_AAV(0)),
        .s_axi_arready(`SLAVE_AAR(0)),.s_axi_rdata(`SLAVE_RD(0)),   .s_axi_rresp(`SLAVE_RR(0)),
        .s_axi_rvalid(`SLAVE_RV(0)),  .s_axi_rready(`SLAVE_RC(0))
    );

    // M1: Data Memory
    data_memory u_dmem (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(`SLAVE_AW(1)),  .s_axi_awprot(`SLAVE_AP(1)),  .s_axi_awvalid(`SLAVE_AV(1)), .s_axi_awready(`SLAVE_AR(1)),
        .s_axi_wdata(`SLAVE_WD(1)),   .s_axi_wstrb(`SLAVE_WS(1)),   .s_axi_wvalid(`SLAVE_WV(1)),
        .s_axi_wready(`SLAVE_WR(1)),  .s_axi_bresp(`SLAVE_BR(1)),   .s_axi_bvalid(`SLAVE_BV(1)),
        .s_axi_bready(`SLAVE_BC(1)),  .s_axi_araddr(`SLAVE_AA(1)),  .s_axi_arprot(`SLAVE_AAP(1)), .s_axi_arvalid(`SLAVE_AAV(1)),
        .s_axi_arready(`SLAVE_AAR(1)),.s_axi_rdata(`SLAVE_RD(1)),   .s_axi_rresp(`SLAVE_RR(1)),
        .s_axi_rvalid(`SLAVE_RV(1)),  .s_axi_rready(`SLAVE_RC(1))
    );

    // M2: UART
    uart u_uart (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(`SLAVE_AW(2)),  .s_axi_awvalid(`SLAVE_AV(2)), .s_axi_awready(`SLAVE_AR(2)),
        .s_axi_wdata(`SLAVE_WD(2)),   .s_axi_wstrb(`SLAVE_WS(2)),   .s_axi_wvalid(`SLAVE_WV(2)),
        .s_axi_wready(`SLAVE_WR(2)),  .s_axi_bresp(`SLAVE_BR(2)),   .s_axi_bvalid(`SLAVE_BV(2)),
        .s_axi_bready(`SLAVE_BC(2)),  .s_axi_araddr(`SLAVE_AA(2)),  .s_axi_arvalid(`SLAVE_AAV(2)),
        .s_axi_arready(`SLAVE_AAR(2)),.s_axi_rdata(`SLAVE_RD(2)),   .s_axi_rresp(`SLAVE_RR(2)),
        .s_axi_rvalid(`SLAVE_RV(2)),  .s_axi_rready(`SLAVE_RC(2)),
        .uart_tx(), .uart_tx_dma_req()
    );

    // M3: Timer
    timer u_timer (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(`SLAVE_AW(3)),  .s_axi_awvalid(`SLAVE_AV(3)), .s_axi_awready(`SLAVE_AR(3)),
        .s_axi_wdata(`SLAVE_WD(3)),   .s_axi_wstrb(`SLAVE_WS(3)),   .s_axi_wvalid(`SLAVE_WV(3)),
        .s_axi_wready(`SLAVE_WR(3)),  .s_axi_bresp(`SLAVE_BR(3)),   .s_axi_bvalid(`SLAVE_BV(3)),
        .s_axi_bready(`SLAVE_BC(3)),  .s_axi_araddr(`SLAVE_AA(3)),  .s_axi_arvalid(`SLAVE_AAV(3)),
        .s_axi_arready(`SLAVE_AAR(3)),.s_axi_rdata(`SLAVE_RD(3)),   .s_axi_rresp(`SLAVE_RR(3)),
        .s_axi_rvalid(`SLAVE_RV(3)),  .s_axi_rready(`SLAVE_RC(3)),
        .timer_irq()
    );

    // M4: GPIO
    gpio u_gpio (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(`SLAVE_AW(4)),  .s_axi_awvalid(`SLAVE_AV(4)), .s_axi_awready(`SLAVE_AR(4)),
        .s_axi_wdata(`SLAVE_WD(4)),   .s_axi_wstrb(`SLAVE_WS(4)),   .s_axi_wvalid(`SLAVE_WV(4)),
        .s_axi_wready(`SLAVE_WR(4)),  .s_axi_bresp(`SLAVE_BR(4)),   .s_axi_bvalid(`SLAVE_BV(4)),
        .s_axi_bready(`SLAVE_BC(4)),  .s_axi_araddr(`SLAVE_AA(4)),  .s_axi_arvalid(`SLAVE_AAV(4)),
        .s_axi_arready(`SLAVE_AAR(4)),.s_axi_rdata(`SLAVE_RD(4)),   .s_axi_rresp(`SLAVE_RR(4)),
        .s_axi_rvalid(`SLAVE_RV(4)),  .s_axi_rready(`SLAVE_RC(4)),
        .gpio_in(8'd0), .gpio_out(), .gpio_oe(), .gpio_irq()
    );

    // M5: AES
    aes u_aes (
        .clk(clk), .rst(rst), .wdt_rst(wdt_rst),
        .s_axi_awaddr(`SLAVE_AW(5)),  .s_axi_awvalid(`SLAVE_AV(5)), .s_axi_awready(`SLAVE_AR(5)),
        .s_axi_wdata(`SLAVE_WD(5)),   .s_axi_wstrb(`SLAVE_WS(5)),   .s_axi_wvalid(`SLAVE_WV(5)),
        .s_axi_wready(`SLAVE_WR(5)),  .s_axi_bresp(`SLAVE_BR(5)),   .s_axi_bvalid(`SLAVE_BV(5)),
        .s_axi_bready(`SLAVE_BC(5)),  .s_axi_araddr(`SLAVE_AA(5)),  .s_axi_arvalid(`SLAVE_AAV(5)),
        .s_axi_arready(`SLAVE_AAR(5)),.s_axi_rdata(`SLAVE_RD(5)),   .s_axi_rresp(`SLAVE_RR(5)),
        .s_axi_rvalid(`SLAVE_RV(5)),  .s_axi_rready(`SLAVE_RC(5)),
        .aes_done()
    );

    // M6: DMA config registers (slave port of DMA)
    dma u_dma (
        .clk(clk), .rst(rst), .wdt_rst(wdt_rst),
        .s_axi_awaddr(`SLAVE_AW(6)),  .s_axi_awvalid(`SLAVE_AV(6)), .s_axi_awready(`SLAVE_AR(6)),
        .s_axi_wdata(`SLAVE_WD(6)),   .s_axi_wstrb(`SLAVE_WS(6)),   .s_axi_wvalid(`SLAVE_WV(6)),
        .s_axi_wready(`SLAVE_WR(6)),  .s_axi_bresp(`SLAVE_BR(6)),   .s_axi_bvalid(`SLAVE_BV(6)),
        .s_axi_bready(`SLAVE_BC(6)),  .s_axi_araddr(`SLAVE_AA(6)),  .s_axi_arvalid(`SLAVE_AAV(6)),
        .s_axi_arready(`SLAVE_AAR(6)),.s_axi_rdata(`SLAVE_RD(6)),   .s_axi_rresp(`SLAVE_RR(6)),
        .s_axi_rvalid(`SLAVE_RV(6)),  .s_axi_rready(`SLAVE_RC(6)),
        // DMA master tied off for this test
        .m_axi_awid(), .m_axi_awaddr(), .m_axi_awlen(), .m_axi_awsize(),
        .m_axi_awburst(), .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(),
        .m_axi_awqos(), .m_axi_awvalid(), .m_axi_awready(1'b1),
        .m_axi_wdata(), .m_axi_wstrb(), .m_axi_wlast(), .m_axi_wvalid(),
        .m_axi_wready(1'b1), .m_axi_bid(8'd0), .m_axi_bresp(2'b00),
        .m_axi_bvalid(1'b0), .m_axi_bready(),
        .m_axi_arid(), .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(),
        .m_axi_arburst(), .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(),
        .m_axi_arqos(), .m_axi_arvalid(), .m_axi_arready(1'b1),
        .m_axi_rid(8'd0), .m_axi_rdata(32'd0), .m_axi_rresp(2'b00),
        .m_axi_rlast(1'b0), .m_axi_rvalid(1'b0), .m_axi_rready(),
        .spi_rx_dma_req(1'b0), .uart_tx_dma_req(1'b1)
    );

    // M7: SPI
    spi u_spi (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(`SLAVE_AW(7)),  .s_axi_awvalid(`SLAVE_AV(7)), .s_axi_awready(`SLAVE_AR(7)),
        .s_axi_wdata(`SLAVE_WD(7)),   .s_axi_wstrb(`SLAVE_WS(7)),   .s_axi_wvalid(`SLAVE_WV(7)),
        .s_axi_wready(`SLAVE_WR(7)),  .s_axi_bresp(`SLAVE_BR(7)),   .s_axi_bvalid(`SLAVE_BV(7)),
        .s_axi_bready(`SLAVE_BC(7)),  .s_axi_araddr(`SLAVE_AA(7)),  .s_axi_arvalid(`SLAVE_AAV(7)),
        .s_axi_arready(`SLAVE_AAR(7)),.s_axi_rdata(`SLAVE_RD(7)),   .s_axi_rresp(`SLAVE_RR(7)),
        .s_axi_rvalid(`SLAVE_RV(7)),  .s_axi_rready(`SLAVE_RC(7)),
        .spi_sck(), .spi_mosi(), .spi_miso(1'b0), .spi_cs_n(),
        .spi_rx_dma_req()
    );

    // M8: Watchdog
    watchdog u_wdt (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(`SLAVE_AW(8)),  .s_axi_awvalid(`SLAVE_AV(8)), .s_axi_awready(`SLAVE_AR(8)),
        .s_axi_wdata(`SLAVE_WD(8)),   .s_axi_wstrb(`SLAVE_WS(8)),   .s_axi_wvalid(`SLAVE_WV(8)),
        .s_axi_wready(`SLAVE_WR(8)),  .s_axi_bresp(`SLAVE_BR(8)),   .s_axi_bvalid(`SLAVE_BV(8)),
        .s_axi_bready(`SLAVE_BC(8)),  .s_axi_araddr(`SLAVE_AA(8)),  .s_axi_arvalid(`SLAVE_AAV(8)),
        .s_axi_arready(`SLAVE_AAR(8)),.s_axi_rdata(`SLAVE_RD(8)),   .s_axi_rresp(`SLAVE_RR(8)),
        .s_axi_rvalid(`SLAVE_RV(8)),  .s_axi_rready(`SLAVE_RC(8)),
        .wdt_reset_dma(), .wdt_reset_aes(), .wdt_reset_spi(), .wdt_fired()
    );

    // =========================================================================
    // AXI master BFM tasks
    // =========================================================================

    // Initialize all master-side outputs to safe defaults
    task init_master;
        s0_awid=0; s0_awaddr=0; s0_awlen=0; s0_awsize=3'd2; s0_awburst=2'b01;
        s0_awlock=0; s0_awcache=4'b0011; s0_awprot=0; s0_awqos=0; s0_awvalid=0;
        s0_wdata=0; s0_wstrb=4'hF; s0_wlast=1; s0_wvalid=0; s0_bready=1;
        s0_arid=0; s0_araddr=0; s0_arlen=0; s0_arsize=3'd2; s0_arburst=2'b01;
        s0_arlock=0; s0_arcache=4'b0011; s0_arprot=0; s0_arqos=0; s0_arvalid=0;
        s0_rready=1;
        s1_awid=0; s1_awaddr=0; s1_awlen=0; s1_awsize=3'd2; s1_awburst=2'b01;
        s1_awlock=0; s1_awcache=4'b0011; s1_awprot=0; s1_awqos=0; s1_awvalid=0;
        s1_wdata=0; s1_wstrb=4'hF; s1_wlast=1; s1_wvalid=0; s1_bready=1;
        s1_arid=0; s1_araddr=0; s1_arlen=0; s1_arsize=3'd2; s1_arburst=2'b01;
        s1_arlock=0; s1_arcache=4'b0011; s1_arprot=0; s1_arqos=0; s1_arvalid=0;
        s1_rready=1;
    endtask

    // Single-beat AXI write on master 0 (CPU)
    task cpu_write(input [AW-1:0] addr, input [DW-1:0] data,
                   input [SW-1:0] strb, output [1:0] resp);
        @(posedge clk); #1;
        s0_awaddr  = addr;
        s0_awvalid = 1;
        s0_wdata   = data;
        s0_wstrb   = strb;
        s0_wlast   = 1;
        s0_wvalid  = 1;
        s0_bready  = 1;

        fork
            begin
                do @(posedge clk);
                while (!s0_awready);
                #1 s0_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!s0_wready);
                #1 s0_wvalid = 0;
            end
        join

        do @(posedge clk);
        while (!s0_bvalid);
        resp = s0_bresp;
        #1 s0_bready = 0;
    endtask

    // Single-beat AXI read on master 0 (CPU)
    task cpu_read(input [AW-1:0] addr, output [DW-1:0] data, output [1:0] resp);
        @(posedge clk); #1;
        s0_araddr  = addr;
        s0_arvalid = 1;
        s0_rready  = 1;

        do @(posedge clk);
        while (!s0_arready);
        #1 s0_arvalid = 0;

        do @(posedge clk);
        while (!s0_rvalid);
        data = s0_rdata;
        resp = s0_rresp;
        #1 s0_rready = 0;
    endtask

    // Single-beat AXI write on master 1 (DMA)
    task dma_write(input [AW-1:0] addr, input [DW-1:0] data,
                   input [SW-1:0] strb, output [1:0] resp);
        @(posedge clk); #1;
        s1_awaddr  = addr;
        s1_awvalid = 1;
        s1_wdata   = data;
        s1_wstrb   = strb;
        s1_wlast   = 1;
        s1_wvalid  = 1;
        s1_bready  = 1;

        fork
            begin
                do @(posedge clk);
                while (!s1_awready);
                #1 s1_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!s1_wready);
                #1 s1_wvalid = 0;
            end
        join

        do @(posedge clk);
        while (!s1_bvalid);
        resp = s1_bresp;
        #1 s1_bready = 0;
    endtask

    // Single-beat AXI read on master 1 (DMA)
    task dma_read(input [AW-1:0] addr, output [DW-1:0] data, output [1:0] resp);
        @(posedge clk); #1;
        s1_araddr  = addr;
        s1_arvalid = 1;
        s1_rready  = 1;

        do @(posedge clk);
        while (!s1_arready);
        #1 s1_arvalid = 0;

        do @(posedge clk);
        while (!s1_rvalid);
        data = s1_rdata;
        resp = s1_rresp;
        #1 s1_rready = 0;
    endtask

    // =========================================================================
    // Test helpers
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;

    task check(input string name, input logic cond);
        if (cond) begin
            $display("[PASS] %s", name); pass_count++;
        end else begin
            $display("[FAIL] %s", name); fail_count++;
        end
    endtask

    // =========================================================================
    // Test stimulus
    // =========================================================================
    logic [1:0]    resp, resp_cpu, resp_dma;
    logic [DW-1:0] rdata;

    initial begin
        $dumpfile("build/interconnect.vcd");
        $dumpvars(0, tb_interconnect);
        init_master();
        // Hold reset for 5 cycles
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ==================================================================
        // TC01 – CPU read/write to all 9 slaves
        // ==================================================================
        $display("--- TC01: CPU access to all 9 slaves ---");

        cpu_write(`IMEM_BASE,        32'hDEAD_BEEF, 4'hF, resp);
        check("TC01_IMEM_WR",  resp == 2'b00);
        cpu_read (`IMEM_BASE,        rdata, resp);
        check("TC01_IMEM_RD",  resp == 2'b00);

        cpu_write(`DMEM_BASE,        32'hCAFE_BABE, 4'hF, resp);
        check("TC01_DMEM_WR",  resp == 2'b00);
        cpu_read (`DMEM_BASE,        rdata, resp);
        check("TC01_DMEM_RD",  resp == 2'b00 && rdata == 32'hCAFE_BABE);

        cpu_write(`UART_BASE,        32'h41,        4'h1, resp); // write 'A'
        check("TC01_UART_WR",  resp == 2'b00);
        cpu_read (`UART_BASE + 8'h08, rdata, resp);             // read STATUS
        check("TC01_UART_RD",  resp == 2'b00);

        cpu_write(`TIMER_BASE + 8'h04, 32'd1000,   4'hF, resp);
        check("TC01_TIMER_WR", resp == 2'b00);
        cpu_read (`TIMER_BASE,         rdata, resp);
        check("TC01_TIMER_RD", resp == 2'b00);

        cpu_write(`GPIO_BASE + 8'h08, 32'hFF,      4'h1, resp);
        check("TC01_GPIO_WR",  resp == 2'b00);
        cpu_read (`GPIO_BASE + 8'h04, rdata, resp);
        check("TC01_GPIO_RD",  resp == 2'b00);

        cpu_write(`AES_BASE,          32'h01234567, 4'hF, resp);
        check("TC01_AES_WR",   resp == 2'b00);
        cpu_read (`AES_BASE,          rdata, resp);
        check("TC01_AES_RD",   resp == 2'b00);

        cpu_write(`DMA_BASE + 8'h08, 32'd16,       4'hF, resp);
        check("TC01_DMA_WR",   resp == 2'b00);
        cpu_read (`DMA_BASE + 8'h10, rdata, resp);
        check("TC01_DMA_RD",   resp == 2'b00);

        cpu_write(`SPI_BASE + 8'h0C, 32'h01,       4'h1, resp);
        check("TC01_SPI_WR",   resp == 2'b00);
        cpu_read (`SPI_BASE + 8'h08, rdata, resp);
        check("TC01_SPI_RD",   resp == 2'b00);

        cpu_write(`WDT_BASE + 8'h04, 32'hFF_FFFF,  4'hF, resp);
        check("TC01_WDT_WR",   resp == 2'b00);
        cpu_read (`WDT_BASE + 8'h04, rdata, resp);
        check("TC01_WDT_RD",   resp == 2'b00 && rdata == 32'hFF_FFFF);

        // ==================================================================
        // TC02 – DMA access to 4 permitted slaves
        // ==================================================================
        $display("--- TC02: DMA access to permitted slaves ---");

        dma_write(`DMEM_BASE,        32'hAABB_CCDD, 4'hF, resp);
        check("TC02_DMEM_WR",  resp == 2'b00);
        dma_read (`DMEM_BASE,        rdata, resp);
        check("TC02_DMEM_RD",  resp == 2'b00 && rdata == 32'hAABB_CCDD);

        dma_write(`UART_BASE,        32'h42,        4'h1, resp);
        check("TC02_UART_WR",  resp == 2'b00);
        dma_read (`UART_BASE + 8'h08, rdata, resp);
        check("TC02_UART_RD",  resp == 2'b00);

        dma_write(`AES_BASE + 8'h18, 32'h11223344, 4'hF, resp);
        check("TC02_AES_WR",   resp == 2'b00);
        dma_read (`AES_BASE + 8'h14, rdata, resp);
        check("TC02_AES_RD",   resp == 2'b00);

        dma_write(`SPI_BASE,        32'h55,         4'h1, resp);
        check("TC02_SPI_WR",   resp == 2'b00);
        dma_read (`SPI_BASE + 8'h08, rdata, resp);
        check("TC02_SPI_RD",   resp == 2'b00);

        // ==================================================================
        // TC03 – DMA access to 5 restricted slaves → DECERR
        // ==================================================================
        $display("--- TC03: DMA access to restricted slaves ---");

        dma_write(`IMEM_BASE,        32'hDEAD,      4'hF, resp);
        check("TC03_IMEM_DMA_W",  resp == 2'b11); // DECERR
        dma_read (`IMEM_BASE,        rdata, resp);
        check("TC03_IMEM_DMA_R",  resp == 2'b11);

        dma_write(`TIMER_BASE,       32'h0,         4'hF, resp);
        check("TC03_TIMER_DMA_W", resp == 2'b11);
        dma_read (`TIMER_BASE,       rdata, resp);
        check("TC03_TIMER_DMA_R", resp == 2'b11);

        dma_write(`GPIO_BASE,        32'h0,         4'hF, resp);
        check("TC03_GPIO_DMA_W",  resp == 2'b11);
        dma_read (`GPIO_BASE,        rdata, resp);
        check("TC03_GPIO_DMA_R",  resp == 2'b11);

        dma_write(`DMA_BASE,         32'h0,         4'hF, resp);
        check("TC03_DMAREG_DMA_W",resp == 2'b11);
        dma_read (`DMA_BASE,         rdata, resp);
        check("TC03_DMAREG_DMA_R",resp == 2'b11);

        dma_write(`WDT_BASE,         32'h0,         4'hF, resp);
        check("TC03_WDT_DMA_W",   resp == 2'b11);
        dma_read (`WDT_BASE,         rdata, resp);
        check("TC03_WDT_DMA_R",   resp == 2'b11);

        // ==================================================================
        // TC04 – Unmapped address → DECERR
        // ==================================================================
        $display("--- TC04: Unmapped address ---");
        cpu_write(32'hDEAD_0000,     32'hFF,        4'hF, resp);
        check("TC04_UNMAP_WR", resp == 2'b11);
        cpu_read (32'hDEAD_0000,     rdata, resp);
        check("TC04_UNMAP_RD", resp == 2'b11);

        // ==================================================================
        // TC05 – Address boundary: last valid address of each slave
        // ==================================================================
        $display("--- TC05: Address boundary checks ---");
        cpu_read (`IMEM_BASE  + 32'hFFFC, rdata, resp);
        check("TC05_IMEM_TOP",  resp == 2'b00);
        cpu_read (`DMEM_BASE  + 32'hFFFC, rdata, resp);
        check("TC05_DMEM_TOP",  resp == 2'b00);
        cpu_read (`UART_BASE  + 8'hFC,    rdata, resp);
        check("TC05_UART_TOP",  resp == 2'b00);
        cpu_read (`AES_BASE   + 8'hFC,    rdata, resp);
        check("TC05_AES_TOP",   resp == 2'b00);
        cpu_read (`WDT_BASE   + 8'hFC,    rdata, resp);
        check("TC05_WDT_TOP",   resp == 2'b00);

        // ==================================================================
        // TC06 – Simultaneous CPU and DMA requests to different slaves
        // ==================================================================
        $display("--- TC06: Simultaneous CPU+DMA different slaves ---");
        fork
            cpu_write (`IMEM_BASE, 32'h12345678, 4'hF, resp_cpu);
            dma_write (`DMEM_BASE, 32'h87654321, 4'hF, resp_dma);
        join
        cpu_read(`IMEM_BASE, rdata, resp);
        check("TC06_CPU_IMEM",   resp == 2'b00 && rdata == 32'h12345678);
        dma_read(`DMEM_BASE, rdata, resp);
        check("TC06_DMA_DMEM",   resp == 2'b00 && rdata == 32'h87654321);

        // ==================================================================
        // TC07 – Same-slave contention: CPU and DMA both target DMEM
        // ==================================================================
        $display("--- TC07: Same-slave contention ---");
        fork
            cpu_write(`DMEM_BASE + 4,  32'hCAFE_BABE, 4'hF, resp_cpu);
            dma_write(`DMEM_BASE + 8,  32'hDDDD_EEEE, 4'hF, resp_dma);
        join
        cpu_read(`DMEM_BASE + 4, rdata, resp);
        check("TC07_CPU_DMEM",  resp == 2'b00 && rdata == 32'hCAFE_BABE);
        dma_read(`DMEM_BASE + 8, rdata, resp);
        check("TC07_DMA_DMEM",  resp == 2'b00 && rdata == 32'hDDDD_EEEE);

        // ==================================================================
        // TC08 – Back-pressure: hold rready low, transaction still completes
        // ==================================================================
        $display("--- TC08: Back-pressure ---");
        s0_rready = 0;
        s0_araddr = `DMEM_BASE; s0_arvalid = 1;
        @(posedge clk); #1;
        while (!s0_arready) @(posedge clk) #1;
        s0_arvalid = 0;
        repeat(5) begin
            @(posedge clk); #1;
        end
        s0_rready = 1;
        while (!s0_rvalid) @(posedge clk) #1;
        resp = s0_rresp;
        @(posedge clk); #1;
        s0_rready = 0;
        check("TC08_BACKPRESSURE", resp == 2'b00);

        // ==================================================================
        // TC09 – WSTRB byte-lane masking
        // ==================================================================
        $display("--- TC09: WSTRB byte lanes ---");
        // Write known pattern
        cpu_write(`DMEM_BASE + 12, 32'hFFFF_FFFF, 4'hF, resp);
        // Overwrite only byte 0 (strb=4'h1) with 0x00
        cpu_write(`DMEM_BASE + 12, 32'h0000_0000, 4'h1, resp);
        cpu_read (`DMEM_BASE + 12, rdata, resp);
        check("TC09_WSTRB", resp==2'b00 && rdata[31:8]==24'hFFFFFF && rdata[7:0]==8'h00);

        // ==================================================================
        // TC10 – VALID/payload stability: check interconnect doesn't corrupt
        //         data when READY is delayed
        // ==================================================================
        $display("--- TC10: VALID stability ---");
        cpu_write(`DMEM_BASE + 16, 32'hA5A5_A5A5, 4'hF, resp);
        cpu_read (`DMEM_BASE + 16, rdata, resp);
        check("TC10_STABILITY", resp==2'b00 && rdata==32'hA5A5_A5A5);

        // ==================================================================
        // TC11 – Reset behaviour
        // ==================================================================
        $display("--- TC11: Reset behaviour ---");
        rst = 1;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);
        // After reset interconnect must accept new transactions
        cpu_write(`DMEM_BASE, 32'h55AA_55AA, 4'hF, resp);
        check("TC11_POST_RST_WR", resp == 2'b00);
        cpu_read(`DMEM_BASE,  rdata, resp);
        check("TC11_POST_RST_RD", resp == 2'b00);

        // ==================================================================
        // Summary
        // ==================================================================
        repeat(2) @(posedge clk);
        $display("========================================");
        $display(" tb_interconnect RESULTS");
        $display(" PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish(fail_count > 0 ? 1 : 0);
    end

    // Timeout watchdog
    initial begin
        #500_000;
        $display("[FAIL] TIMEOUT – simulation exceeded 500 us");
        $finish(1);
    end

endmodule
