// =============================================================================
// File: soc_stress_seq.sv
// Description: UVM Sequence validating Concurrency, Stress & High Bus Traffic
// =============================================================================

`ifndef SOC_STRESS_SEQ_SV
`define SOC_STRESS_SEQ_SV

class soc_stress_seq extends soc_base_seq;
    `uvm_object_utils(soc_stress_seq)

    function new(string name = "soc_stress_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("STRESS_SEQ", "Starting High-Throughput Interleaved Stress Sequence...", UVM_LOW)

        // Run 50 rapid interleaved operations alternating between CPU and DMA IDs
        for (int i = 0; i < 50; i++) begin
            bit [31:0] target_addr = 32'h0001_0000 + ((i & 32'h0000_003F) << 2);
            bit [31:0] test_data   = 32'hA000_0000 | i;

            // CPU Write
            axi_write(target_addr, test_data, 8'h01);

            // DMA Read
            axi_read(target_addr, rdata, resp, 8'h10);
            if (resp !== 2'b00 || rdata !== test_data) begin
                `uvm_error("STRESS_SEQ", $sformatf("Iteration %0d mismatch: exp=0x%08h act=0x%08h",
                    i, test_data, rdata))
            end
        end

        `uvm_info("STRESS_SEQ", "Interleaved Stress Sequence completed successfully!", UVM_LOW)
    endtask

endclass : soc_stress_seq

`endif // SOC_STRESS_SEQ_SV

