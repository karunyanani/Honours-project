// =============================================================================
// File: clk_rst_seq_item.sv
// Description: UVM Sequence Item for Clock and Reset Operations
// =============================================================================

`ifndef CLK_RST_SEQ_ITEM_SV
`define CLK_RST_SEQ_ITEM_SV

class clk_rst_seq_item extends uvm_sequence_item;
    `uvm_object_utils(clk_rst_seq_item)

    typedef enum bit [2:0] {
        CLK_SET_FREQ     = 3'b000,
        RST_ASSERT       = 3'b001,
        RST_DEASSERT     = 3'b010,
        RST_PULSE        = 3'b011,
        RST_GLITCH       = 3'b100
    } clk_rst_op_e;

    rand clk_rst_op_e op_type;
    rand time         duration_ns;
    rand time         new_period_ns;

    constraint c_dur {
        duration_ns   inside {[10ns : 500ns]};
        new_period_ns inside {[5ns  : 100ns]};
    }

    function new(string name = "clk_rst_seq_item");
        super.new(name);
        op_type       = RST_PULSE;
        duration_ns   = 100ns;
        new_period_ns = 20ns;
    endfunction

    virtual function string convert2string();
        return $sformatf("CLK_RST_ITEM: OP=%s DURATION=%0tns PERIOD=%0tns",
            op_type.name(), duration_ns, new_period_ns);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        clk_rst_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return;
        super.do_copy(rhs);
        this.op_type       = rhs_.op_type;
        this.duration_ns   = rhs_.duration_ns;
        this.new_period_ns = rhs_.new_period_ns;
    endfunction

endclass : clk_rst_seq_item

`endif // CLK_RST_SEQ_ITEM_SV

