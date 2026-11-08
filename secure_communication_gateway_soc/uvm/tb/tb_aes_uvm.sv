// =============================================================================
// File: tb_aes_uvm.sv
// Description: Dedicated Block-Level UVM Testbench for AES-128 CTR Engine
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import soc_uvm_pkg::*;

module tb_aes_uvm;

    // Clock and Reset VIP
    clk_rst_if clk_rst_bus();
    wire clk = clk_rst_bus.clk;
    wire rst = clk_rst_bus.rst;

    // AXI4-Lite Interface for AES Configuration & Datapath
    axi_if axi_bus (.clk(clk), .rst(rst));

    // Scoped reset sideband
    logic wdt_rst;

    // Instantiate AES DUT
    aes #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(8)
    ) u_aes (
        .clk           (clk),
        .rst           (rst),
        .wdt_rst       (wdt_rst),
        .s_axi_awaddr  (axi_bus.awaddr[7:0]),
        .s_axi_awvalid (axi_bus.awvalid),
        .s_axi_awready (axi_bus.awready),
        .s_axi_wdata   (axi_bus.wdata),
        .s_axi_wstrb   (axi_bus.wstrb),
        .s_axi_wvalid  (axi_bus.wvalid),
        .s_axi_wready  (axi_bus.wready),
        .s_axi_bresp   (axi_bus.bresp),
        .s_axi_bvalid  (axi_bus.bvalid),
        .s_axi_bready  (axi_bus.bready),
        .s_axi_araddr  (axi_bus.araddr[7:0]),
        .s_axi_arvalid (axi_bus.arvalid),
        .s_axi_arready (axi_bus.arready),
        .s_axi_rdata   (axi_bus.rdata),
        .s_axi_rresp   (axi_bus.rresp),
        .s_axi_rvalid  (axi_bus.rvalid),
        .s_axi_rready  (axi_bus.rready)
    );

    // Protocol Assertions
    axi_assertions u_axi_assert (
        .clk     (clk),
        .rst     (rst),
        .awaddr  (axi_bus.awaddr),
        .awvalid (axi_bus.awvalid),
        .awready (axi_bus.awready),
        .wdata   (axi_bus.wdata),
        .wstrb   (axi_bus.wstrb),
        .wvalid  (axi_bus.wvalid),
        .wready  (axi_bus.wready),
        .bresp   (axi_bus.bresp),
        .bvalid  (axi_bus.bvalid),
        .bready  (axi_bus.bready),
        .araddr  (axi_bus.araddr),
        .arvalid (axi_bus.arvalid),
        .arready (axi_bus.arready),
        .rdata   (axi_bus.rdata),
        .rresp   (axi_bus.rresp),
        .rvalid  (axi_bus.rvalid),
        .rready  (axi_bus.rready)
    );

    initial begin
        wdt_rst = 1'b0;

        // Virtual Interface registration
        uvm_config_db #(virtual axi_if)::set     (null, "*m_axi_agent*",     "vif", axi_bus);
        uvm_config_db #(virtual clk_rst_if)::set (null, "*m_clk_rst_agent*", "vif", clk_rst_bus);

`ifdef DUMP_FSDB
        $fsdbDumpfile("aes_uvm.fsdb");
        $fsdbDumpvars(0, tb_aes_uvm);
`else
        $dumpfile("aes_uvm.vcd");
        $dumpvars(0, tb_aes_uvm);
`endif

        run_test();
    end

endmodule : tb_aes_uvm

