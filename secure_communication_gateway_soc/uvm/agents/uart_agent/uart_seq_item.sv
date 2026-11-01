// =============================================================================
// File: uart_seq_item.sv
// Description: UVM Sequence Item for UART Transactions
// =============================================================================

`ifndef UART_SEQ_ITEM_SV
`define UART_SEQ_ITEM_SV

class uart_seq_item extends uvm_sequence_item;
    `uvm_object_utils(uart_seq_item)

    typedef enum bit {
        UART_TX = 1'b0, // Monitor observed on SoC uart_tx
        UART_RX = 1'b1  // Driver injecting into SoC uart_rx
    } uart_dir_e;

    rand bit [7:0]   data_byte;
    rand int         inter_byte_delay; // Delay in bit periods
    rand uart_dir_e  direction;

    // Error injection flags
    rand bit         inject_frame_error;
    rand bit         inject_parity_error;

    // Sampled status
    bit              frame_error;
    bit              parity_error;

    constraint c_default {
        inter_byte_delay inside {[0:10]};
        inject_frame_error  dist { 1'b0 := 95, 1'b1 := 5 };
        inject_parity_error dist { 1'b0 := 98, 1'b1 := 2 };
    }

    function new(string name = "uart_seq_item");
        super.new(name);
        direction           = UART_RX;
        data_byte           = 8'h00;
        inter_byte_delay    = 1;
        inject_frame_error  = 0;
        inject_parity_error = 0;
    endfunction

    virtual function string convert2string();
        return $sformatf("UART_ITEM: DIR=%s DATA=0x%02h ('%c') ERR(FRAME=%0b, PARITY=%0b)",
            direction.name(), data_byte, (data_byte >= 32 && data_byte <= 126) ? data_byte : 8'h2E,
            frame_error, parity_error);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        uart_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return;
        super.do_copy(rhs);
        this.data_byte           = rhs_.data_byte;
        this.inter_byte_delay    = rhs_.inter_byte_delay;
        this.direction           = rhs_.direction;
        this.inject_frame_error  = rhs_.inject_frame_error;
        this.inject_parity_error = rhs_.inject_parity_error;
        this.frame_error         = rhs_.frame_error;
        this.parity_error        = rhs_.parity_error;
    endfunction

endclass : uart_seq_item

`endif // UART_SEQ_ITEM_SV
