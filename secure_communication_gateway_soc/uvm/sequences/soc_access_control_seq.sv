// =============================================================================
// File: soc_access_control_seq.sv
// Description: UVM Sequence validating Access Control Matrix and DECERR responses
// =============================================================================

`ifndef SOC_ACCESS_CONTROL_SEQ_SV
`define SOC_ACCESS_CONTROL_SEQ_SV

class soc_access_control_seq extends soc_base_seq;
    `uvm_object_utils(soc_access_control_seq)

    function new(string name = "soc_access_control_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("SEC_SEQ", "Starting AXI Access Control & DECERR Verification...", UVM_LOW)

        // 1. DMA (ID=0x10) Accesses to DENIED Slaves (Must receive DECERR = 2'b11)
        // A. IMEM (0x00000000)
        axi_read(32'h0000_0000, rdata, resp, 8'h10);
        if (resp !== 2'b11)
            `uvm_error("SEC_SEQ", $sformatf("Expected DECERR on DMA->IMEM, got %0d", resp))

        // B. Timer (0x10000100)
        axi_read(32'h1000_0100, rdata, resp, 8'h10);
        if (resp !== 2'b11)
            `uvm_error("SEC_SEQ", $sformatf("Expected DECERR on DMA->Timer, got %0d", resp))

        // C. GPIO (0x10000200)
        axi_read(32'h1000_0200, rdata, resp, 8'h10);
        if (resp !== 2'b11)
            `uvm_error("SEC_SEQ", $sformatf("Expected DECERR on DMA->GPIO, got %0d", resp))

        // D. DMA Config Registers (0x10000400)
        axi_read(32'h1000_0400, rdata, resp, 8'h10);
        if (resp !== 2'b11)
            `uvm_error("SEC_SEQ", $sformatf("Expected DECERR on DMA->DMA_CFG, got %0d", resp))

        // E. Watchdog (0x10000600)
        axi_read(32'h1000_0600, rdata, resp, 8'h10);
        if (resp !== 2'b11)
            `uvm_error("SEC_SEQ", $sformatf("Expected DECERR on DMA->WDT, got %0d", resp))

        // 2. DMA (ID=0x10) Accesses to ALLOWED Slaves (Must receive OKAY = 2'b00)
        // A. Data Memory (0x00010000)
        axi_write(32'h0001_0100, 32'h55AA_55AA, 8'h10);
        axi_read (32'h0001_0100, rdata, resp, 8'h10);
        if (resp !== 2'b00 || rdata !== 32'h55AA_55AA)
            `uvm_error("SEC_SEQ", $sformatf("DMA->DMEM failed: resp=%0d data=0x%08h", resp, rdata))

        // B. AES Engine (0x10000300)
        axi_read(32'h1000_0314, rdata, resp, 8'h10); // AES_STATUS at offset 0x14
        if (resp !== 2'b00)
            `uvm_error("SEC_SEQ", $sformatf("DMA->AES status read failed: resp=%0d", resp))

        // C. SPI Controller (0x10000500)
        axi_read(32'h1000_0508, rdata, resp, 8'h10);
        if (resp !== 2'b00)
            `uvm_error("SEC_SEQ", $sformatf("DMA->SPI status read failed: resp=%0d", resp))

        // 3. Unmapped Address Access (0x20000000) - Both CPU and DMA must receive DECERR
        axi_read(32'h2000_0000, rdata, resp, 8'h00);
        if (resp !== 2'b11)
            `uvm_error("SEC_SEQ", $sformatf("Expected DECERR on unmapped CPU access, got %0d", resp))

        axi_read(32'h2000_0000, rdata, resp, 8'h10);
        if (resp !== 2'b11)
            `uvm_error("SEC_SEQ", $sformatf("Expected DECERR on unmapped DMA access, got %0d", resp))

        `uvm_info("SEC_SEQ", "AXI Access Control & DECERR Verification passed!", UVM_LOW)
    endtask

endclass : soc_access_control_seq

`endif // SOC_ACCESS_CONTROL_SEQ_SV

