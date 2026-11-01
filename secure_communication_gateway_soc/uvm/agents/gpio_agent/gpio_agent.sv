// =============================================================================
// File: gpio_agent.sv
// Description: UVM Agent encapsulating Driver, Monitor, Sequencer for GPIO VIP
// =============================================================================

`ifndef GPIO_AGENT_SV
`define GPIO_AGENT_SV

class gpio_agent extends uvm_agent;
    `uvm_component_utils(gpio_agent)

    gpio_driver        driver;
    gpio_monitor       monitor;
    gpio_sequencer     sequencer;
    gpio_agent_config  cfg;

    uvm_analysis_port #(gpio_seq_item) ap;

    function new(string name = "gpio_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(gpio_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = gpio_agent_config::type_id::create("cfg");
        end

        monitor = gpio_monitor::type_id::create("monitor", this);

        if (cfg.is_active == UVM_ACTIVE) begin
            driver    = gpio_driver::type_id::create("driver", this);
            sequencer = gpio_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = monitor.ap;
        if (cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass : gpio_agent

`endif // GPIO_AGENT_SV

