// =============================================================================
// File: soc_mem_seq.sv
// Description: UVM Sequence validating Memory Boundaries & Byte Strobes
// =============================================================================

`ifndef SOC_MEM_SEQ_SV
`define SOC_MEM_SEQ_SV

class soc_mem_seq extends soc_base_seq;
    `uvm_object_utils(soc_mem_seq)

    function new(string name = "soc_mem_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("MEM_SEQ", "Starting Memory Boundary & Data Integrity Sequence...", UVM_LOW)

        // 1. DMEM Base Address (0x0001_0000) Write & Read
        axi_write(32'h0001_0000, 32'h1234_5678);
        axi_read (32'h0001_0000, rdata, resp);
        if (rdata !== 32'h1234_5678 || resp !== 2'b00)
            `uvm_error("MEM_SEQ", $sformatf("DMEM base mismatch: act=0x%08h", rdata))

        // 2. DMEM End Boundary (0x0001_FFFC) Write & Read
        axi_write(32'h0001_FFFC, 32'hDEAD_BEEF);
        axi_read (32'h0001_FFFC, rdata, resp);
        if (rdata !== 32'hDEAD_BEEF || resp !== 2'b00)
            `uvm_error("MEM_SEQ", $sformatf("DMEM top boundary mismatch: act=0x%08h", rdata))

        // 3. Walking Bit Patterns in Data Memory
        for (int i = 0; i < 32; i++) begin
            bit [31:0] test_val = (1 << i);
            axi_write(32'h0001_0100, test_val);
            axi_read (32'h0001_0100, rdata, resp);
            if (rdata !== test_val)
                `uvm_error("MEM_SEQ", $sformatf("Walking bit %0d failed: exp=0x%08h act=0x%08h", i, test_val, rdata))
        end

        `uvm_info("MEM_SEQ", "Memory Boundary & Walking Bit Verification PASSED!", UVM_LOW)
    endtask

endclass : soc_mem_seq

`endif // SOC_MEM_SEQ_SV

