// =============================================================================
// File: axi_seq_lib.sv
// Description: Pre-built UVM Sequence Library for AXI4 VIP
// =============================================================================

`ifndef AXI_SEQ_LIB_SV
`define AXI_SEQ_LIB_SV

class axi_random_burst_seq extends soc_base_seq;
    `uvm_object_utils(axi_random_burst_seq)

    rand bit [31:0] base_addr;
    rand int        burst_count;

    constraint c_burst {
        burst_count inside {[4:16]};
        base_addr[1:0] == 2'b00;
        base_addr inside {[32'h0001_0000 : 32'h0001_0FFF]}; // DMEM
    }

    function new(string name = "axi_random_burst_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] wr_data;
        bit [31:0] rd_data;
        bit [1:0]  resp;

        for (int i = 0; i < burst_count; i++) begin
            wr_data = $urandom();
            axi_write(base_addr + (i * 4), wr_data);
            axi_read (base_addr + (i * 4), rd_data, resp);
            if (rd_data !== wr_data || resp !== 2'b00) begin
                `uvm_error("AXI_BURST_FAIL", $sformatf("Addr 0x%08h Exp=0x%08h Act=0x%08h Resp=0x%02h",
                    base_addr + (i * 4), wr_data, rd_data, resp))
            end
        end
    endtask
endclass : axi_random_burst_seq

// Access control security violation test sequence (attempts unauthorized DMA master access)
class axi_security_violation_seq extends soc_base_seq;
    `uvm_object_utils(axi_security_violation_seq)

    function new(string name = "axi_security_violation_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rd_data;
        bit [1:0]  resp;

        `uvm_info("SEC_SEQ", "Testing DMA Master unauthorized access to IMEM & WDT...", UVM_LOW)

        // Attempt read on IMEM with DMA Master ID (0x10)
        axi_read(32'h0000_0000, rd_data, resp, 8'h10);
        if (resp !== 2'b11) begin // Must be DECERR
            `uvm_error("SEC_VIOLATION", $sformatf("Expected DECERR for DMA IMEM read, got resp=0x%01h", resp))
        end else begin
            `uvm_info("SEC_PASS", "Verified DECERR returned for DMA access to IMEM", UVM_MEDIUM)
        end

        // Attempt write on WDT with DMA Master ID (0x10)
        axi_write(32'h1000_0600, 32'hDEAD_BEEF, 8'h10);
        // Note: write response checked via driver resp
    endtask
endclass : axi_security_violation_seq

`endif // AXI_SEQ_LIB_SV

