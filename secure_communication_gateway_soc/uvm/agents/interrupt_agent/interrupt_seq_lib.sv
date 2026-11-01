// =============================================================================
// File: interrupt_seq_lib.sv
// Description: UVM Sequence Library for Interrupt & Fault Recovery VIP
// =============================================================================

`ifndef INTERRUPT_SEQ_LIB_SV
`define INTERRUPT_SEQ_LIB_SV

class interrupt_wait_irq_seq extends uvm_sequence #(interrupt_seq_item);
    `uvm_object_utils(interrupt_wait_irq_seq)

    rand interrupt_seq_item::irq_source_e expected_source;
    int timeout_cycles = 10000;

    function new(string name = "interrupt_wait_irq_seq");
        super.new(name);
        expected_source = interrupt_seq_item::IRQ_SRC_TIMER;
    endfunction

    virtual task body();
        `uvm_info("IRQ_SEQ", $sformatf("Waiting for interrupt source: %s", expected_source.name()), UVM_MEDIUM)
    endtask
endclass : interrupt_wait_irq_seq

`endif // INTERRUPT_SEQ_LIB_SV

