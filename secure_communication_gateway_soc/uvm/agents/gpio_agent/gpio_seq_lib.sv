// =============================================================================
// File: gpio_seq_lib.sv
// Description: Pre-built UVM Sequence Library for GPIO VIP
// =============================================================================

`ifndef GPIO_SEQ_LIB_SV
`define GPIO_SEQ_LIB_SV

// Base GPIO sequence
class gpio_base_seq extends uvm_sequence #(gpio_seq_item);
    `uvm_object_utils(gpio_base_seq)

    function new(string name = "gpio_base_seq");
        super.new(name);
    endfunction

    virtual task set_pins(bit [7:0] val, bit [7:0] mask = 8'hFF, int delay = 2);
        gpio_seq_item item = gpio_seq_item::type_id::create("set_pins_item");
        start_item(item);
        item.op_type    = gpio_seq_item::GPIO_DRIVE_LEVEL;
        item.gpio_in    = val;
        item.pin_mask   = mask;
        item.post_delay = delay;
        finish_item(item);
    endtask

    virtual task pulse_pin(int pin_idx, int cycles = 5);
        gpio_seq_item item = gpio_seq_item::type_id::create("pulse_pin_item");
        start_item(item);
        item.op_type      = gpio_seq_item::GPIO_PULSE_PIN;
        item.gpio_in      = (8'h1 << pin_idx);
        item.pin_mask     = (8'h1 << pin_idx);
        item.pulse_cycles = cycles;
        item.post_delay   = 2;
        finish_item(item);
    endtask
endclass : gpio_base_seq

// Walking ones sequence
class gpio_walking_ones_seq extends gpio_base_seq;
    `uvm_object_utils(gpio_walking_ones_seq)

    function new(string name = "gpio_walking_ones_seq");
        super.new(name);
    endfunction

    virtual task body();
        for (int i = 0; i < 8; i++) begin
            set_pins(8'h1 << i, 8'hFF, 5);
        end
        set_pins(8'h00, 8'hFF, 5);
    endtask
endclass : gpio_walking_ones_seq

// Hardware sensor DRDY pulse sequence
class gpio_sensor_drdy_pulse_seq extends gpio_base_seq;
    `uvm_object_utils(gpio_sensor_drdy_pulse_seq)

    function new(string name = "gpio_sensor_drdy_pulse_seq");
        super.new(name);
    endfunction

    virtual task body();
        // Pulse pin 0 (standard sensor DRDY line)
        pulse_pin(0, 10);
    endtask
endclass : gpio_sensor_drdy_pulse_seq

`endif // GPIO_SEQ_LIB_SV

