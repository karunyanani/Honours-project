// =============================================================================
// veer_el2_wrapper.v  –  VeeR EL2 Processor Integration Wrapper
//
// Spec refs:
//   - Section 2 req 4 : Original RTL SHALL NOT be modified
//   - Section 2 req 5 : Integration via separate wrappers and adapters
//   - Section 2 req 7 : IFU and LSU interfaces integrated via CPU-side adapter
//   - Section 2 req 10: Debug interfaces excluded from main interconnect
//
// This wrapper instantiates el2_veer_wrapper (CHIPS Alliance VeeR EL2) and:
//   1. Exposes the LSU AXI4 64-bit master interface outward.
//   2. Exposes the IFU AXI4 64-bit read interface outward.
//   3. Ties off all optional interfaces (debug, DMA slave, system-bus,
//      scratchpad memories, ICache RAM, clock overrides).
//   4. Routes external interrupts (GPIO DRDY, timer, DMA) into VeeR PIC.
//
// VeeR EL2 repository:
//   https://github.com/chipsalliance/Cores-VeeR-EL2.git
//   Commit: fa00c8aadc4a077d78b277129c1badf90d881255
//
// Bus interface (from el2_veer_wrapper.sv):
//   LSU AXI : 64-bit data, 32-bit address, LSU_BUS_TAG-bit ID  (read+write)
//   IFU AXI : 64-bit data, 32-bit address, IFU_BUS_TAG-bit ID  (read only)
//   Both are fed to cpu_axi_adapter for 64→32 bit conversion.
//
// RTL: Verilog-2001 wrapper shell; VeeR EL2 itself is SystemVerilog.
//      VCS and iverilog >=11 handle mixed-language at this boundary.
// Compile: add +define+RV_BUILD_AXI4 to enable AXI mode in VeeR EL2.
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module veer_el2_wrapper #(
    parameter [31:1] RESET_VEC   = 31'h0000_0000,
    parameter [31:1] NMI_VEC     = 31'h0000_0000,
    parameter        LSU_BUS_TAG = 4,
    parameter        IFU_BUS_TAG = 4
) (
    input  wire        clk,
    input  wire        rst_l,      // active-low (VeeR convention)

    // =========================================================================
    // LSU AXI4 master (64-bit data bus)
    // =========================================================================
    output wire                    lsu_axi_awvalid,
    input  wire                    lsu_axi_awready,
    output wire [LSU_BUS_TAG-1:0]  lsu_axi_awid,
    output wire [31:0]             lsu_axi_awaddr,
    output wire [7:0]              lsu_axi_awlen,
    output wire [2:0]              lsu_axi_awsize,
    output wire [1:0]              lsu_axi_awburst,
    output wire                    lsu_axi_awlock,
    output wire [3:0]              lsu_axi_awcache,
    output wire [2:0]              lsu_axi_awprot,
    output wire [3:0]              lsu_axi_awqos,
    output wire                    lsu_axi_wvalid,
    input  wire                    lsu_axi_wready,
    output wire [63:0]             lsu_axi_wdata,
    output wire [7:0]              lsu_axi_wstrb,
    output wire                    lsu_axi_wlast,
    input  wire                    lsu_axi_bvalid,
    output wire                    lsu_axi_bready,
    input  wire [1:0]              lsu_axi_bresp,
    input  wire [LSU_BUS_TAG-1:0]  lsu_axi_bid,
    output wire                    lsu_axi_arvalid,
    input  wire                    lsu_axi_arready,
    output wire [LSU_BUS_TAG-1:0]  lsu_axi_arid,
    output wire [31:0]             lsu_axi_araddr,
    output wire [7:0]              lsu_axi_arlen,
    output wire [2:0]              lsu_axi_arsize,
    output wire [1:0]              lsu_axi_arburst,
    output wire                    lsu_axi_arlock,
    output wire [3:0]              lsu_axi_arcache,
    output wire [2:0]              lsu_axi_arprot,
    output wire [3:0]              lsu_axi_arqos,
    input  wire                    lsu_axi_rvalid,
    output wire                    lsu_axi_rready,
    input  wire [LSU_BUS_TAG-1:0]  lsu_axi_rid,
    input  wire [63:0]             lsu_axi_rdata,
    input  wire [1:0]              lsu_axi_rresp,
    input  wire                    lsu_axi_rlast,

    // =========================================================================
    // IFU AXI4 master (64-bit data bus, read-only fetch)
    // =========================================================================
    output wire                    ifu_axi_arvalid,
    input  wire                    ifu_axi_arready,
    output wire [IFU_BUS_TAG-1:0]  ifu_axi_arid,
    output wire [31:0]             ifu_axi_araddr,
    output wire [7:0]              ifu_axi_arlen,
    output wire [2:0]              ifu_axi_arsize,
    output wire [1:0]              ifu_axi_arburst,
    output wire                    ifu_axi_arlock,
    output wire [3:0]              ifu_axi_arcache,
    output wire [2:0]              ifu_axi_arprot,
    output wire [3:0]              ifu_axi_arqos,
    input  wire                    ifu_axi_rvalid,
    output wire                    ifu_axi_rready,
    input  wire [IFU_BUS_TAG-1:0]  ifu_axi_rid,
    input  wire [63:0]             ifu_axi_rdata,
    input  wire [1:0]              ifu_axi_rresp,
    input  wire                    ifu_axi_rlast,

    // =========================================================================
    // Interrupts
    // =========================================================================
    input  wire        timer_irq,
    input  wire        gpio_irq,
    input  wire        dma_irq,

    // Debug status (output only, no interconnect connection)
    output wire        dbg_active
);

    // =========================================================================
    // Instantiate VeeR EL2 top-level wrapper
    // Compile guard: +define+RV_BUILD_AXI4 must be set
    // =========================================================================
`ifdef RV_BUILD_AXI4
    el2_veer_wrapper u_veer_el2 (
        .clk               ( clk    ),
        .rst_l             ( rst_l  ),
        .dbg_rst_l         ( rst_l  ),
        .rst_vec           ( RESET_VEC ),
        .nmi_int           ( 1'b0   ),
        .nmi_vec           ( NMI_VEC ),
        .jtag_id           ( 31'd0  ),

        // Trace outputs – unconnected
        .trace_rv_i_insn_ip      (),
        .trace_rv_i_address_ip   (),
        .trace_rv_i_valid_ip     (),
        .trace_rv_i_exception_ip (),
        .trace_rv_i_ecause_ip    (),
        .trace_rv_i_interrupt_ip (),
        .trace_rv_i_tval_ip      (),

        // Halt/run – tied off
        .i_cpu_halt_req         ( 1'b0 ),
        .i_cpu_run_req          ( 1'b0 ),
        .o_cpu_halt_ack         (),
        .o_cpu_halt_status      (),
        .o_cpu_run_ack          (),
        .o_debug_mode_status    ( dbg_active ),

        // MPC debug – tied off, run after reset
        .mpc_debug_halt_req     ( 1'b0 ),
        .mpc_debug_run_req      ( 1'b0 ),
        .mpc_reset_run_req      ( 1'b1 ),
        .mpc_debug_halt_ack     (),
        .mpc_debug_run_ack      (),
        .debug_brkpt_status     (),

        // Perf counters – unused
        .dec_tlu_perfcnt0       (),
        .dec_tlu_perfcnt1       (),
        .dec_tlu_perfcnt2       (),
        .dec_tlu_perfcnt3       (),

        // DCCM scratchpad – not used
        .dccm_wren              (),
        .dccm_rden              (),
        .dccm_wr_addr_lo        (),
        .dccm_wr_addr_hi        (),
        .dccm_rd_addr_lo        (),
        .dccm_rd_addr_hi        (),
        .dccm_wr_data_lo        (),
        .dccm_wr_data_hi        (),
        .dccm_rd_data_lo        ( 39'd0 ),
        .dccm_rd_data_hi        ( 39'd0 ),

        // ICCM – not used
        .iccm_rw_addr           (),
        .iccm_wren              (),
        .iccm_rden              (),
        .iccm_wr_size           (),
        .iccm_wr_data           (),
        .iccm_buf_correct_ecc   (),
        .iccm_correction_state  (),
        .iccm_rd_data_ecc       ( 78'd0 ),

        // ICache – disabled
        .ic_rw_addr             (),
        .ic_tag_valid           (),
        .ic_wr_en               (),
        .ic_rd_en               (),
        .ic_wr_data             (),
        .ic_rd_data             ( 142'd0 ),
        .ic_rd_addr_lo          ( 2'd0   ),
        .ic_rd_bank_check_en    ( 4'd0   ),
        .ic_debug_rd_data       ( 71'd0  ),
        .ictag_debug_rd_data    ( 26'd0  ),
        .ic_debug_wr_data       (),
        .ic_debug_addr          (),
        .ic_debug_rd_en         (),
        .ic_debug_wr_en         (),
        .ic_debug_tag_array     (),
        .ic_debug_way           (),
        .ic_rd_hit              ( 4'd0 ),
        .ic_tag_perr            ( 1'b0 ),

        // LSU AXI master
        .lsu_axi_awvalid        ( lsu_axi_awvalid  ),
        .lsu_axi_awready        ( lsu_axi_awready  ),
        .lsu_axi_awid           ( lsu_axi_awid     ),
        .lsu_axi_awaddr         ( lsu_axi_awaddr   ),
        .lsu_axi_awregion       (),
        .lsu_axi_awlen          ( lsu_axi_awlen    ),
        .lsu_axi_awsize         ( lsu_axi_awsize   ),
        .lsu_axi_awburst        ( lsu_axi_awburst  ),
        .lsu_axi_awlock         ( lsu_axi_awlock   ),
        .lsu_axi_awcache        ( lsu_axi_awcache  ),
        .lsu_axi_awprot         ( lsu_axi_awprot   ),
        .lsu_axi_awqos          ( lsu_axi_awqos    ),
        .lsu_axi_wvalid         ( lsu_axi_wvalid   ),
        .lsu_axi_wready         ( lsu_axi_wready   ),
        .lsu_axi_wdata          ( lsu_axi_wdata    ),
        .lsu_axi_wstrb          ( lsu_axi_wstrb    ),
        .lsu_axi_wlast          ( lsu_axi_wlast    ),
        .lsu_axi_bvalid         ( lsu_axi_bvalid   ),
        .lsu_axi_bready         ( lsu_axi_bready   ),
        .lsu_axi_bresp          ( lsu_axi_bresp    ),
        .lsu_axi_bid            ( lsu_axi_bid      ),
        .lsu_axi_arvalid        ( lsu_axi_arvalid  ),
        .lsu_axi_arready        ( lsu_axi_arready  ),
        .lsu_axi_arid           ( lsu_axi_arid     ),
        .lsu_axi_araddr         ( lsu_axi_araddr   ),
        .lsu_axi_arregion       (),
        .lsu_axi_arlen          ( lsu_axi_arlen    ),
        .lsu_axi_arsize         ( lsu_axi_arsize   ),
        .lsu_axi_arburst        ( lsu_axi_arburst  ),
        .lsu_axi_arlock         ( lsu_axi_arlock   ),
        .lsu_axi_arcache        ( lsu_axi_arcache  ),
        .lsu_axi_arprot         ( lsu_axi_arprot   ),
        .lsu_axi_arqos          ( lsu_axi_arqos    ),
        .lsu_axi_rvalid         ( lsu_axi_rvalid   ),
        .lsu_axi_rready         ( lsu_axi_rready   ),
        .lsu_axi_rid            ( lsu_axi_rid      ),
        .lsu_axi_rdata          ( lsu_axi_rdata    ),
        .lsu_axi_rresp          ( lsu_axi_rresp    ),
        .lsu_axi_rlast          ( lsu_axi_rlast    ),

        // IFU AXI master (read-only; write side tied off)
        .ifu_axi_awvalid        ( 1'b0  ),
        .ifu_axi_awready        (),
        .ifu_axi_awid           (),
        .ifu_axi_awaddr         (),
        .ifu_axi_awregion       (),
        .ifu_axi_awlen          (),
        .ifu_axi_awsize         (),
        .ifu_axi_awburst        (),
        .ifu_axi_awlock         (),
        .ifu_axi_awcache        (),
        .ifu_axi_awprot         (),
        .ifu_axi_awqos          (),
        .ifu_axi_wvalid         ( 1'b0  ),
        .ifu_axi_wready         (),
        .ifu_axi_wdata          (),
        .ifu_axi_wstrb          (),
        .ifu_axi_wlast          (),
        .ifu_axi_bvalid         ( 1'b0  ),
        .ifu_axi_bready         (),
        .ifu_axi_bresp          ( 2'b00 ),
        .ifu_axi_bid            ( {IFU_BUS_TAG{1'b0}} ),
        .ifu_axi_arvalid        ( ifu_axi_arvalid  ),
        .ifu_axi_arready        ( ifu_axi_arready  ),
        .ifu_axi_arid           ( ifu_axi_arid     ),
        .ifu_axi_araddr         ( ifu_axi_araddr   ),
        .ifu_axi_arregion       (),
        .ifu_axi_arlen          ( ifu_axi_arlen    ),
        .ifu_axi_arsize         ( ifu_axi_arsize   ),
        .ifu_axi_arburst        ( ifu_axi_arburst  ),
        .ifu_axi_arlock         ( ifu_axi_arlock   ),
        .ifu_axi_arcache        ( ifu_axi_arcache  ),
        .ifu_axi_arprot         ( ifu_axi_arprot   ),
        .ifu_axi_arqos          ( ifu_axi_arqos    ),
        .ifu_axi_rvalid         ( ifu_axi_rvalid   ),
        .ifu_axi_rready         ( ifu_axi_rready   ),
        .ifu_axi_rid            ( ifu_axi_rid      ),
        .ifu_axi_rdata          ( ifu_axi_rdata    ),
        .ifu_axi_rresp          ( ifu_axi_rresp    ),
        .ifu_axi_rlast          ( ifu_axi_rlast    ),

        // System-bus (debug) AXI – fully tied off
        .sb_axi_awvalid         (),
        .sb_axi_awready         ( 1'b1  ),
        .sb_axi_awid            (),
        .sb_axi_awaddr          (),
        .sb_axi_awregion        (),
        .sb_axi_awlen           (),
        .sb_axi_awsize          (),
        .sb_axi_awburst         (),
        .sb_axi_awlock          (),
        .sb_axi_awcache         (),
        .sb_axi_awprot          (),
        .sb_axi_awqos           (),
        .sb_axi_wvalid          (),
        .sb_axi_wready          ( 1'b1  ),
        .sb_axi_wdata           (),
        .sb_axi_wstrb           (),
        .sb_axi_wlast           (),
        .sb_axi_bvalid          ( 1'b0  ),
        .sb_axi_bready          (),
        .sb_axi_bresp           ( 2'b00 ),
        .sb_axi_bid             ( 1'b0  ),
        .sb_axi_arvalid         (),
        .sb_axi_arready         ( 1'b1  ),
        .sb_axi_arid            (),
        .sb_axi_araddr          (),
        .sb_axi_arregion        (),
        .sb_axi_arlen           (),
        .sb_axi_arsize          (),
        .sb_axi_arburst         (),
        .sb_axi_arlock          (),
        .sb_axi_arcache         (),
        .sb_axi_arprot          (),
        .sb_axi_arqos           (),
        .sb_axi_rvalid          ( 1'b0  ),
        .sb_axi_rready          (),
        .sb_axi_rid             ( 1'b0  ),
        .sb_axi_rdata           ( 64'd0 ),
        .sb_axi_rresp           ( 2'b00 ),
        .sb_axi_rlast           ( 1'b0  ),

        // DMA AXI slave – not used (DMA is a separate master on the interconnect)
        .dma_axi_awvalid        ( 1'b0  ),
        .dma_axi_awready        (),
        .dma_axi_awid           ( 1'b0  ),
        .dma_axi_awaddr         ( 32'd0 ),
        .dma_axi_awsize         ( 3'd0  ),
        .dma_axi_awlen          ( 8'd0  ),
        .dma_axi_awburst        ( 2'b01 ),
        .dma_axi_wvalid         ( 1'b0  ),
        .dma_axi_wready         (),
        .dma_axi_wdata          ( 64'd0 ),
        .dma_axi_wstrb          ( 8'd0  ),
        .dma_axi_wlast          ( 1'b0  ),
        .dma_axi_bvalid         (),
        .dma_axi_bready         ( 1'b1  ),
        .dma_axi_bresp          (),
        .dma_axi_bid            (),
        .dma_axi_arvalid        ( 1'b0  ),
        .dma_axi_arready        (),
        .dma_axi_arid           ( 1'b0  ),
        .dma_axi_araddr         ( 32'd0 ),
        .dma_axi_arsize         ( 3'd0  ),
        .dma_axi_arlen          ( 8'd0  ),
        .dma_axi_arburst        ( 2'b01 ),
        .dma_axi_rvalid         (),
        .dma_axi_rready         ( 1'b1  ),
        .dma_axi_rid            (),
        .dma_axi_rdata          (),
        .dma_axi_rresp          (),
        .dma_axi_rlast          (),

        // External interrupts into VeeR PIC
        // [0]=reserved, [1]=gpio_irq, [2]=timer_irq, [3]=dma_irq, [4..31]=0
        .extintsrc_req          ( {28'd0, dma_irq, timer_irq, gpio_irq, 1'b0} ),

        .core_id                ( 28'd0     ),
        .timer_int              ( timer_irq ),
        .soft_int               ( 1'b0      ),

        // Clock / ECC overrides – unused outputs
        .active_l2clk           (),
        .free_l2clk             (),
        .dccm_clk_override      (),
        .icm_clk_override       (),
        .dec_tlu_core_ecc_disable          (),
        .dec_tlu_dccm_wr_readback_disable  (),
        .core_rst_l             ()
    );
`else
    // Default tied-off assignments when building without VeeR EL2 proprietary core
    assign lsu_axi_awvalid = 1'b0;
    assign lsu_axi_awid    = {LSU_BUS_TAG{1'b0}};
    assign lsu_axi_awaddr  = 32'd0;
    assign lsu_axi_awlen   = 8'd0;
    assign lsu_axi_awsize  = 3'd0;
    assign lsu_axi_awburst = 2'd0;
    assign lsu_axi_awlock  = 1'b0;
    assign lsu_axi_awcache = 4'd0;
    assign lsu_axi_awprot  = 3'd0;
    assign lsu_axi_awqos   = 4'd0;
    assign lsu_axi_wvalid  = 1'b0;
    assign lsu_axi_wdata   = 64'd0;
    assign lsu_axi_wstrb   = 8'd0;
    assign lsu_axi_wlast   = 1'b0;
    assign lsu_axi_bready  = 1'b0;
    assign lsu_axi_arvalid = 1'b0;
    assign lsu_axi_arid    = {LSU_BUS_TAG{1'b0}};
    assign lsu_axi_araddr  = 32'd0;
    assign lsu_axi_arlen   = 8'd0;
    assign lsu_axi_arsize  = 3'd0;
    assign lsu_axi_arburst = 2'd0;
    assign lsu_axi_arlock  = 1'b0;
    assign lsu_axi_arcache = 4'd0;
    assign lsu_axi_arprot  = 3'd0;
    assign lsu_axi_arqos   = 4'd0;
    assign lsu_axi_rready  = 1'b0;

    assign ifu_axi_arvalid = 1'b0;
    assign ifu_axi_arid    = {IFU_BUS_TAG{1'b0}};
    assign ifu_axi_araddr  = 32'd0;
    assign ifu_axi_arlen   = 8'd0;
    assign ifu_axi_arsize  = 3'd0;
    assign ifu_axi_arburst = 2'd0;
    assign ifu_axi_arlock  = 1'b0;
    assign ifu_axi_arcache = 4'd0;
    assign ifu_axi_arprot  = 3'd0;
    assign ifu_axi_arqos   = 4'd0;
    assign ifu_axi_rready  = 1'b0;

    assign dbg_active      = 1'b0;
`endif

endmodule

`resetall
