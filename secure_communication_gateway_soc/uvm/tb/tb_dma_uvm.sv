// =============================================================================
// File: tb_dma_uvm.sv
// Description: Dedicated Block-Level UVM Testbench for DMA Controller IP
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import soc_uvm_pkg::*;

module tb_dma_uvm;

    // Clock and Reset VIP
    clk_rst_if clk_rst_bus();
    wire clk = clk_rst_bus.clk;
    wire rst = clk_rst_bus.rst;

    // AXI4-Lite Slave Interface for DMA Configuration
    axi_if axi_cfg_bus (.clk(clk), .rst(rst));

    // AXI4 Master Interface for DMA Transfers
    axi_if axi_mst_bus (.clk(clk), .rst(rst));

    // Sideband signals
    logic wdt_rst;
    logic spi_rx_dma_req;
    logic uart_tx_dma_req;

    // Instantiate DMA DUT
    dma #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .ID_WIDTH  (8)
    ) u_dma (
        .clk             (clk),
        .rst             (rst),
        .wdt_rst         (wdt_rst),

        // Config Slave
        .s_axi_awaddr    (axi_cfg_bus.awaddr),
        .s_axi_awvalid   (axi_cfg_bus.awvalid),
        .s_axi_awready   (axi_cfg_bus.awready),
        .s_axi_wdata     (axi_cfg_bus.wdata),
        .s_axi_wstrb     (axi_cfg_bus.wstrb),
        .s_axi_wvalid    (axi_cfg_bus.wvalid),
        .s_axi_wready    (axi_cfg_bus.wready),
        .s_axi_bresp     (axi_cfg_bus.bresp),
        .s_axi_bvalid    (axi_cfg_bus.bvalid),
        .s_axi_bready    (axi_cfg_bus.bready),
        .s_axi_araddr    (axi_cfg_bus.araddr),
        .s_axi_arvalid   (axi_cfg_bus.arvalid),
        .s_axi_arready   (axi_cfg_bus.arready),
        .s_axi_rdata     (axi_cfg_bus.rdata),
        .s_axi_rresp     (axi_cfg_bus.rresp),
        .s_axi_rvalid    (axi_cfg_bus.rvalid),
        .s_axi_rready    (axi_cfg_bus.rready),

        // Master Port
        .m_axi_awid      (axi_mst_bus.awid),
        .m_axi_awaddr    (axi_mst_bus.awaddr),
        .m_axi_awlen     (axi_mst_bus.awlen),
        .m_axi_awsize    (axi_mst_bus.awsize),
        .m_axi_awburst   (axi_mst_bus.awburst),
        .m_axi_awlock    (axi_mst_bus.awlock),
        .m_axi_awcache   (axi_mst_bus.awcache),
        .m_axi_awprot    (axi_mst_bus.awprot),
        .m_axi_awqos     (axi_mst_bus.awqos),
        .m_axi_awvalid   (axi_mst_bus.awvalid),
        .m_axi_awready   (axi_mst_bus.awready),

        .m_axi_wdata     (axi_mst_bus.wdata),
        .m_axi_wstrb     (axi_mst_bus.wstrb),
        .m_axi_wlast     (axi_mst_bus.wlast),
        .m_axi_wvalid    (axi_mst_bus.wvalid),
        .m_axi_wready    (axi_mst_bus.wready),

        .m_axi_bid       (axi_mst_bus.bid),
        .m_axi_bresp     (axi_mst_bus.bresp),
        .m_axi_bvalid    (axi_mst_bus.bvalid),
        .m_axi_bready    (axi_mst_bus.bready),

        .m_axi_arid      (axi_mst_bus.arid),
        .m_axi_araddr    (axi_mst_bus.araddr),
        .m_axi_arlen     (axi_mst_bus.arlen),
        .m_axi_arsize    (axi_mst_bus.arsize),
        .m_axi_arburst   (axi_mst_bus.arburst),
        .m_axi_arlock    (axi_mst_bus.arlock),
        .m_axi_arcache   (axi_mst_bus.arcache),
        .m_axi_arprot    (axi_mst_bus.arprot),
        .m_axi_arqos     (axi_mst_bus.arqos),
        .m_axi_arvalid   (axi_mst_bus.arvalid),
        .m_axi_arready   (axi_mst_bus.arready),

        .m_axi_rid       (axi_mst_bus.rid),
        .m_axi_rdata     (axi_mst_bus.rdata),
        .m_axi_rresp     (axi_mst_bus.rresp),
        .m_axi_rlast     (axi_mst_bus.rlast),
        .m_axi_rvalid    (axi_mst_bus.rvalid),
        .m_axi_rready    (axi_mst_bus.rready),

        // Sidebands
        .spi_rx_dma_req  (spi_rx_dma_req),
        .uart_tx_dma_req (uart_tx_dma_req)
    );

    // Responder logic for DMA Master transfers
    always @(posedge clk) begin
        if (rst) begin
            axi_mst_bus.awready <= 1'b1;
            axi_mst_bus.wready  <= 1'b1;
            axi_mst_bus.bvalid  <= 1'b0;
            axi_mst_bus.bresp   <= 2'b00;
            axi_mst_bus.bid     <= 8'h00;
            axi_mst_bus.arready <= 1'b1;
            axi_mst_bus.rvalid  <= 1'b0;
            axi_mst_bus.rdata   <= 32'hA5A5_5A5A;
            axi_mst_bus.rresp   <= 2'b00;
            axi_mst_bus.rlast   <= 1'b1;
        end else begin
            // Write handshake
            if (axi_mst_bus.awvalid && axi_mst_bus.wvalid) begin
                axi_mst_bus.bvalid <= 1'b1;
                axi_mst_bus.bid    <= axi_mst_bus.awid;
            end else if (axi_mst_bus.bvalid && axi_mst_bus.bready) begin
                axi_mst_bus.bvalid <= 1'b0;
            end

            // Read handshake
            if (axi_mst_bus.arvalid) begin
                axi_mst_bus.rvalid <= 1'b1;
                axi_mst_bus.rid    <= axi_mst_bus.arid;
            end else if (axi_mst_bus.rvalid && axi_mst_bus.rready) begin
                axi_mst_bus.rvalid <= 1'b0;
            end
        end
    end

    initial begin
        wdt_rst         = 1'b0;
        spi_rx_dma_req  = 1'b1;
        uart_tx_dma_req = 1'b1;

        // Virtual Interface registration
        uvm_config_db #(virtual axi_if)::set     (null, "*m_axi_agent*",     "vif", axi_cfg_bus);
        uvm_config_db #(virtual clk_rst_if)::set (null, "*m_clk_rst_agent*", "vif", clk_rst_bus);

`ifdef DUMP_FSDB
        $fsdbDumpfile("dma_uvm.fsdb");
        $fsdbDumpvars(0, tb_dma_uvm);
`else
        $dumpfile("dma_uvm.vcd");
        $dumpvars(0, tb_dma_uvm);
`endif

        run_test();
    end

endmodule : tb_dma_uvm

