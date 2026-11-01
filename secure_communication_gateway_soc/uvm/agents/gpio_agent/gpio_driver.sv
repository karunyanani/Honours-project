// =============================================================================
// File: gpio_driver.sv
// Description: UVM Driver for GPIO VIP
// =============================================================================

`ifndef GPIO_DRIVER_SV
`define GPIO_DRIVER_SV

class gpio_driver extends uvm_driver #(gpio_seq_item);
    `uvm_component_utils(gpio_driver)

    virtual gpio_if.driver vif;
    gpio_agent_config      cfg;
    bit [7:0]              cur_pins;

    function new(string name = "gpio_driver", uvm_component parent = null);
        super.new(name, parent);
        cur_pins = 8'h00;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual gpio_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        if (!uvm_config_db #(gpio_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = gpio_agent_config::type_id::create("default_gpio_cfg");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        cur_pins = cfg.default_in;
        vif.drv_cb.gpio_in <= cur_pins;
        wait (vif.rst === 1'b0);

        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task drive_item(gpio_seq_item item);
        case (item.op_type)
            gpio_seq_item::GPIO_DRIVE_LEVEL: begin
                cur_pins = (cur_pins & ~item.pin_mask) | (item.gpio_in & item.pin_mask);
                @(vif.drv_cb);
                vif.drv_cb.gpio_in <= cur_pins;
            end

            gpio_seq_item::GPIO_PULSE_PIN: begin
                bit [7:0] pulse_high = cur_pins | (item.gpio_in & item.pin_mask);
                bit [7:0] pulse_low  = cur_pins & ~(item.gpio_in & item.pin_mask);

                // Drive pulse
                @(vif.drv_cb);
                vif.drv_cb.gpio_in <= pulse_high;
                repeat (item.pulse_cycles) @(vif.drv_cb);
                vif.drv_cb.gpio_in <= pulse_low;
                cur_pins = pulse_low;
            end

            gpio_seq_item::GPIO_SAMPLE_ONLY: begin
                @(vif.drv_cb);
            end
        endcase

        if (item.post_delay > 0) begin
            repeat (item.post_delay) @(vif.drv_cb);
        end

        // Sample back pins
        item.gpio_out = vif.drv_cb.gpio_out;
        item.gpio_oe  = vif.drv_cb.gpio_oe;
        item.gpio_irq = vif.drv_cb.gpio_irq;
    endtask

endclass : gpio_driver

`endif // GPIO_DRIVER_SV

