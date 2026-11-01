// =============================================================================
// soc_top.v  –  Secure Communication Gateway SoC – Top-Level Integration
//
// Instantiates and interconnects all SoC subsystems:
//
//   Masters (AXI4):
//     S0 – RISC-V CPU (cpu_axi_master)
//     S1 – DMA Controller (dma)
//
//   Slaves (AXI4-Lite, addressed via soc_axi_interconnect_wrap_2x9):
//     M0 – Instruction Memory  (0x0000_0000, 64 KB)
//     M1 – Data Memory         (0x0001_0000, 64 KB)
//     M2 – UART                (0x1000_0000, 256 B)
//     M3 – Timer               (0x1000_0100, 256 B)
//     M4 – GPIO                (0x1000_0200, 256 B)
//     M5 – AES Engine          (0x1000_0300, 256 B)
//     M6 – DMA Config Regs     (0x1000_0400, 256 B)
//     M7 – SPI Controller      (0x1000_0500, 256 B)
//     M8 – Watchdog Timer      (0x1000_0600, 256 B)
//
//   Sideband / scoped reset:
//     Watchdog fires → wdt_reset_dma/aes/spi → resets DMA/AES/SPI datapaths
//     spi_rx_dma_req → DMA trigger for MODE 0
//     uart_tx_dma_req → DMA back-pressure for MODE 1
//
// AXI parameter conventions:
//   DATA_WIDTH = 32, ADDR_WIDTH = 32, STRB_WIDTH = 4, ID_WIDTH = 8
//
// All AXI slaves in this SoC are AXI4-Lite and do not use AxID, AxLEN,
// AxSIZE, AxBURST, AxLOCK, AxCACHE, AxPROT, AxQOS, AxREGION.
// Those signals are driven from the interconnect M-side but slaves ignore
// everything except VALID/READY/ADDR/DATA/STRB/RESP.
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "soc_defines.vh"

module soc_top #(
    parameter CLK_FREQ_HZ  = 50_000_000,
    parameter BAUD_RATE    = 115_200,
    // CPU reset vector (start of instruction memory)
    parameter RESET_VECTOR = 32'h0000_0000,
    parameter IMEM_HEX     = ""
) (
    input  wire        clk,
    input  wire        rst_n,     // Active-low external reset

    // GPIO pads
    input  wire [7:0]  gpio_in,
    output wire [7:0]  gpio_out,
    output wire [7:0]  gpio_oe,

    // UART physical
    output wire        uart_tx,
    input  wire        uart_rx,   // stub – not connected to UART internals

    // SPI physical
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    // External interrupt / status
    output wire        gpio_irq,
    output wire        timer_irq,
    output wire        wdt_fired,

    // Debug
    output wire [31:0] dbg_pc
);

    // =========================================================================
    // Active-high synchronous reset (internal)
    // =========================================================================
    reg  rst_sync_ff1, rst_sync_ff2;
    always @(posedge clk) begin
        rst_sync_ff1 <= ~rst_n;
        rst_sync_ff2 <= rst_sync_ff1;
    end
    wire rst = rst_sync_ff2;

    // =========================================================================
    // Watchdog scoped reset sideband
    // =========================================================================
    wire wdt_reset_dma;
    wire wdt_reset_aes;
    wire wdt_reset_spi;

    // =========================================================================
    // SPI ↔ DMA sideband
    // =========================================================================
    wire spi_rx_dma_req;
    wire uart_tx_dma_req;

    // =========================================================================
    // Baud divider (compile-time)
    // =========================================================================
    localparam BAUD_DIV = CLK_FREQ_HZ / BAUD_RATE;

    // =========================================================================
    // Interconnect packed buses
    //
    // Convention: signal[n*W +: W] = port for slave/master index n
    // S-side: index 0 = CPU, index 1 = DMA
    // M-side: index 0..8 per soc_defines.vh M_xxx constants
    // =========================================================================

    // ---- S-side (master → interconnect) ------------------------------------
    wire [2*`AXI_ID_WIDTH-1:0]   s_axi_awid,    s_axi_arid,
                                  s_axi_bid,      s_axi_rid;
    wire [2*`AXI_ADDR_WIDTH-1:0] s_axi_awaddr,   s_axi_araddr;
    wire [2*8-1:0]               s_axi_awlen,    s_axi_arlen;
    wire [2*3-1:0]               s_axi_awsize,   s_axi_arsize;
    wire [2*2-1:0]               s_axi_awburst,  s_axi_arburst;
    wire [2-1:0]                 s_axi_awlock,   s_axi_arlock;
    wire [2*4-1:0]               s_axi_awcache,  s_axi_arcache;
    wire [2*3-1:0]               s_axi_awprot,   s_axi_arprot;
    wire [2*4-1:0]               s_axi_awqos,    s_axi_arqos;
    wire [2-1:0]                 s_axi_awvalid,  s_axi_awready;
    wire [2*`AXI_DATA_WIDTH-1:0] s_axi_wdata,    s_axi_rdata;
    wire [2*`AXI_STRB_WIDTH-1:0] s_axi_wstrb;
    wire [2-1:0]                 s_axi_wlast,    s_axi_wvalid, s_axi_wready;
    wire [2*2-1:0]               s_axi_bresp,    s_axi_rresp;
    wire [2-1:0]                 s_axi_bvalid,   s_axi_bready;
    wire [2-1:0]                 s_axi_arvalid,  s_axi_arready;
    wire [2-1:0]                 s_axi_rlast,    s_axi_rvalid, s_axi_rready;

    // ---- M-side (interconnect → slave) -------------------------------------
    wire [9*`AXI_ID_WIDTH-1:0]   m_axi_awid,    m_axi_arid,
                                  m_axi_bid,      m_axi_rid;
    wire [9*`AXI_ADDR_WIDTH-1:0] m_axi_awaddr,   m_axi_araddr;
    wire [9*8-1:0]               m_axi_awlen,    m_axi_arlen;
    wire [9*3-1:0]               m_axi_awsize,   m_axi_arsize;
    wire [9*2-1:0]               m_axi_awburst,  m_axi_arburst;
    wire [9-1:0]                 m_axi_awlock,   m_axi_arlock;
    wire [9*4-1:0]               m_axi_awcache,  m_axi_arcache;
    wire [9*3-1:0]               m_axi_awprot,   m_axi_arprot;
    wire [9*4-1:0]               m_axi_awqos,    m_axi_arqos;
    wire [9*4-1:0]               m_axi_awregion, m_axi_arregion;
    wire [9-1:0]                 m_axi_awvalid,  m_axi_awready;
    wire [9*`AXI_DATA_WIDTH-1:0] m_axi_wdata,    m_axi_rdata;
    wire [9*`AXI_STRB_WIDTH-1:0] m_axi_wstrb;
    wire [9-1:0]                 m_axi_wlast,    m_axi_wvalid, m_axi_wready;
    wire [9*2-1:0]               m_axi_bresp,    m_axi_rresp;
    wire [9-1:0]                 m_axi_bvalid,   m_axi_bready;
    wire [9-1:0]                 m_axi_arvalid,  m_axi_arready;
    wire [9-1:0]                 m_axi_rlast,    m_axi_rvalid, m_axi_rready;

    // Single-beat slaves assert RLAST whenever RVALID is asserted
    assign m_axi_rlast = m_axi_rvalid;

    // =========================================================================
    // Slave index helper macros (not Verilog macros; use localparam offsets)
    // M0=IMEM, M1=DMEM, M2=UART, M3=TIMER, M4=GPIO, M5=AES,
    // M6=DMA, M7=SPI, M8=WDT
    // =========================================================================
    localparam M_IMEM  = 0;
    localparam M_DMEM  = 1;
    localparam M_UART  = 2;
    localparam M_TIMER = 3;
    localparam M_GPIO  = 4;
    localparam M_AES   = 5;
    localparam M_DMA   = 6;
    localparam M_SPI   = 7;
    localparam M_WDT   = 8;

    // Master index helpers
    localparam S_CPU   = 0;
    localparam S_DMA   = 1;

    // =========================================================================
    // AXI Interconnect  (2 masters × 9 slaves)
    // =========================================================================
    soc_axi_interconnect_wrap_2x9 u_interconnect (
        .clk             (clk),
        .rst             (rst),
        // S-side
        .s_axi_awid      (s_axi_awid),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awlock    (s_axi_awlock),
        .s_axi_awcache   (s_axi_awcache),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awqos     (s_axi_awqos),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bid       (s_axi_bid),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arlock    (s_axi_arlock),
        .s_axi_arcache   (s_axi_arcache),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arqos     (s_axi_arqos),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rid       (s_axi_rid),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rlast     (s_axi_rlast),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        // M-side
        .m_axi_awid      (m_axi_awid),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awlock    (m_axi_awlock),
        .m_axi_awcache   (m_axi_awcache),
        .m_axi_awprot    (m_axi_awprot),
        .m_axi_awqos     (m_axi_awqos),
        .m_axi_awregion  (m_axi_awregion),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_bid       (m_axi_bid),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),
        .m_axi_arid      (m_axi_arid),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arlock    (m_axi_arlock),
        .m_axi_arcache   (m_axi_arcache),
        .m_axi_arprot    (m_axi_arprot),
        .m_axi_arqos     (m_axi_arqos),
        .m_axi_arregion  (m_axi_arregion),
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_rid       (m_axi_rid),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready)
    );

    // =========================================================================
    // CPU (S0 master)
    // =========================================================================
    cpu_axi_master #(
        .RESET_VECTOR (RESET_VECTOR)
    ) u_cpu (
        .clk            (clk),
        .rst            (rst),
        // AXI4 master
        .m_axi_awid     (s_axi_awid    [`AXI_ID_WIDTH*S_CPU   +: `AXI_ID_WIDTH]),
        .m_axi_awaddr   (s_axi_awaddr  [`AXI_ADDR_WIDTH*S_CPU +: `AXI_ADDR_WIDTH]),
        .m_axi_awlen    (s_axi_awlen   [8*S_CPU                +: 8]),
        .m_axi_awsize   (s_axi_awsize  [3*S_CPU                +: 3]),
        .m_axi_awburst  (s_axi_awburst [2*S_CPU                +: 2]),
        .m_axi_awlock   (s_axi_awlock  [S_CPU]),
        .m_axi_awcache  (s_axi_awcache [4*S_CPU                +: 4]),
        .m_axi_awprot   (s_axi_awprot  [3*S_CPU                +: 3]),
        .m_axi_awqos    (s_axi_awqos   [4*S_CPU                +: 4]),
        .m_axi_awvalid  (s_axi_awvalid [S_CPU]),
        .m_axi_awready  (s_axi_awready [S_CPU]),
        .m_axi_wdata    (s_axi_wdata   [`AXI_DATA_WIDTH*S_CPU  +: `AXI_DATA_WIDTH]),
        .m_axi_wstrb    (s_axi_wstrb   [`AXI_STRB_WIDTH*S_CPU  +: `AXI_STRB_WIDTH]),
        .m_axi_wlast    (s_axi_wlast   [S_CPU]),
        .m_axi_wvalid   (s_axi_wvalid  [S_CPU]),
        .m_axi_wready   (s_axi_wready  [S_CPU]),
        .m_axi_bid      (s_axi_bid     [`AXI_ID_WIDTH*S_CPU    +: `AXI_ID_WIDTH]),
        .m_axi_bresp    (s_axi_bresp   [2*S_CPU                +: 2]),
        .m_axi_bvalid   (s_axi_bvalid  [S_CPU]),
        .m_axi_bready   (s_axi_bready  [S_CPU]),
        .m_axi_arid     (s_axi_arid    [`AXI_ID_WIDTH*S_CPU    +: `AXI_ID_WIDTH]),
        .m_axi_araddr   (s_axi_araddr  [`AXI_ADDR_WIDTH*S_CPU  +: `AXI_ADDR_WIDTH]),
        .m_axi_arlen    (s_axi_arlen   [8*S_CPU                +: 8]),
        .m_axi_arsize   (s_axi_arsize  [3*S_CPU                +: 3]),
        .m_axi_arburst  (s_axi_arburst [2*S_CPU                +: 2]),
        .m_axi_arlock   (s_axi_arlock  [S_CPU]),
        .m_axi_arcache  (s_axi_arcache [4*S_CPU                +: 4]),
        .m_axi_arprot   (s_axi_arprot  [3*S_CPU                +: 3]),
        .m_axi_arqos    (s_axi_arqos   [4*S_CPU                +: 4]),
        .m_axi_arvalid  (s_axi_arvalid [S_CPU]),
        .m_axi_arready  (s_axi_arready [S_CPU]),
        .m_axi_rid      (s_axi_rid     [`AXI_ID_WIDTH*S_CPU    +: `AXI_ID_WIDTH]),
        .m_axi_rdata    (s_axi_rdata   [`AXI_DATA_WIDTH*S_CPU  +: `AXI_DATA_WIDTH]),
        .m_axi_rresp    (s_axi_rresp   [2*S_CPU                +: 2]),
        .m_axi_rlast    (s_axi_rlast   [S_CPU]),
        .m_axi_rvalid   (s_axi_rvalid  [S_CPU]),
        .m_axi_rready   (s_axi_rready  [S_CPU]),
        .halt           (1'b0),
        .dbg_pc         (dbg_pc)
    );

    // =========================================================================
    // DMA Controller (S1 master + M6 slave config)
    // =========================================================================
    dma u_dma (
        .clk            (clk),
        .rst            (rst),
        .wdt_rst        (wdt_reset_dma),
        // AXI4-Lite slave (config – from interconnect M6)
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_DMA  +: `AXI_ADDR_WIDTH]),
        .s_axi_awvalid  (m_axi_awvalid [M_DMA]),
        .s_axi_awready  (m_axi_awready [M_DMA]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_DMA  +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_DMA  +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_DMA]),
        .s_axi_wready   (m_axi_wready  [M_DMA]),
        .s_axi_bresp    (m_axi_bresp   [2*M_DMA                +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_DMA]),
        .s_axi_bready   (m_axi_bready  [M_DMA]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_DMA  +: `AXI_ADDR_WIDTH]),
        .s_axi_arvalid  (m_axi_arvalid [M_DMA]),
        .s_axi_arready  (m_axi_arready [M_DMA]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_DMA  +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_DMA                +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_DMA]),
        .s_axi_rready   (m_axi_rready  [M_DMA]),
        // AXI4 master (data – to interconnect S1)
        .m_axi_awid     (s_axi_awid    [`AXI_ID_WIDTH*S_DMA    +: `AXI_ID_WIDTH]),
        .m_axi_awaddr   (s_axi_awaddr  [`AXI_ADDR_WIDTH*S_DMA  +: `AXI_ADDR_WIDTH]),
        .m_axi_awlen    (s_axi_awlen   [8*S_DMA                +: 8]),
        .m_axi_awsize   (s_axi_awsize  [3*S_DMA                +: 3]),
        .m_axi_awburst  (s_axi_awburst [2*S_DMA                +: 2]),
        .m_axi_awlock   (s_axi_awlock  [S_DMA]),
        .m_axi_awcache  (s_axi_awcache [4*S_DMA                +: 4]),
        .m_axi_awprot   (s_axi_awprot  [3*S_DMA                +: 3]),
        .m_axi_awqos    (s_axi_awqos   [4*S_DMA                +: 4]),
        .m_axi_awvalid  (s_axi_awvalid [S_DMA]),
        .m_axi_awready  (s_axi_awready [S_DMA]),
        .m_axi_wdata    (s_axi_wdata   [`AXI_DATA_WIDTH*S_DMA  +: `AXI_DATA_WIDTH]),
        .m_axi_wstrb    (s_axi_wstrb   [`AXI_STRB_WIDTH*S_DMA  +: `AXI_STRB_WIDTH]),
        .m_axi_wlast    (s_axi_wlast   [S_DMA]),
        .m_axi_wvalid   (s_axi_wvalid  [S_DMA]),
        .m_axi_wready   (s_axi_wready  [S_DMA]),
        .m_axi_bid      (s_axi_bid     [`AXI_ID_WIDTH*S_DMA    +: `AXI_ID_WIDTH]),
        .m_axi_bresp    (s_axi_bresp   [2*S_DMA                +: 2]),
        .m_axi_bvalid   (s_axi_bvalid  [S_DMA]),
        .m_axi_bready   (s_axi_bready  [S_DMA]),
        .m_axi_arid     (s_axi_arid    [`AXI_ID_WIDTH*S_DMA    +: `AXI_ID_WIDTH]),
        .m_axi_araddr   (s_axi_araddr  [`AXI_ADDR_WIDTH*S_DMA  +: `AXI_ADDR_WIDTH]),
        .m_axi_arlen    (s_axi_arlen   [8*S_DMA                +: 8]),
        .m_axi_arsize   (s_axi_arsize  [3*S_DMA                +: 3]),
        .m_axi_arburst  (s_axi_arburst [2*S_DMA                +: 2]),
        .m_axi_arlock   (s_axi_arlock  [S_DMA]),
        .m_axi_arcache  (s_axi_arcache [4*S_DMA                +: 4]),
        .m_axi_arprot   (s_axi_arprot  [3*S_DMA                +: 3]),
        .m_axi_arqos    (s_axi_arqos   [4*S_DMA                +: 4]),
        .m_axi_arvalid  (s_axi_arvalid [S_DMA]),
        .m_axi_arready  (s_axi_arready [S_DMA]),
        .m_axi_rid      (s_axi_rid     [`AXI_ID_WIDTH*S_DMA    +: `AXI_ID_WIDTH]),
        .m_axi_rdata    (s_axi_rdata   [`AXI_DATA_WIDTH*S_DMA  +: `AXI_DATA_WIDTH]),
        .m_axi_rresp    (s_axi_rresp   [2*S_DMA                +: 2]),
        .m_axi_rlast    (s_axi_rlast   [S_DMA]),
        .m_axi_rvalid   (s_axi_rvalid  [S_DMA]),
        .m_axi_rready   (s_axi_rready  [S_DMA]),
        // Sideband
        .spi_rx_dma_req  (spi_rx_dma_req),
        .uart_tx_dma_req (uart_tx_dma_req)
    );

    // =========================================================================
    // Instruction Memory (M0)
    // =========================================================================
    instruction_memory #(
        .HEX_FILE       (IMEM_HEX)
    ) u_imem (
        .clk            (clk),
        .rst            (rst),
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_IMEM  +: `AXI_ADDR_WIDTH]),
        .s_axi_awprot   (m_axi_awprot  [3*M_IMEM                 +: 3]),
        .s_axi_awvalid  (m_axi_awvalid [M_IMEM]),
        .s_axi_awready  (m_axi_awready [M_IMEM]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_IMEM   +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_IMEM   +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_IMEM]),
        .s_axi_wready   (m_axi_wready  [M_IMEM]),
        .s_axi_bresp    (m_axi_bresp   [2*M_IMEM                  +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_IMEM]),
        .s_axi_bready   (m_axi_bready  [M_IMEM]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_IMEM   +: `AXI_ADDR_WIDTH]),
        .s_axi_arprot   (m_axi_arprot  [3*M_IMEM                  +: 3]),
        .s_axi_arvalid  (m_axi_arvalid [M_IMEM]),
        .s_axi_arready  (m_axi_arready [M_IMEM]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_IMEM   +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_IMEM                  +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_IMEM]),
        .s_axi_rready   (m_axi_rready  [M_IMEM])
    );

    // =========================================================================
    // Data Memory (M1)
    // =========================================================================
    data_memory u_dmem (
        .clk            (clk),
        .rst            (rst),
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_DMEM   +: `AXI_ADDR_WIDTH]),
        .s_axi_awprot   (m_axi_awprot  [3*M_DMEM                  +: 3]),
        .s_axi_awvalid  (m_axi_awvalid [M_DMEM]),
        .s_axi_awready  (m_axi_awready [M_DMEM]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_DMEM    +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_DMEM    +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_DMEM]),
        .s_axi_wready   (m_axi_wready  [M_DMEM]),
        .s_axi_bresp    (m_axi_bresp   [2*M_DMEM                   +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_DMEM]),
        .s_axi_bready   (m_axi_bready  [M_DMEM]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_DMEM    +: `AXI_ADDR_WIDTH]),
        .s_axi_arprot   (m_axi_arprot  [3*M_DMEM                   +: 3]),
        .s_axi_arvalid  (m_axi_arvalid [M_DMEM]),
        .s_axi_arready  (m_axi_arready [M_DMEM]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_DMEM    +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_DMEM                   +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_DMEM]),
        .s_axi_rready   (m_axi_rready  [M_DMEM])
    );

    // =========================================================================
    // UART (M2)
    // =========================================================================
    uart #(
        .DEFAULT_BAUD (BAUD_DIV[15:0])
    ) u_uart (
        .clk            (clk),
        .rst            (rst),
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_UART   +: `AXI_ADDR_WIDTH]),
        .s_axi_awvalid  (m_axi_awvalid [M_UART]),
        .s_axi_awready  (m_axi_awready [M_UART]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_UART    +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_UART    +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_UART]),
        .s_axi_wready   (m_axi_wready  [M_UART]),
        .s_axi_bresp    (m_axi_bresp   [2*M_UART                   +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_UART]),
        .s_axi_bready   (m_axi_bready  [M_UART]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_UART    +: `AXI_ADDR_WIDTH]),
        .s_axi_arvalid  (m_axi_arvalid [M_UART]),
        .s_axi_arready  (m_axi_arready [M_UART]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_UART    +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_UART                   +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_UART]),
        .s_axi_rready   (m_axi_rready  [M_UART]),
        .uart_tx        (uart_tx),
        .uart_tx_dma_req(uart_tx_dma_req)
    );

    // =========================================================================
    // Timer (M3)
    // =========================================================================
    timer u_timer (
        .clk            (clk),
        .rst            (rst),
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_TIMER   +: `AXI_ADDR_WIDTH]),
        .s_axi_awvalid  (m_axi_awvalid [M_TIMER]),
        .s_axi_awready  (m_axi_awready [M_TIMER]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_TIMER    +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_TIMER    +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_TIMER]),
        .s_axi_wready   (m_axi_wready  [M_TIMER]),
        .s_axi_bresp    (m_axi_bresp   [2*M_TIMER                   +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_TIMER]),
        .s_axi_bready   (m_axi_bready  [M_TIMER]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_TIMER    +: `AXI_ADDR_WIDTH]),
        .s_axi_arvalid  (m_axi_arvalid [M_TIMER]),
        .s_axi_arready  (m_axi_arready [M_TIMER]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_TIMER    +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_TIMER                   +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_TIMER]),
        .s_axi_rready   (m_axi_rready  [M_TIMER]),
        .timer_irq      (timer_irq)
    );

    // =========================================================================
    // GPIO (M4)
    // =========================================================================
    gpio u_gpio (
        .clk            (clk),
        .rst            (rst),
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_GPIO    +: `AXI_ADDR_WIDTH]),
        .s_axi_awvalid  (m_axi_awvalid [M_GPIO]),
        .s_axi_awready  (m_axi_awready [M_GPIO]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_GPIO     +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_GPIO     +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_GPIO]),
        .s_axi_wready   (m_axi_wready  [M_GPIO]),
        .s_axi_bresp    (m_axi_bresp   [2*M_GPIO                    +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_GPIO]),
        .s_axi_bready   (m_axi_bready  [M_GPIO]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_GPIO     +: `AXI_ADDR_WIDTH]),
        .s_axi_arvalid  (m_axi_arvalid [M_GPIO]),
        .s_axi_arready  (m_axi_arready [M_GPIO]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_GPIO     +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_GPIO                    +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_GPIO]),
        .s_axi_rready   (m_axi_rready  [M_GPIO]),
        .gpio_in        (gpio_in),
        .gpio_out       (gpio_out),
        .gpio_oe        (gpio_oe),
        .gpio_irq       (gpio_irq)
    );

    // =========================================================================
    // AES Engine (M5)
    // =========================================================================
    aes u_aes (
        .clk            (clk),
        .rst            (rst),
        .wdt_rst        (wdt_reset_aes),
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_AES     +: `AXI_ADDR_WIDTH]),
        .s_axi_awvalid  (m_axi_awvalid [M_AES]),
        .s_axi_awready  (m_axi_awready [M_AES]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_AES      +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_AES      +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_AES]),
        .s_axi_wready   (m_axi_wready  [M_AES]),
        .s_axi_bresp    (m_axi_bresp   [2*M_AES                     +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_AES]),
        .s_axi_bready   (m_axi_bready  [M_AES]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_AES      +: `AXI_ADDR_WIDTH]),
        .s_axi_arvalid  (m_axi_arvalid [M_AES]),
        .s_axi_arready  (m_axi_arready [M_AES]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_AES      +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_AES                     +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_AES]),
        .s_axi_rready   (m_axi_rready  [M_AES]),
        .aes_done       ()   // sideband – connect if needed externally
    );

    // =========================================================================
    // SPI Controller (M7)
    // =========================================================================
    spi u_spi (
        .clk            (clk),
        .rst            (rst | wdt_reset_spi),
        .s_axi_awaddr   (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_SPI     +: `AXI_ADDR_WIDTH]),
        .s_axi_awvalid  (m_axi_awvalid [M_SPI]),
        .s_axi_awready  (m_axi_awready [M_SPI]),
        .s_axi_wdata    (m_axi_wdata   [`AXI_DATA_WIDTH*M_SPI      +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb    (m_axi_wstrb   [`AXI_STRB_WIDTH*M_SPI      +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid   (m_axi_wvalid  [M_SPI]),
        .s_axi_wready   (m_axi_wready  [M_SPI]),
        .s_axi_bresp    (m_axi_bresp   [2*M_SPI                     +: 2]),
        .s_axi_bvalid   (m_axi_bvalid  [M_SPI]),
        .s_axi_bready   (m_axi_bready  [M_SPI]),
        .s_axi_araddr   (m_axi_araddr  [`AXI_ADDR_WIDTH*M_SPI      +: `AXI_ADDR_WIDTH]),
        .s_axi_arvalid  (m_axi_arvalid [M_SPI]),
        .s_axi_arready  (m_axi_arready [M_SPI]),
        .s_axi_rdata    (m_axi_rdata   [`AXI_DATA_WIDTH*M_SPI      +: `AXI_DATA_WIDTH]),
        .s_axi_rresp    (m_axi_rresp   [2*M_SPI                     +: 2]),
        .s_axi_rvalid   (m_axi_rvalid  [M_SPI]),
        .s_axi_rready   (m_axi_rready  [M_SPI]),
        .spi_sck        (spi_sck),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso),
        .spi_cs_n       (spi_cs_n),
        .spi_rx_dma_req (spi_rx_dma_req)
    );

    // =========================================================================
    // Watchdog (M8)
    // =========================================================================
    watchdog u_wdt (
        .clk             (clk),
        .rst             (rst),
        .s_axi_awaddr    (m_axi_awaddr  [`AXI_ADDR_WIDTH*M_WDT    +: `AXI_ADDR_WIDTH]),
        .s_axi_awvalid   (m_axi_awvalid [M_WDT]),
        .s_axi_awready   (m_axi_awready [M_WDT]),
        .s_axi_wdata     (m_axi_wdata   [`AXI_DATA_WIDTH*M_WDT     +: `AXI_DATA_WIDTH]),
        .s_axi_wstrb     (m_axi_wstrb   [`AXI_STRB_WIDTH*M_WDT     +: `AXI_STRB_WIDTH]),
        .s_axi_wvalid    (m_axi_wvalid  [M_WDT]),
        .s_axi_wready    (m_axi_wready  [M_WDT]),
        .s_axi_bresp     (m_axi_bresp   [2*M_WDT                    +: 2]),
        .s_axi_bvalid    (m_axi_bvalid  [M_WDT]),
        .s_axi_bready    (m_axi_bready  [M_WDT]),
        .s_axi_araddr    (m_axi_araddr  [`AXI_ADDR_WIDTH*M_WDT     +: `AXI_ADDR_WIDTH]),
        .s_axi_arvalid   (m_axi_arvalid [M_WDT]),
        .s_axi_arready   (m_axi_arready [M_WDT]),
        .s_axi_rdata     (m_axi_rdata   [`AXI_DATA_WIDTH*M_WDT     +: `AXI_DATA_WIDTH]),
        .s_axi_rresp     (m_axi_rresp   [2*M_WDT                    +: 2]),
        .s_axi_rvalid    (m_axi_rvalid  [M_WDT]),
        .s_axi_rready    (m_axi_rready  [M_WDT]),
        .wdt_reset_dma   (wdt_reset_dma),
        .wdt_reset_aes   (wdt_reset_aes),
        .wdt_reset_spi   (wdt_reset_spi),
        .wdt_fired       (wdt_fired)
    );

    // =========================================================================
    // Tie off unused M-side rlast inputs that AXI-Lite slaves don't drive
    // The interconnect uses rlast for AXI4 burst tracking.
    // AXI-Lite slaves leave s_axi_rlast unconnected; tie off at top.
    // (instruction_memory and data_memory do drive rlast, others don't)
    // =========================================================================
    // UART, Timer, GPIO, AES, DMA, SPI, WDT are AXI4-Lite – rlast unused.
    // The memories (IMEM/DMEM) drive rlast from their port.

    // Unused sideband tie-off
    // uart_rx is not connected to UART internals in this stub
    // (UART is TX-only in the current implementation)

endmodule

`resetall
