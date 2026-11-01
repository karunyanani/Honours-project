// =============================================================================
// File: clk_rst_seq_lib.sv
// Description: UVM Sequence Library for Clock and Reset Operations
// =============================================================================

`ifndef CLK_RST_SEQ_LIB_SV
`define CLK_RST_SEQ_LIB_SV

class clk_rst_power_on_seq extends uvm_sequence #(clk_rst_seq_item);
    `uvm_object_utils(clk_rst_power_on_seq)

    time reset_duration = 100ns;

    function new(string name = "clk_rst_power_on_seq");
        super.new(name);
    endfunction

    virtual task body();
        clk_rst_seq_item item = clk_rst_seq_item::type_id::create("por_item");
        start_item(item);
        item.op_type     = clk_rst_seq_item::RST_PULSE;
        item.duration_ns = reset_duration;
        finish_item(item);
    endtask
endclass : clk_rst_power_on_seq

class clk_rst_warm_reset_seq extends uvm_sequence #(clk_rst_seq_item);
    `uvm_object_utils(clk_rst_warm_reset_seq)

    time reset_duration = 40ns;

    function new(string name = "clk_rst_warm_reset_seq");
        super.new(name);
    endfunction

    virtual task body();
        clk_rst_seq_item item = clk_rst_seq_item::type_id::create("warm_rst_item");
        start_item(item);
        item.op_type     = clk_rst_seq_item::RST_PULSE;
        item.duration_ns = reset_duration;
        finish_item(item);
    endtask
endclass : clk_rst_warm_reset_seq

`endif // CLK_RST_SEQ_LIB_SV

