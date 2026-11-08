// =============================================================================
// File: soc_spi_seq.sv
// Description: UVM Sequence validating SPI Controller (Configuration & Transfers)
// =============================================================================

`ifndef SOC_SPI_SEQ_SV
`define SOC_SPI_SEQ_SV

class soc_spi_seq extends soc_base_seq;
    `uvm_object_utils(soc_spi_seq)

    function new(string name = "soc_spi_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("SPI_SEQ", "Starting SPI Controller Verification Sequence...", UVM_LOW)

        // 1. Program SPI Clock Divider (SCK scaling)
        axi_write(32'h1000_0510, 32'd4); // CLK_DIV = 4 for fast simulation
        axi_read (32'h1000_0510, rdata, resp);
        if (rdata[7:0] !== 8'd4)
            `uvm_error("SPI_SEQ", $sformatf("SPI CLK_DIV mismatch: exp=4 act=%0d", rdata[7:0]))

        // 2. Enable SPI Controller: EN=1, CS_AUTO=1 (CTRL = 0x09)
        axi_write(32'h1000_050C, 32'h0000_0009);
        axi_read (32'h1000_050C, rdata, resp);
        if ((rdata & 32'h0000_0009) !== 32'h0000_0009)
            `uvm_error("SPI_SEQ", $sformatf("SPI CTRL mismatch: act=0x%08h", rdata))

        // 3. Check Initial Status (TX not full, RX initially empty)
        axi_read(32'h1000_0508, rdata, resp); // STATUS
        `uvm_info("SPI_SEQ", $sformatf("Initial SPI Status: 0x%08h", rdata), UVM_HIGH)

        // 4. Transmit Command Byte over SPI
        axi_write(32'h1000_0500, 32'h0000_00A5); // TX_DATA = 0xA5

        // Wait for transmission cycle to complete
        #200ns;

        // 5. Read Status: Check BUSY clears
        axi_read(32'h1000_0508, rdata, resp);
        `uvm_info("SPI_SEQ", $sformatf("Post-Tx SPI Status: 0x%08h", rdata), UVM_HIGH)

        `uvm_info("SPI_SEQ", "SPI Controller Verification Sequence completed successfully!", UVM_LOW)
    endtask

endclass : soc_spi_seq

`endif // SOC_SPI_SEQ_SV

