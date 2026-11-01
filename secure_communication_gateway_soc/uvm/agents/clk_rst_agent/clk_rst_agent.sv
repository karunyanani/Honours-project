// =============================================================================
// File: clk_rst_agent.sv
// Description: UVM Agent for Clock and Reset Generation VIP
// =============================================================================

`ifndef CLK_RST_AGENT_SV
`define CLK_RST_AGENT_SV

class clk_rst_agent extends uvm_agent;
    `uvm_component_utils(clk_rst_agent)

    clk_rst_driver        driver;
    clk_rst_sequencer     sequencer;
    clk_rst_agent_config  cfg;

    function new(string name = "clk_rst_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(clk_rst_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = clk_rst_agent_config::type_id::create("cfg");
        end

        driver    = clk_rst_driver::type_id::create("driver", this);
        sequencer = clk_rst_sequencer::type_id::create("sequencer", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass : clk_rst_agent

`endif // CLK_RST_AGENT_SV

