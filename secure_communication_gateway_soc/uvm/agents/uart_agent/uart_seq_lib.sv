// =============================================================================
// File: uart_seq_lib.sv
// Description: UVM Sequence Library for UART Verification IP
// =============================================================================

`ifndef UART_SEQ_LIB_SV
`define UART_SEQ_LIB_SV

class uart_base_seq extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_base_seq)

    function new(string name = "uart_base_seq");
        super.new(name);
    endfunction

    virtual task send_byte(bit [7:0] data, int delay = 1);
        uart_seq_item item = uart_seq_item::type_id::create("uart_byte_item");
        start_item(item);
        item.direction        = uart_seq_item::UART_RX;
        item.data_byte        = data;
        item.inter_byte_delay = delay;
        finish_item(item);
    endtask

    virtual task send_string(string str);
        for (int i = 0; i < str.len(); i++) begin
            send_byte(str[i], 1);
        end
    endtask
endclass : uart_base_seq

class uart_rx_command_seq extends uart_base_seq;
    `uvm_object_utils(uart_rx_command_seq)

    function new(string name = "uart_rx_command_seq");
        super.new(name);
    endfunction

    virtual task body();
        send_string("PING\r\n");
    endtask
endclass : uart_rx_command_seq

`endif // UART_SEQ_LIB_SV

