// =============================================================================
// File: gpio_seq_item.sv
// Description: UVM Sequence Item for GPIO Pin Driving and Edge Event Tracking
// =============================================================================

`ifndef GPIO_SEQ_ITEM_SV
`define GPIO_SEQ_ITEM_SV

class gpio_seq_item extends uvm_sequence_item;
    `uvm_object_utils(gpio_seq_item)

    typedef enum bit [1:0] {
        GPIO_DRIVE_LEVEL = 2'b00,
        GPIO_PULSE_PIN   = 2'b01,
        GPIO_SAMPLE_ONLY = 2'b10
    } gpio_op_e;

    rand gpio_op_e op_type;
    rand bit [7:0] gpio_in;      // Value driven onto gpio_in lines
    rand bit [7:0] pin_mask;     // Bitmask of pins to modify
    rand int       pulse_cycles; // Hold duration in clock cycles
    rand int       post_delay;   // Delay after transaction

    // Sampled feedback from DUT
    bit [7:0] gpio_out;
    bit [7:0] gpio_oe;
    bit       gpio_irq;

    constraint c_default {
        pulse_cycles inside {[1:50]};
        post_delay   inside {[0:20]};
    }

    function new(string name = "gpio_seq_item");
        super.new(name);
        op_type      = GPIO_DRIVE_LEVEL;
        gpio_in      = 8'h00;
        pin_mask     = 8'hFF;
        pulse_cycles = 5;
        post_delay   = 2;
    endfunction

    virtual function string convert2string();
        return $sformatf("GPIO_ITEM: OP=%s IN=0x%02h MASK=0x%02h OUT=0x%02h OE=0x%02h IRQ=%0b",
            op_type.name(), gpio_in, pin_mask, gpio_out, gpio_oe, gpio_irq);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        gpio_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return;
        super.do_copy(rhs);
        this.op_type      = rhs_.op_type;
        this.gpio_in      = rhs_.gpio_in;
        this.pin_mask     = rhs_.pin_mask;
        this.pulse_cycles = rhs_.pulse_cycles;
        this.post_delay   = rhs_.post_delay;
        this.gpio_out     = rhs_.gpio_out;
        this.gpio_oe      = rhs_.gpio_oe;
        this.gpio_irq     = rhs_.gpio_irq;
    endfunction

endclass : gpio_seq_item

`endif // GPIO_SEQ_ITEM_SV

