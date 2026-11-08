// =============================================================================
// File: tb_interconnect_uvm.sv
// Description: Dedicated Block-Level UVM Testbench for AXI4 2x9 Interconnect
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import soc_uvm_pkg::*;

module tb_interconnect_uvm;

    // Clock and Reset VIP
    clk_rst_if clk_rst_bus();
    wire clk = clk_rst_bus.clk;
    wire rst = clk_rst_bus.rst;

    // AXI Master VIP for Master 0 (CPU)
    axi_if axi_m0 (.clk(clk), .rst(rst));

    // AXI Master VIP for Master 1 (DMA)
    axi_if axi_m1 (.clk(clk), .rst(rst));

    // Interconnect S-side (masters)
    wire [15:0] s_axi_awid    = {axi_m1.awid,    axi_m0.awid};
    wire [63:0] s_axi_awaddr  = {axi_m1.awaddr,  axi_m0.awaddr};
    wire [15:0] s_axi_awlen   = {axi_m1.awlen,   axi_m0.awlen};
    wire [5:0]  s_axi_awsize  = {axi_m1.awsize,  axi_m0.awsize};
    wire [3:0]  s_axi_awburst = {axi_m1.awburst, axi_m0.awburst};
    wire [1:0]  s_axi_awlock  = {axi_m1.awlock,  axi_m0.awlock};
    wire [7:0]  s_axi_awcache = {axi_m1.awcache, axi_m0.awcache};
    wire [5:0]  s_axi_awprot  = {axi_m1.awprot,  axi_m0.awprot};
    wire [7:0]  s_axi_awqos   = {axi_m1.awqos,   axi_m0.awqos};
    wire [1:0]  s_axi_awvalid = {axi_m1.awvalid, axi_m0.awvalid};
    wire [1:0]  s_axi_awready;

    assign axi_m0.awready = s_axi_awready[0];
    assign axi_m1.awready = s_axi_awready[1];

    wire [63:0] s_axi_wdata   = {axi_m1.wdata,   axi_m0.wdata};
    wire [7:0]  s_axi_wstrb   = {axi_m1.wstrb,   axi_m0.wstrb};
    wire [1:0]  s_axi_wlast   = {axi_m1.wlast,   axi_m0.wlast};
    wire [1:0]  s_axi_wvalid  = {axi_m1.wvalid,  axi_m0.wvalid};
    wire [1:0]  s_axi_wready;

    assign axi_m0.wready  = s_axi_wready[0];
    assign axi_m1.wready  = s_axi_wready[1];

    wire [15:0] s_axi_bid;
    wire [3:0]  s_axi_bresp;
    wire [1:0]  s_axi_bvalid;
    wire [1:0]  s_axi_bready  = {axi_m1.bready,  axi_m0.bready};

    assign axi_m0.bid     = s_axi_bid[7:0];
    assign axi_m0.bresp   = s_axi_bresp[1:0];
    assign axi_m0.bvalid  = s_axi_bvalid[0];
    assign axi_m1.bid     = s_axi_bid[15:8];
    assign axi_m1.bresp   = s_axi_bresp[3:2];
    assign axi_m1.bvalid  = s_axi_bvalid[1];

    wire [15:0] s_axi_arid    = {axi_m1.arid,    axi_m0.arid};
    wire [63:0] s_axi_araddr  = {axi_m1.araddr,  axi_m0.araddr};
    wire [15:0] s_axi_arlen   = {axi_m1.arlen,   axi_m0.arlen};
    wire [5:0]  s_axi_arsize  = {axi_m1.arsize,  axi_m0.arsize};
    wire [3:0]  s_axi_arburst = {axi_m1.arburst, axi_m0.arburst};
    wire [1:0]  s_axi_arlock  = {axi_m1.arlock,  axi_m0.arlock};
    wire [7:0]  s_axi_arcache = {axi_m1.arcache, axi_m0.arcache};
    wire [5:0]  s_axi_arprot  = {axi_m1.arprot,  axi_m0.arprot};
    wire [7:0]  s_axi_arqos   = {axi_m1.arqos,   axi_m0.arqos};
    wire [1:0]  s_axi_arvalid = {axi_m1.arvalid, axi_m0.arvalid};
    wire [1:0]  s_axi_arready;

    assign axi_m0.arready = s_axi_arready[0];
    assign axi_m1.arready = s_axi_arready[1];

    wire [15:0] s_axi_rid;
    wire [63:0] s_axi_rdata;
    wire [3:0]  s_axi_rresp;
    wire [1:0]  s_axi_rlast;
    wire [1:0]  s_axi_rvalid;
    wire [1:0]  s_axi_rready  = {axi_m1.rready,  axi_m0.rready};

    assign axi_m0.rid     = s_axi_rid[7:0];
    assign axi_m0.rdata   = s_axi_rdata[31:0];
    assign axi_m0.rresp   = s_axi_rresp[1:0];
    assign axi_m0.rlast   = s_axi_rlast[0];
    assign axi_m0.rvalid  = s_axi_rvalid[0];
    assign axi_m1.rid     = s_axi_rid[15:8];
    assign axi_m1.rdata   = s_axi_rdata[63:32];
    assign axi_m1.rresp   = s_axi_rresp[3:2];
    assign axi_m1.rlast   = s_axi_rlast[1];
    assign axi_m1.rvalid  = s_axi_rvalid[1];

    // Interconnect M-side (slaves M0..M8)
    wire [9*`AXI_ID_WIDTH-1:0]   m_axi_awid;
    wire [9*`AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [9*8-1:0]                m_axi_awlen;
    wire [9*3-1:0]                m_axi_awsize;
    wire [9*2-1:0]                m_axi_awburst;
    wire [9-1:0]                  m_axi_awlock;
    wire [9*4-1:0]                m_axi_awcache;
    wire [9*3-1:0]                m_axi_awprot;
    wire [9*4-1:0]                m_axi_awqos;
    wire [9*4-1:0]                m_axi_awregion;
    wire [9-1:0]                  m_axi_awvalid;
    reg  [9-1:0]                  m_axi_awready;

    wire [9*`AXI_DATA_WIDTH-1:0] m_axi_wdata;
    wire [9*`AXI_STRB_WIDTH-1:0] m_axi_wstrb;
    wire [9-1:0]                  m_axi_wlast;
    wire [9-1:0]                  m_axi_wvalid;
    reg  [9-1:0]                  m_axi_wready;

    reg  [9*`AXI_ID_WIDTH-1:0]   m_axi_bid;
    reg  [9*2-1:0]                m_axi_bresp;
    reg  [9-1:0]                  m_axi_bvalid;
    wire [9-1:0]                  m_axi_bready;

    wire [9*`AXI_ID_WIDTH-1:0]   m_axi_arid;
    wire [9*`AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    wire [9*8-1:0]                m_axi_arlen;
    wire [9*3-1:0]                m_axi_arsize;
    wire [9*2-1:0]                m_axi_arburst;
    wire [9-1:0]                  m_axi_arlock;
    wire [9*4-1:0]                m_axi_arcache;
    wire [9*3-1:0]                m_axi_arprot;
    wire [9*4-1:0]                m_axi_arqos;
    wire [9*4-1:0]                m_axi_arregion;
    wire [9-1:0]                  m_axi_arvalid;
    reg  [9-1:0]                  m_axi_arready;

    reg  [9*`AXI_ID_WIDTH-1:0]   m_axi_rid;
    reg  [9*`AXI_DATA_WIDTH-1:0] m_axi_rdata;
    reg  [9*2-1:0]                m_axi_rresp;
    reg  [9-1:0]                  m_axi_rlast;
    reg  [9-1:0]                  m_axi_rvalid;
    wire [9-1:0]                  m_axi_rready;

    // Instantiate Interconnect DUT
    soc_axi_interconnect_wrap_2x9 u_interconnect (
        .clk            (clk),
        .rst            (rst),

        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awlock   (s_axi_awlock),
        .s_axi_awcache  (s_axi_awcache),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awqos    (s_axi_awqos),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),

        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wlast    (s_axi_wlast),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),

        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),

        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arlock   (s_axi_arlock),
        .s_axi_arcache  (s_axi_arcache),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arqos    (s_axi_arqos),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),

        .s_axi_rid      (s_axi_rid),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awqos    (m_axi_awqos),
        .m_axi_awregion (m_axi_awregion),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),

        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),

        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),

        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arqos    (m_axi_arqos),
        .m_axi_arregion (m_axi_arregion),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),

        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // Simple responder for all 9 downstream slaves
    genvar i;
    generate
        for (i = 0; i < 9; i = i + 1) begin : gen_slave_resp
            always @(posedge clk) begin
                if (rst) begin
                    m_axi_awready[i] <= 1'b1;
                    m_axi_wready[i]  <= 1'b1;
                    m_axi_bvalid[i]  <= 1'b0;
                    m_axi_bresp[i*2 +: 2] <= 2'b00;
                    m_axi_arready[i] <= 1'b1;
                    m_axi_rvalid[i]  <= 1'b0;
                    m_axi_rdata[i*32 +: 32] <= 32'hDEAD_BEEF;
                    m_axi_rresp[i*2 +: 2] <= 2'b00;
                    m_axi_rlast[i]   <= 1'b1;
                end else begin
                    // Write
                    if (m_axi_awvalid[i] && m_axi_wvalid[i]) begin
                        m_axi_bvalid[i] <= 1'b1;
                        m_axi_bid[i*`AXI_ID_WIDTH +: `AXI_ID_WIDTH] <= m_axi_awid[i*`AXI_ID_WIDTH +: `AXI_ID_WIDTH];
                    end else if (m_axi_bvalid[i] && m_axi_bready[i]) begin
                        m_axi_bvalid[i] <= 1'b0;
                    end

                    // Read
                    if (m_axi_arvalid[i]) begin
                        m_axi_rvalid[i] <= 1'b1;
                        m_axi_rid[i*`AXI_ID_WIDTH +: `AXI_ID_WIDTH] <= m_axi_arid[i*`AXI_ID_WIDTH +: `AXI_ID_WIDTH];
                    end else if (m_axi_rvalid[i] && m_axi_rready[i]) begin
                        m_axi_rvalid[i] <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    initial begin
        uvm_config_db #(virtual axi_if)::set     (null, "*m_axi_agent*",     "vif", axi_m0);
        uvm_config_db #(virtual clk_rst_if)::set (null, "*m_clk_rst_agent*", "vif", clk_rst_bus);

`ifdef DUMP_FSDB
        $fsdbDumpfile("interconnect_uvm.fsdb");
        $fsdbDumpvars(0, tb_interconnect_uvm);
`else
        $dumpfile("interconnect_uvm.vcd");
        $dumpvars(0, tb_interconnect_uvm);
`endif

        run_test();
    end

endmodule : tb_interconnect_uvm

