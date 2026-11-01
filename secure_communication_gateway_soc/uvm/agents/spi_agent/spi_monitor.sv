// =============================================================================
// File: spi_monitor.sv
// Description: UVM Monitor for SPI Interface capturing MOSI & MISO
// =============================================================================

`ifndef SPI_MONITOR_SV
`define SPI_MONITOR_SV

class spi_monitor extends uvm_monitor;
    `uvm_component_utils(spi_monitor)

    virtual spi_if.monitor vif;
    spi_agent_config       cfg;
    uvm_analysis_port #(spi_seq_item) ap;

    function new(string name = "spi_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        if (!uvm_config_db #(spi_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = spi_agent_config::type_id::create("default_spi_cfg");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        spi_seq_item item;
        bit [7:0] miso_byte;
        bit [7:0] mosi_byte;

        forever begin
            wait (vif.cs_n === 1'b0);
            for (int i = 7; i >= 0; i--) begin
                @(posedge vif.sclk);
                miso_byte[i] = vif.miso;
                mosi_byte[i] = vif.mosi;
            end
            wait (vif.cs_n === 1'b1);

            item = spi_seq_item::type_id::create("spi_mon_item");
            item.data_byte   = miso_byte;
            item.mosi_cmd    = mosi_byte;
            item.assert_drdy = vif.sensor_drdy;

            ap.write(item);
        end
    endtask

endclass : spi_monitor

`endif // SPI_MONITOR_SV
