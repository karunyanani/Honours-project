// =============================================================================
// File: tb_top.sv
// Description: UVM Testbench Top Module for Secure Communication Gateway SoC
// Features:
//   - Instantiates all Verification IPs:
//       * AXI4 Verification IP (axi_agent)
//       * SPI Sensor Verification IP (spi_agent)
//       * Full-Duplex UART Verification IP (uart_agent)
//       * GPIO & Pad Verification IP (gpio_agent)
//       * Interrupt & Fault Recovery VIP (interrupt_agent)
//       * Clock & Reset Generation VIP (clk_rst_agent)
//   - Complete DUT (soc_top) Pin & Internal Bus Integration
//   - SVA Protocol Assertions Binding
//   - Virtual Interface Registration into uvm_config_db
//   - FSDB / VCD Waveform Dumper Configuration
// =============================================================================

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import soc_uvm_pkg::*;

module tb_top;

    // =========================================================================
    // Clock and Reset VIP Interface
    // =========================================================================
    clk_rst_if clk_rst_bus();

    wire clk   = clk_rst_bus.clk;
    wire rst_n = clk_rst_bus.rst_n;
    wire rst   = clk_rst_bus.rst;

    // =========================================================================
    // Protocol Interfaces
    // =========================================================================
    axi_if       axi_bus  (.clk(clk), .rst(rst));
    spi_if       spi_bus  (.clk(clk), .rst(rst));
    uart_if      uart_bus (.clk(clk), .rst(rst));
    gpio_if      gpio_bus (.clk(clk), .rst(rst));
    interrupt_if irq_bus  (.clk(clk), .rst(rst));

    // =========================================================================
    // Interconnect Physical & Sideband Signals
    // =========================================================================
    wire        uart_tx;
    wire        uart_rx;
    wire        spi_sck;
    wire        spi_mosi;
    wire        spi_miso;
    wire        spi_cs_n;
    wire [7:0]  gpio_in;
    wire [7:0]  gpio_out;
    wire [7:0]  gpio_oe;
    wire        gpio_irq;
    wire        timer_irq;
    wire        wdt_fired;
    wire [31:0] dbg_pc;

    // Bind interface signals
    assign gpio_in              = gpio_bus.gpio_in;
    assign gpio_bus.gpio_out    = gpio_out;
    assign gpio_bus.gpio_oe     = gpio_oe;
    assign gpio_bus.gpio_irq    = gpio_irq;

    assign uart_rx              = uart_bus.uart_rx;
    assign uart_bus.uart_tx     = uart_tx;

    assign spi_bus.sclk         = spi_sck;
    assign spi_bus.cs_n         = spi_cs_n;
    assign spi_bus.mosi         = spi_mosi;
    assign spi_miso             = spi_bus.miso;

    assign irq_bus.gpio_irq     = gpio_irq;
    assign irq_bus.timer_irq    = timer_irq;
    assign irq_bus.wdt_fired    = wdt_fired;

    // =========================================================================
    // DUT Instantiation (soc_top)
    // =========================================================================
    soc_top #(
        .CLK_FREQ_HZ  (50_000_000),
        .BAUD_RATE    (115_200)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .gpio_in     (gpio_in),
        .gpio_out    (gpio_out),
        .gpio_oe     (gpio_oe),
        .uart_tx     (uart_tx),
        .uart_rx     (uart_rx),
        .spi_sck     (spi_sck),
        .spi_mosi    (spi_mosi),
        .spi_miso    (spi_miso),
        .spi_cs_n    (spi_cs_n),
        .gpio_irq    (gpio_irq),
        .timer_irq   (timer_irq),
        .wdt_fired   (wdt_fired),
        .dbg_pc      (dbg_pc)
    );

    // =========================================================================
    // AXI Master VIP Bridging & CPU Integration Mode Configuration
    // =========================================================================
    // Mode selection:
    //   axi_vip_master_en = 1: VIP drives stimulus (for VIP unit sequences, CPU held in reset)
    //   axi_vip_master_en = 0: CPU Integration Mode (CPU adapter drives fabric, VIP passively monitors)
    bit axi_vip_master_en = 1'b1;

    initial begin
        void'($value$plusargs("AXI_VIP_MASTER_EN=%d", axi_vip_master_en));
        if (!axi_vip_master_en) begin
            `uvm_info("TB_TOP", "CPU Integration Mode: CPU adapter drives interconnect Port S0 with zero bypass forces.", UVM_LOW)
        end
    end

    // Slave responses from interconnect back to VIP / CPU adapter
    assign axi_bus.awready = u_dut.u_interconnect.s_axi_awready[0];
    assign axi_bus.wready  = u_dut.u_interconnect.s_axi_wready[0];
    assign axi_bus.bid     = u_dut.u_interconnect.s_axi_bid[0*8 +: 8];
    assign axi_bus.bresp   = u_dut.u_interconnect.s_axi_bresp[0*2 +: 2];
    assign axi_bus.bvalid  = u_dut.u_interconnect.s_axi_bvalid[0];
    assign axi_bus.arready = u_dut.u_interconnect.s_axi_arready[0];
    assign axi_bus.rid     = u_dut.u_interconnect.s_axi_rid[0*8 +: 8];
    assign axi_bus.rdata   = u_dut.u_interconnect.s_axi_rdata[0*32 +: 32];
    assign axi_bus.rresp   = u_dut.u_interconnect.s_axi_rresp[0*2 +: 2];
    assign axi_bus.rlast   = u_dut.u_interconnect.s_axi_rlast[0];
    assign axi_bus.rvalid  = u_dut.u_interconnect.s_axi_rvalid[0];

    // In CPU integration mode, expose CPU adapter outputs to axi_bus for passive VIP monitoring
    assign axi_bus.awid    = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_awid    : 8'bz;
    assign axi_bus.awaddr  = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_awaddr  : 32'bz;
    assign axi_bus.awlen   = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_awlen   : 8'bz;
    assign axi_bus.awsize  = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_awsize  : 3'bz;
    assign axi_bus.awburst = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_awburst : 2'bz;
    assign axi_bus.awvalid = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_awvalid : 1'bz;

    assign axi_bus.wdata   = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_wdata   : 32'bz;
    assign axi_bus.wstrb   = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_wstrb   : 4'bz;
    assign axi_bus.wlast   = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_wlast   : 1'bz;
    assign axi_bus.wvalid  = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_wvalid  : 1'bz;
    assign axi_bus.bready  = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_bready  : 1'bz;

    assign axi_bus.arid    = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_arid    : 8'bz;
    assign axi_bus.araddr  = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_araddr  : 32'bz;
    assign axi_bus.arlen   = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_arlen   : 8'bz;
    assign axi_bus.arsize  = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_arsize  : 3'bz;
    assign axi_bus.arburst = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_arburst : 2'bz;
    assign axi_bus.arvalid = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_arvalid : 1'bz;
    assign axi_bus.rready  = (!axi_vip_master_en) ? u_dut.u_cpu.m_axi_rready  : 1'bz;

    // Drive interconnect Port S0 only when VIP Master Injection is explicitly enabled
    always @(*) begin
        if (axi_vip_master_en) begin
            // Hold CPU in reset so it does not collide with VIP injection
            force u_dut.u_cpu.rst = 1'b1;

            if (axi_bus.awvalid) begin
                force u_dut.u_interconnect.s_axi_awid[0*8 +: 8]     = axi_bus.awid;
                force u_dut.u_interconnect.s_axi_awaddr[0*32 +: 32] = axi_bus.awaddr;
                force u_dut.u_interconnect.s_axi_awlen[0*8 +: 8]    = axi_bus.awlen;
                force u_dut.u_interconnect.s_axi_awsize[0*3 +: 3]   = axi_bus.awsize;
                force u_dut.u_interconnect.s_axi_awburst[0*2 +: 2]  = axi_bus.awburst;
                force u_dut.u_interconnect.s_axi_awvalid[0]         = axi_bus.awvalid;
            end else begin
                release u_dut.u_interconnect.s_axi_awid[0*8 +: 8];
                release u_dut.u_interconnect.s_axi_awaddr[0*32 +: 32];
                release u_dut.u_interconnect.s_axi_awlen[0*8 +: 8];
                release u_dut.u_interconnect.s_axi_awsize[0*3 +: 3];
                release u_dut.u_interconnect.s_axi_awburst[0*2 +: 2];
                release u_dut.u_interconnect.s_axi_awvalid[0];
            end

            if (axi_bus.wvalid) begin
                force u_dut.u_interconnect.s_axi_wdata[0*32 +: 32]  = axi_bus.wdata;
                force u_dut.u_interconnect.s_axi_wstrb[0*4 +: 4]    = axi_bus.wstrb;
                force u_dut.u_interconnect.s_axi_wlast[0]           = axi_bus.wlast;
                force u_dut.u_interconnect.s_axi_wvalid[0]          = axi_bus.wvalid;
                force u_dut.u_interconnect.s_axi_bready[0]          = axi_bus.bready;
            end else begin
                release u_dut.u_interconnect.s_axi_wdata[0*32 +: 32];
                release u_dut.u_interconnect.s_axi_wstrb[0*4 +: 4];
                release u_dut.u_interconnect.s_axi_wlast[0];
                release u_dut.u_interconnect.s_axi_wvalid[0];
                release u_dut.u_interconnect.s_axi_bready[0];
            end

            if (axi_bus.arvalid) begin
                force u_dut.u_interconnect.s_axi_arid[0*8 +: 8]     = axi_bus.arid;
                force u_dut.u_interconnect.s_axi_araddr[0*32 +: 32] = axi_bus.araddr;
                force u_dut.u_interconnect.s_axi_arlen[0*8 +: 8]    = axi_bus.arlen;
                force u_dut.u_interconnect.s_axi_arsize[0*3 +: 3]   = axi_bus.arsize;
                force u_dut.u_interconnect.s_axi_arburst[0*2 +: 2]  = axi_bus.arburst;
                force u_dut.u_interconnect.s_axi_arvalid[0]         = axi_bus.arvalid;
                force u_dut.u_interconnect.s_axi_rready[0]          = axi_bus.rready;
            end else begin
                release u_dut.u_interconnect.s_axi_arid[0*8 +: 8];
                release u_dut.u_interconnect.s_axi_araddr[0*32 +: 32];
                release u_dut.u_interconnect.s_axi_arlen[0*8 +: 8];
                release u_dut.u_interconnect.s_axi_arsize[0*3 +: 3];
                release u_dut.u_interconnect.s_axi_arburst[0*2 +: 2];
                release u_dut.u_interconnect.s_axi_arvalid[0];
                release u_dut.u_interconnect.s_axi_rready[0];
            end
        end else begin
            // In CPU Integration Mode, release all forces unconditionally.
            // The CPU and CPU adapter natively drive interconnect Port S0!
            release u_dut.u_cpu.rst;
            release u_dut.u_interconnect.s_axi_awid[0*8 +: 8];
            release u_dut.u_interconnect.s_axi_awaddr[0*32 +: 32];
            release u_dut.u_interconnect.s_axi_awlen[0*8 +: 8];
            release u_dut.u_interconnect.s_axi_awsize[0*3 +: 3];
            release u_dut.u_interconnect.s_axi_awburst[0*2 +: 2];
            release u_dut.u_interconnect.s_axi_awvalid[0];

            release u_dut.u_interconnect.s_axi_wdata[0*32 +: 32];
            release u_dut.u_interconnect.s_axi_wstrb[0*4 +: 4];
            release u_dut.u_interconnect.s_axi_wlast[0];
            release u_dut.u_interconnect.s_axi_wvalid[0];
            release u_dut.u_interconnect.s_axi_bready[0];

            release u_dut.u_interconnect.s_axi_arid[0*8 +: 8];
            release u_dut.u_interconnect.s_axi_araddr[0*32 +: 32];
            release u_dut.u_interconnect.s_axi_arlen[0*8 +: 8];
            release u_dut.u_interconnect.s_axi_arsize[0*3 +: 3];
            release u_dut.u_interconnect.s_axi_arburst[0*2 +: 2];
            release u_dut.u_interconnect.s_axi_arvalid[0];
            release u_dut.u_interconnect.s_axi_rready[0];
        end
    end

    // =========================================================================
    // Protocol Assertions Binding
    // =========================================================================
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

    // =========================================================================
    // Virtual Interface Configuration and Test Execution
    // =========================================================================
    initial begin
        // Set virtual interfaces in config_db for all VIP agents
        uvm_config_db #(virtual axi_if)::set      (null, "*m_axi_agent*",       "vif", axi_bus);
        uvm_config_db #(virtual spi_if)::set      (null, "*m_spi_agent*",       "vif", spi_bus);
        uvm_config_db #(virtual uart_if)::set     (null, "*m_uart_agent*",      "vif", uart_bus);
        uvm_config_db #(virtual gpio_if)::set     (null, "*m_gpio_agent*",      "vif", gpio_bus);
        uvm_config_db #(virtual interrupt_if)::set(null, "*m_interrupt_agent*", "vif", irq_bus);
        uvm_config_db #(virtual clk_rst_if)::set  (null, "*m_clk_rst_agent*",   "vif", clk_rst_bus);

        // Waveform Dumping
`ifdef DUMP_FSDB
        $fsdbDumpfile("soc_uvm.fsdb");
        $fsdbDumpvars(0, tb_top);
`else
        $dumpfile("soc_uvm.vcd");
        $dumpvars(0, tb_top);
`endif

        // Execute UVM Test
        run_test();
    end

endmodule : tb_top
