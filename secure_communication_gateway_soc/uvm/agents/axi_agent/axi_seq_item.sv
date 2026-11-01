// =============================================================================
// File: axi_seq_item.sv
// Description: UVM Sequence Item for AXI4 Bus Transactions
// =============================================================================

`ifndef AXI_SEQ_ITEM_SV
`define AXI_SEQ_ITEM_SV

class axi_seq_item extends uvm_sequence_item;
    `uvm_object_utils(axi_seq_item)

    typedef enum bit { AXI_READ = 1'b0, AXI_WRITE = 1'b1 } axi_rw_e;

    rand bit [31:0]        addr;
    rand bit [31:0]        data;
    rand bit [3:0]         strb;
    rand axi_rw_e          rw_type;
    rand bit [7:0]         id;
    rand bit [7:0]         len;
    rand bit [2:0]         size;
    rand bit [1:0]         burst;

    // Response
    bit [1:0]              resp; // 2'b00: OKAY, 2'b10: SLVERR, 2'b11: DECERR

    constraint c_default_burst {
        len   == 8'd0;       // Single beat
        size  == 3'b010;     // 4 bytes
        burst == 2'b01;      // INCR
        strb  == 4'b1111;    // Full word
    }

    constraint c_aligned_addr {
        addr[1:0] == 2'b00;  // 32-bit word aligned
    }

    function new(string name = "axi_seq_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("AXI_ITEM: [%s] ID=0x%02h ADDR=0x%08h DATA=0x%08h STRB=0x%1h RESP=0x%1h",
            rw_type.name(), id, addr, data, strb, resp);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        axi_seq_item rhs_;
        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal("DO_COPY", "Cast failed")
            return;
        end
        super.do_copy(rhs);
        this.addr    = rhs_.addr;
        this.data    = rhs_.data;
        this.strb    = rhs_.strb;
        this.rw_type = rhs_.rw_type;
        this.id      = rhs_.id;
        this.len     = rhs_.len;
        this.size    = rhs_.size;
        this.burst   = rhs_.burst;
        this.resp    = rhs_.resp;
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (super.do_compare(rhs, comparer) &&
                (this.addr    == rhs_.addr)    &&
                (this.data    == rhs_.data)    &&
                (this.strb    == rhs_.strb)    &&
                (this.rw_type == rhs_.rw_type) &&
                (this.id      == rhs_.id)      &&
                (this.resp    == rhs_.resp));
    endfunction

endclass : axi_seq_item

`endif // AXI_SEQ_ITEM_SV

