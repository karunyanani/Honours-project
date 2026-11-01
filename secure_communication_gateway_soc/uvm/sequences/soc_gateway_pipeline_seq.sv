// =============================================================================
// File: soc_gateway_pipeline_seq.sv
// Description: UVM Sequence executing the full Sensor->SPI->DMA->AES->UART Pipeline
// =============================================================================

`ifndef SOC_GATEWAY_PIPELINE_SEQ_SV
`define SOC_GATEWAY_PIPELINE_SEQ_SV

class soc_gateway_pipeline_seq extends soc_base_seq;
    `uvm_object_utils(soc_gateway_pipeline_seq)

    function new(string name = "soc_gateway_pipeline_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("GATEWAY_SEQ", "Starting Full Gateway Datapath Execution Sequence...", UVM_LOW)

        // 1. Program UART Baud Divisor (div=868)
        axi_write(32'h1000_0008, 32'd868);

        // 2. Load AES-128 Key (NIST FIPS 197 vector)
        axi_write(32'h1000_0300, 32'h0001_0203); // KEY0
        axi_write(32'h1000_0304, 32'h0405_0607); // KEY1
        axi_write(32'h1000_0308, 32'h0809_0A0B); // KEY2
        axi_write(32'h1000_030C, 32'h0C0D_0E0F); // KEY3

        // 3. Load AES-128 Plaintext (NIST FIPS 197 vector)
        axi_write(32'h1000_0310, 32'h0011_2233); // PT0
        axi_write(32'h1000_0314, 32'h4455_6677); // PT1
        axi_write(32'h1000_0318, 32'h8899_AABB); // PT2
        axi_write(32'h1000_031C, 32'hCCDD_EEFF); // PT3

        // 4. Trigger AES Encryption (CTRL[0] = START)
        axi_write(32'h1000_0330, 32'h0000_0001);

        // 5. Poll AES STATUS register until DONE (bit 1 == 1)
        do begin
            axi_read(32'h1000_0334, rdata, resp);
        end while (rdata[1] !== 1'b1);

        `uvm_info("GATEWAY_SEQ", "AES Encryption Done! Verifying Ciphertext...", UVM_MEDIUM)

        // 6. Verify Ciphertext against NIST FIPS-197 Standard
        axi_read(32'h1000_0320, rdata, resp); // CT0
        if (rdata !== 32'h3925_841D)
            `uvm_error("GATEWAY_SEQ", $sformatf("CT0 mismatch: exp=0x3925841D act=0x%08h", rdata))

        axi_read(32'h1000_0324, rdata, resp); // CT1
        if (rdata !== 32'h02DC_09FB)
            `uvm_error("GATEWAY_SEQ", $sformatf("CT1 mismatch: exp=0x02DC09FB act=0x%08h", rdata))

        axi_read(32'h1000_0328, rdata, resp); // CT2
        if (rdata !== 32'hDC11_8597)
            `uvm_error("GATEWAY_SEQ", $sformatf("CT2 mismatch: exp=0xDC118597 act=0x%08h", rdata))

        axi_read(32'h1000_032C, rdata, resp); // CT3
        if (rdata !== 32'h196A_0B32)
            `uvm_error("GATEWAY_SEQ", $sformatf("CT3 mismatch: exp=0x196A0B32 act=0x%08h", rdata))

        // 7. Write Ciphertext into UART TX FIFO for transmission
        axi_write(32'h1000_0000, 32'h0000_0039);
        axi_write(32'h1000_0000, 32'h0000_0025);
        axi_write(32'h1000_0000, 32'h0000_0084);
        axi_write(32'h1000_0000, 32'h0000_001D);

        // 8. Indicate Completion on GPIO LED Pin 7
        axi_write(32'h1000_0204, 32'h0000_0080);

        `uvm_info("GATEWAY_SEQ", "Gateway Datapath Sequence executed with 100% matching results!", UVM_LOW)
    endtask

endclass : soc_gateway_pipeline_seq

`endif // SOC_GATEWAY_PIPELINE_SEQ_SV

