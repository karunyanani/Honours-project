// =============================================================================
// File: soc_base_seq.sv
// Description: UVM Base Sequence with Helper Read/Write Tasks
// =============================================================================

`ifndef SOC_BASE_SEQ_SV
`define SOC_BASE_SEQ_SV

class soc_base_seq extends uvm_sequence #(axi_seq_item);
    `uvm_object_utils(soc_base_seq)

    function new(string name = "soc_base_seq");
        super.new(name);
    endfunction

    virtual task axi_write(bit [31:0] addr, bit [31:0] data, bit [7:0] master_id = 8'h00);
        axi_seq_item req_item = axi_seq_item::type_id::create("axi_write_item");
        start_item(req_item);
        req_item.rw_type = axi_seq_item::AXI_WRITE;
        req_item.addr    = addr;
        req_item.data    = data;
        req_item.strb    = 4'hF;
        req_item.id      = master_id;
        finish_item(req_item);
    endtask

    virtual task axi_read(bit [31:0] addr, output bit [31:0] data, output bit [1:0] resp, bit [7:0] master_id = 8'h00);
        axi_seq_item req_item = axi_seq_item::type_id::create("axi_read_item");
        start_item(req_item);
        req_item.rw_type = axi_seq_item::AXI_READ;
        req_item.addr    = addr;
        req_item.id      = master_id;
        finish_item(req_item);
        data = req_item.data;
        resp = req_item.resp;
    endtask

endclass : soc_base_seq

`endif // SOC_BASE_SEQ_SV

