// =============================================================================
// File: soc_reg_access_seq.sv
// Description: UVM Sequence verifying registers across all 9 AXI slaves
// =============================================================================

`ifndef SOC_REG_ACCESS_SEQ_SV
`define SOC_REG_ACCESS_SEQ_SV

class soc_reg_access_seq extends soc_base_seq;
    `uvm_object_utils(soc_reg_access_seq)

    function new(string name = "soc_reg_access_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("REG_SEQ", "Starting Register Sanity Sequence across all 9 Slaves...", UVM_LOW)

        // 1. Data Memory (M1: 0x00010000)
        axi_write(32'h0001_0000, 32'hCAFE_BABE);
        axi_read (32'h0001_0000, rdata, resp);
        if (rdata !== 32'hCAFE_BABE || resp !== 2'b00)
            `uvm_error("REG_SEQ", $sformatf("DMEM readback mismatch: 0x%08h, resp: %0d", rdata, resp))

        // 2. UART (M2: 0x10000000)
        axi_write(32'h1000_000C, 32'd868); // BAUD_DIV (offset 0x0C)
        axi_read (32'h1000_000C, rdata, resp);
        if (rdata !== 32'd868)
            `uvm_error("REG_SEQ", $sformatf("UART BAUD_DIV mismatch: %0d", rdata))

        // 3. Timer (M3: 0x10000100)
        axi_write(32'h1000_0104, 32'd5000); // TIMER_LOAD (offset 0x04)
        axi_read (32'h1000_0104, rdata, resp);
        if (rdata !== 32'd5000)
            `uvm_error("REG_SEQ", $sformatf("Timer LOAD mismatch: %0d", rdata))

        // 4. GPIO (M4: 0x10000200)
        axi_write(32'h1000_0200, 32'h0000_00A5); // GPIO_DATA_OUT (offset 0x00)
        axi_read (32'h1000_0200, rdata, resp);
        if (rdata[7:0] !== 8'hA5)
            `uvm_error("REG_SEQ", $sformatf("GPIO_OUT mismatch: 0x%02h", rdata[7:0]))

        // 5. AES Engine (M5: 0x10000300)
        axi_write(32'h1000_0300, 32'h0001_0203); // KEY0
        axi_write(32'h1000_0304, 32'h0405_0607); // KEY1
        axi_write(32'h1000_0308, 32'h0809_0A0B); // KEY2
        axi_write(32'h1000_030C, 32'h0C0D_0E0F); // KEY3
        axi_read (32'h1000_0314, rdata, resp);   // STATUS (offset 0x14)
        if (resp !== 2'b00)
            `uvm_error("REG_SEQ", "AES STATUS read failed")

        // 6. DMA Configuration Registers (M6: 0x10000400)
        axi_write(32'h1000_0400, 32'h1000_0500); // SRC (SPI)
        axi_write(32'h1000_0404, 32'h1000_0318); // DST (AES_DATA_IN0)
        axi_write(32'h1000_0408, 32'd16);        // LEN
        axi_read (32'h1000_0408, rdata, resp);
        if (rdata !== 32'd16)
            `uvm_error("REG_SEQ", $sformatf("DMA LEN mismatch: %0d", rdata))

        // 7. SPI Controller (M7: 0x10000500)
        axi_write(32'h1000_050C, 32'h0000_0001); // SPI_CTRL (offset 0x0C)
        axi_read (32'h1000_050C, rdata, resp);
        if (rdata[0] !== 1'b1)
            `uvm_error("REG_SEQ", "SPI_CTRL enable mismatch")

        // 8. Watchdog Timer (M8: 0x10000600)
        axi_write(32'h1000_0604, 32'd50000); // WDT_TIMEOUT (offset 0x04)
        axi_read (32'h1000_0604, rdata, resp);
        if (rdata !== 32'd50000)
            `uvm_error("REG_SEQ", $sformatf("WDT TIMEOUT mismatch: %0d", rdata))

        `uvm_info("REG_SEQ", "Register Sanity Sequence completed successfully!", UVM_LOW)
    endtask

endclass : soc_reg_access_seq

`endif // SOC_REG_ACCESS_SEQ_SV

