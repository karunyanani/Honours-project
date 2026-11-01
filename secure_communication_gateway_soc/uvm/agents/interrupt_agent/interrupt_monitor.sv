// =============================================================================
// File: interrupt_monitor.sv
// Description: UVM Monitor for Interrupt & Fault Recovery VIP
// =============================================================================

`ifndef INTERRUPT_MONITOR_SV
`define INTERRUPT_MONITOR_SV

class interrupt_monitor extends uvm_monitor;
    `uvm_component_utils(interrupt_monitor)

    virtual interrupt_if.monitor vif;
    interrupt_agent_config       cfg;
    uvm_analysis_port #(interrupt_seq_item) ap;

    function new(string name = "interrupt_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual interrupt_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        if (!uvm_config_db #(interrupt_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = interrupt_agent_config::type_id::create("default_irq_cfg");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        fork
            monitor_gpio_irq();
            monitor_timer_irq();
            monitor_wdt_fired();
        join
    endtask

    virtual task monitor_gpio_irq();
        interrupt_seq_item item;
        bit prev_state = 1'b0;

        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.gpio_irq !== prev_state) begin
                item = interrupt_seq_item::type_id::create("gpio_irq_event");
                item.source    = interrupt_seq_item::IRQ_SRC_GPIO;
                item.state     = vif.mon_cb.gpio_irq ? interrupt_seq_item::IRQ_ASSERTED : interrupt_seq_item::IRQ_DEASSERTED;
                item.timestamp = $time;
                prev_state     = vif.mon_cb.gpio_irq;
                ap.write(item);
            end
        end
    endtask

    virtual task monitor_timer_irq();
        interrupt_seq_item item;
        bit prev_state = 1'b0;

        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.timer_irq !== prev_state) begin
                item = interrupt_seq_item::type_id::create("timer_irq_event");
                item.source    = interrupt_seq_item::IRQ_SRC_TIMER;
                item.state     = vif.mon_cb.timer_irq ? interrupt_seq_item::IRQ_ASSERTED : interrupt_seq_item::IRQ_DEASSERTED;
                item.timestamp = $time;
                prev_state     = vif.mon_cb.timer_irq;
                ap.write(item);
            end
        end
    endtask

    virtual task monitor_wdt_fired();
        interrupt_seq_item item;
        bit prev_state = 1'b0;

        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.wdt_fired !== prev_state) begin
                item = interrupt_seq_item::type_id::create("wdt_fired_event");
                item.source    = interrupt_seq_item::IRQ_SRC_WDT;
                item.state     = vif.mon_cb.wdt_fired ? interrupt_seq_item::IRQ_ASSERTED : interrupt_seq_item::IRQ_DEASSERTED;
                item.timestamp = $time;
                prev_state     = vif.mon_cb.wdt_fired;
                ap.write(item);
            end
        end
    endtask

endclass : interrupt_monitor

`endif // INTERRUPT_MONITOR_SV

