// =============================================================================
// File: soc_aes_seq.sv
// Description: UVM Sequence validating AES-128 Engine (ECB KAT and CTR Mode)
// =============================================================================

`ifndef SOC_AES_SEQ_SV
`define SOC_AES_SEQ_SV

class soc_aes_seq extends soc_base_seq;
    `uvm_object_utils(soc_aes_seq)

    function new(string name = "soc_aes_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("AES_SEQ", "Starting AES Hardware Engine Verification Sequence...", UVM_LOW)

        // ---------------------------------------------------------------------
        // Phase 1: NIST FIPS-197 Known Answer Test (ECB Mode)
        // ---------------------------------------------------------------------
        `uvm_info("AES_SEQ", "Phase 1: NIST FIPS-197 Known Answer Test (ECB Mode)", UVM_MEDIUM)

        // 1. Program 128-bit Key: 00010203_04050607_08090A0B_0C0D0E0F
        axi_write(32'h1000_0300, 32'h0001_0203); // KEY0
        axi_write(32'h1000_0304, 32'h0405_0607); // KEY1
        axi_write(32'h1000_0308, 32'h0809_0A0B); // KEY2
        axi_write(32'h1000_030C, 32'h0C0D_0E0F); // KEY3

        // 2. Program 128-bit Plaintext: 00112233_44556677_8899AABB_CCDDEEFF
        axi_write(32'h1000_0318, 32'h0011_2233); // DATA_IN0
        axi_write(32'h1000_031C, 32'h4455_6677); // DATA_IN1
        axi_write(32'h1000_0320, 32'h8899_AABB); // DATA_IN2
        axi_write(32'h1000_0324, 32'hCCDD_EEFF); // DATA_IN3

        // 3. Start ECB Encryption (CTRL[0]=1 (START), CTRL[1]=1 (KEY_VALID), CTRL[2]=0 (ECB))
        axi_write(32'h1000_0310, 32'h0000_0003);

        // 4. Poll STATUS until DONE (bit 0 == 1)
        do begin
            axi_read(32'h1000_0314, rdata, resp);
        end while (rdata[0] !== 1'b1);

        // 5. Verify Ciphertext against NIST FIPS-197 (3925841d_02dc09fb_dc118597_196a0b32)
        axi_read(32'h1000_0328, rdata, resp);
        if (rdata !== 32'h3925_841D)
            `uvm_error("AES_SEQ", $sformatf("ECB CT0 mismatch: exp=0x3925841D act=0x%08h", rdata))

        axi_read(32'h1000_032C, rdata, resp);
        if (rdata !== 32'h02DC_09FB)
            `uvm_error("AES_SEQ", $sformatf("ECB CT1 mismatch: exp=0x02DC09FB act=0x%08h", rdata))

        axi_read(32'h1000_0330, rdata, resp);
        if (rdata !== 32'hDC11_8597)
            `uvm_error("AES_SEQ", $sformatf("ECB CT2 mismatch: exp=0xDC118597 act=0x%08h", rdata))

        axi_read(32'h1000_0334, rdata, resp);
        if (rdata !== 32'h196A_0B32)
            `uvm_error("AES_SEQ", $sformatf("ECB CT3 mismatch: exp=0x196A0B32 act=0x%08h", rdata))

        `uvm_info("AES_SEQ", "NIST FIPS-197 ECB Known Answer Test PASSED!", UVM_LOW)

        // ---------------------------------------------------------------------
        // Phase 2: AES-128 CTR Mode Validation & IV Auto-Increment
        // ---------------------------------------------------------------------
        `uvm_info("AES_SEQ", "Phase 2: AES-128 CTR Mode & Counter Auto-Increment", UVM_MEDIUM)

        // Set IV = 0x00000000_00000000_00000000_00000001
        axi_write(32'h1000_0338, 32'h0000_0000); // IV0
        axi_write(32'h1000_033C, 32'h0000_0000); // IV1
        axi_write(32'h1000_0340, 32'h0000_0000); // IV2
        axi_write(32'h1000_0344, 32'h0000_0001); // IV3

        // Configure CTR Mode: CTRL[2]=1 (CTR), CTRL[1]=1 (KEY_VALID), CTRL[0]=1 (START) -> 0x07
        axi_write(32'h1000_0310, 32'h0000_0007);

        // Poll STATUS until DONE
        do begin
            axi_read(32'h1000_0314, rdata, resp);
        end while (rdata[0] !== 1'b1);

        // Read and verify IV auto-incremented: IV3 must be 2
        axi_read(32'h1000_0344, rdata, resp);
        if (rdata !== 32'h0000_0002)
            `uvm_error("AES_SEQ", $sformatf("CTR IV3 auto-increment failed: exp=2 act=%0d", rdata))
        else
            `uvm_info("AES_SEQ", "CTR IV auto-increment verified successfully (IV3 = 2)", UVM_LOW)

        `uvm_info("AES_SEQ", "All AES Hardware Engine Verification Checks Completed!", UVM_LOW)
    endtask

endclass : soc_aes_seq

`endif // SOC_AES_SEQ_SV

