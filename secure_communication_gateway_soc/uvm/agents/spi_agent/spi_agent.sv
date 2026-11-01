// =============================================================================
// File: spi_agent.sv
// Description: UVM Agent for SPI Sensor Interface
// =============================================================================

`ifndef SPI_AGENT_SV
`define SPI_AGENT_SV

class spi_agent extends uvm_agent;
    `uvm_component_utils(spi_agent)

    spi_driver        driver;
    spi_monitor       monitor;
    spi_sequencer     sequencer;
    spi_agent_config  cfg;

    uvm_analysis_port #(spi_seq_item) ap;

    function new(string name = "spi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(spi_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = spi_agent_config::type_id::create("cfg");
        end

        monitor = spi_monitor::type_id::create("monitor", this);

        if (cfg.is_active == UVM_ACTIVE) begin
            driver    = spi_driver::type_id::create("driver", this);
            sequencer = spi_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = monitor.ap;
        if (cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : spi_agent

`endif // SPI_AGENT_SV
