// =============================================================================
// File: interrupt_agent.sv
// Description: UVM Agent for Interrupt & Fault Recovery VIP
// =============================================================================

`ifndef INTERRUPT_AGENT_SV
`define INTERRUPT_AGENT_SV

class interrupt_agent extends uvm_agent;
    `uvm_component_utils(interrupt_agent)

    interrupt_monitor       monitor;
    interrupt_agent_config  cfg;

    uvm_analysis_port #(interrupt_seq_item) ap;

    function new(string name = "interrupt_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(interrupt_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = interrupt_agent_config::type_id::create("cfg");
        end

        monitor = interrupt_monitor::type_id::create("monitor", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = monitor.ap;
    endfunction

endclass : interrupt_agent

`endif // INTERRUPT_AGENT_SV

