// =============================================================================
// File: axi_agent.sv
// Description: UVM Agent for AXI4 Bus Transactions (Supports Master & Slave Roles)
// =============================================================================

`ifndef AXI_AGENT_SV
`define AXI_AGENT_SV

class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)

    axi_driver        driver;
    axi_slave_driver  slave_driver;
    axi_monitor       monitor;
    axi_sequencer     sequencer;
    axi_agent_config  cfg;

    uvm_analysis_port #(axi_seq_item) ap;

    function new(string name = "axi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(axi_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = axi_agent_config::type_id::create("cfg");
        end

        monitor = axi_monitor::type_id::create("monitor", this);

        if (cfg.is_active == UVM_ACTIVE) begin
            if (cfg.role == axi_agent_config::AXI_ROLE_SLAVE) begin
                slave_driver = axi_slave_driver::type_id::create("slave_driver", this);
            end else begin
                driver    = axi_driver::type_id::create("driver", this);
                sequencer = axi_sequencer::type_id::create("sequencer", this);
            end
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = monitor.ap;
        if (cfg.is_active == UVM_ACTIVE && cfg.role == axi_agent_config::AXI_ROLE_MASTER) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : axi_agent

`endif // AXI_AGENT_SV
