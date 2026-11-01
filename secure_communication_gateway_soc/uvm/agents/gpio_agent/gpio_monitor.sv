// =============================================================================
// File: gpio_monitor.sv
// Description: UVM Monitor for GPIO VIP capturing Pin State Changes & IRQs
// =============================================================================

`ifndef GPIO_MONITOR_SV
`define GPIO_MONITOR_SV

class gpio_monitor extends uvm_monitor;
    `uvm_component_utils(gpio_monitor)

    virtual gpio_if.monitor vif;
    uvm_analysis_port #(gpio_seq_item) ap;

    function new(string name = "gpio_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual gpio_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit [7:0] prev_in  = 8'h00;
        bit [7:0] prev_out = 8'h00;
        bit [7:0] prev_oe  = 8'h00;
        bit       prev_irq = 1'b0;

        gpio_seq_item item;

        forever begin
            @(vif.mon_cb);
            if ((vif.mon_cb.gpio_in  !== prev_in)  ||
                (vif.mon_cb.gpio_out !== prev_out) ||
                (vif.mon_cb.gpio_oe  !== prev_oe)  ||
                (vif.mon_cb.gpio_irq !== prev_irq)) begin

                item = gpio_seq_item::type_id::create("gpio_mon_item");
                item.gpio_in  = vif.mon_cb.gpio_in;
                item.gpio_out = vif.mon_cb.gpio_out;
                item.gpio_oe  = vif.mon_cb.gpio_oe;
                item.gpio_irq = vif.mon_cb.gpio_irq;

                prev_in  = vif.mon_cb.gpio_in;
                prev_out = vif.mon_cb.gpio_out;
                prev_oe  = vif.mon_cb.gpio_oe;
                prev_irq = vif.mon_cb.gpio_irq;

                ap.write(item);
            end
        end
    endtask

endclass : gpio_monitor

`endif // GPIO_MONITOR_SV

