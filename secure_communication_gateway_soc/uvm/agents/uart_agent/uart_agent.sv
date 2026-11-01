// =============================================================================
// File: uart_agent.sv
// Description: UVM Agent for UART Interface (Supports Active & Passive Modes)
// =============================================================================

`ifndef UART_AGENT_SV
`define UART_AGENT_SV

class uart_agent extends uvm_agent;
    `uvm_component_utils(uart_agent)

    uart_driver        driver;
    uart_monitor       monitor;
    uart_sequencer     sequencer;
    uart_agent_config  cfg;

    uvm_analysis_port #(uart_seq_item) ap;

    function new(string name = "uart_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(uart_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = uart_agent_config::type_id::create("cfg");
        end

        monitor = uart_monitor::type_id::create("monitor", this);

        if (cfg.is_active == UVM_ACTIVE) begin
            driver    = uart_driver::type_id::create("driver", this);
            sequencer = uart_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = monitor.ap;
        if (cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : uart_agent

`endif // UART_AGENT_SV
