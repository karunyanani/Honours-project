// =============================================================================
// File: interrupt_seq_item.sv
// Description: UVM Sequence Item for Interrupt and Fault Recovery Events
// =============================================================================

`ifndef INTERRUPT_SEQ_ITEM_SV
`define INTERRUPT_SEQ_ITEM_SV

class interrupt_seq_item extends uvm_sequence_item;
    `uvm_object_utils(interrupt_seq_item)

    typedef enum bit [1:0] {
        IRQ_SRC_GPIO  = 2'b00,
        IRQ_SRC_TIMER = 2'b01,
        IRQ_SRC_WDT   = 2'b10
    } irq_source_e;

    typedef enum bit {
        IRQ_ASSERTED   = 1'b1,
        IRQ_DEASSERTED = 1'b0
    } irq_state_e;

    irq_source_e source;
    irq_state_e  state;
    time         timestamp;
    int          pulse_width_cycles;

    function new(string name = "interrupt_seq_item");
        super.new(name);
        source    = IRQ_SRC_GPIO;
        state     = IRQ_ASSERTED;
        timestamp = 0;
    endfunction

    virtual function string convert2string();
        return $sformatf("INTERRUPT_ITEM: SRC=%s STATE=%s TIME=%0t WIDTH=%0d cycles",
            source.name(), state.name(), timestamp, pulse_width_cycles);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        interrupt_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return;
        super.do_copy(rhs);
        this.source             = rhs_.source;
        this.state              = rhs_.state;
        this.timestamp          = rhs_.timestamp;
        this.pulse_width_cycles = rhs_.pulse_width_cycles;
    endfunction

endclass : interrupt_seq_item

`endif // INTERRUPT_SEQ_ITEM_SV

