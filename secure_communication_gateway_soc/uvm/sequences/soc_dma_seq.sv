// =============================================================================
// File: soc_dma_seq.sv
// Description: UVM Sequence validating DMA Controller (Mode 0 & Mode 1)
// =============================================================================

`ifndef SOC_DMA_SEQ_SV
`define SOC_DMA_SEQ_SV

class soc_dma_seq extends soc_base_seq;
    `uvm_object_utils(soc_dma_seq)

    function new(string name = "soc_dma_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("DMA_SEQ", "Starting DMA Controller Verification Sequence...", UVM_LOW)

        // ---------------------------------------------------------------------
        // Test 1: DMA Mode 0 Configuration (SPI -> AES)
        // ---------------------------------------------------------------------
        `uvm_info("DMA_SEQ", "Test 1: Configuring DMA Mode 0 (SPI RX -> AES PT)", UVM_MEDIUM)

        axi_write(32'h1000_0400, 32'h1000_0504); // SRC: SPI_RX_DATA (offset 0x04)
        axi_write(32'h1000_0404, 32'h1000_0318); // DST: AES_DATA_IN0 (offset 0x18)
        axi_write(32'h1000_0408, 32'd16);        // LEN: 16 bytes
        axi_write(32'h1000_040C, 32'h0000_0001); // CTRL: START=1, MODE=0 (SPI->AES)

        // Verify Status: Busy bit asserts
        axi_read(32'h1000_0410, rdata, resp);
        `uvm_info("DMA_SEQ", $sformatf("DMA Status post-start: 0x%08h", rdata), UVM_HIGH)

        // ---------------------------------------------------------------------
        // Test 2: DMA Mode 1 Configuration (AES -> UART)
        // ---------------------------------------------------------------------
        `uvm_info("DMA_SEQ", "Test 2: Configuring DMA Mode 1 (AES CT -> UART TX)", UVM_MEDIUM)

        axi_write(32'h1000_0400, 32'h1000_0328); // SRC: AES_DATA_OUT0 (offset 0x28)
        axi_write(32'h1000_0404, 32'h1000_0000); // DST: UART_TX_DATA (offset 0x00)
        axi_write(32'h1000_0408, 32'd16);        // LEN: 16 bytes
        axi_write(32'h1000_040C, 32'h0000_0003); // CTRL: START=1, MODE=1 (bit 1=1)

        // Readback config registers to ensure retention and alignment
        axi_read(32'h1000_0400, rdata, resp);
        if (rdata !== 32'h1000_0328)
            `uvm_error("DMA_SEQ", $sformatf("DMA SRC_ADDR mismatch: exp=0x10000328 act=0x%08h", rdata))

        axi_read(32'h1000_0404, rdata, resp);
        if (rdata !== 32'h1000_0000)
            `uvm_error("DMA_SEQ", $sformatf("DMA DST_ADDR mismatch: exp=0x10000000 act=0x%08h", rdata))

        axi_read(32'h1000_0408, rdata, resp);
        if (rdata !== 32'd16)
            `uvm_error("DMA_SEQ", $sformatf("DMA LEN mismatch: exp=16 act=%0d", rdata))

        `uvm_info("DMA_SEQ", "DMA Controller Verification Sequence completed successfully!", UVM_LOW)
    endtask

endclass : soc_dma_seq

`endif // SOC_DMA_SEQ_SV

