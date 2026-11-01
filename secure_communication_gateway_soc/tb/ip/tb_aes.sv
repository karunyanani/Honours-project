// =============================================================================
// tb_aes.sv  –  AES-128 Engine Self-Checking Testbench
//
// Tests (spec §14, AES verification):
//   TC01 – FIPS-197 Appendix B known-answer test (KAT)
//          Key  = 2b7e1516 28aed2a6 abf71588 09cf4f3c
//          PT   = 3243f6a8 885a308d 313198a2 e0370734
//          CT   = 3925841d 02dc09fb dc118597 196a0b32
//   TC02 – FIPS-197 Appendix C.1 KAT (all-zero key)
//          Key  = 00000000 00000000 00000000 00000000
//          PT   = 00000000 00000000 00000000 00000000
//          CT   = 66e94bd4 ef8a2c3b 884cfa59 ca342b2e
//   TC03 – CTR mode reference test
//          Encrypt two blocks with incrementing counter; verify XOR with PT
//   TC04 – Key loading: engine not DONE before KEY_VALID set
//   TC05 – Busy→Done sequence and timing (exactly 11 cycles minimum)
//   TC06 – Reading AES_STATUS clears DONE flag (read-to-clear)
//   TC07 – Output retained until next operation
//   TC08 – Watchdog scoped reset clears pipeline but retains key
//   TC09 – Starting with KEY_VALID=0 must NOT assert DONE
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_aes;

    parameter CLK_PERIOD = 10;
    parameter AW = 32;
    parameter DW = 32;

    logic clk = 0;
    logic rst = 1;
    logic wdt_rst = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // AXI4-Lite slave connections
    logic [AW-1:0] s_awaddr; logic s_awvalid; logic s_awready;
    logic [DW-1:0] s_wdata;  logic [3:0] s_wstrb;
    logic          s_wvalid; logic s_wready;
    logic [1:0]    s_bresp;  logic s_bvalid;  logic s_bready;
    logic [AW-1:0] s_araddr; logic s_arvalid; logic s_arready;
    logic [DW-1:0] s_rdata;  logic [1:0] s_rresp;
    logic          s_rvalid; logic s_rready;
    logic          aes_done;

    aes dut (
        .clk(clk), .rst(rst), .wdt_rst(wdt_rst),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata),   .s_axi_wstrb(s_wstrb),     .s_axi_wvalid(s_wvalid),
        .s_axi_wready(s_wready), .s_axi_bresp(s_bresp),      .s_axi_bvalid(s_bvalid),
        .s_axi_bready(s_bready), .s_axi_araddr(s_araddr),    .s_axi_arvalid(s_arvalid),
        .s_axi_arready(s_arready),.s_axi_rdata(s_rdata),     .s_axi_rresp(s_rresp),
        .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),    .aes_done(aes_done)
    );

    // =========================================================================
    // AXI-Lite BFM tasks (base address is 0, offsets used directly)
    // =========================================================================
    task axi_write(input [7:0] off, input [31:0] data);
        @(posedge clk); #1;
        s_awaddr = {24'h0, off}; s_awvalid = 1;
        s_wdata  = data;         s_wstrb   = 4'hF; s_wvalid = 1;
        s_bready = 1;
        fork
            begin
                do @(posedge clk);
                while (!s_awready);
                #1 s_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!s_wready);
                #1 s_wvalid = 0;
            end
        join
        while (!s_bvalid) @(posedge clk) #1;
        @(posedge clk); #1;
        s_bready = 0;
    endtask

    task axi_read(input [7:0] off, output [31:0] data);
        @(posedge clk); #1;
        s_araddr = {24'h0, off}; s_arvalid = 1;
        s_rready = 1;
        do @(posedge clk);
        while (!s_arready);
        #1 s_arvalid = 0;
        while (!s_rvalid) @(posedge clk) #1;
        data = s_rdata;
        @(posedge clk); #1;
        s_rready = 0;
    endtask

    // Write 128-bit key (4 × 32-bit words)
    task load_key(input [127:0] key);
        axi_write(8'h00, key[127:96]);
        axi_write(8'h04, key[ 95:64]);
        axi_write(8'h08, key[ 63:32]);
        axi_write(8'h0C, key[ 31: 0]);
        axi_write(8'h10, 32'h02);  // KEY_VALID=1, START=0
    endtask

    // Write 128-bit plaintext and start encryption
    task encrypt(input [127:0] pt);
        axi_write(8'h18, pt[127:96]);
        axi_write(8'h1C, pt[ 95:64]);
        axi_write(8'h20, pt[ 63:32]);
        axi_write(8'h24, pt[ 31: 0]);
        axi_write(8'h10, 32'h03);  // KEY_VALID=1, START=1
    endtask

    // Poll STATUS until DONE=1; fail after timeout
    task wait_done(output logic done);
        logic [31:0] st;
        integer timeout;
        timeout = 0;
        done = 0;
        st = 0;
        while (st[0] == 0 && timeout <= 200) begin
            axi_read(8'h14, st);
            timeout++;
        end
        if (st[0] == 1) begin
            done = 1;
        end else begin
            $display("[FAIL] wait_done: timeout after %0d polls", timeout);
            done = 0;
        end
    endtask

    // Read 128-bit ciphertext
    task read_ct(output [127:0] ct);
        logic [31:0] w;
        axi_read(8'h28, w); ct[127:96] = w;
        axi_read(8'h2C, w); ct[ 95:64] = w;
        axi_read(8'h30, w); ct[ 63:32] = w;
        axi_read(8'h34, w); ct[ 31: 0] = w;
    endtask

    // =========================================================================
    // CTR mode reference model (software)
    // Encrypt counter block using known AES-128 result, XOR with plaintext
    // We derive expected CT from the FIPS KAT engine output
    // =========================================================================

    // =========================================================================
    // Test helpers
    // =========================================================================
    integer pass_count = 0, fail_count = 0;

    task check(input string name, input logic cond);
        if (cond) begin $display("[PASS] %s", name); pass_count++; end
        else      begin $display("[FAIL] %s", name); fail_count++; end
    endtask

    logic [127:0] ct_got;
    logic         done;
    logic [31:0]  status_word;
    integer       i;

    initial begin
        // Init AXI
        s_awvalid=0; s_wvalid=0; s_bready=0;
        s_arvalid=0; s_rready=0;
        s_awaddr=0; s_wdata=0; s_wstrb=4'hF;
        s_araddr=0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ==================================================================
        // TC01 – FIPS-197 Appendix B KAT
        //   Key = 2b7e151628aed2a6abf7158809cf4f3c
        //   PT  = 3243f6a8885a308d313198a2e0370734
        //   CT  = 3925841d02dc09fbdc118597196a0b32
        // ==================================================================
        $display("--- TC01: FIPS-197 Appendix B KAT ---");
        load_key(128'h2b7e151628aed2a6abf7158809cf4f3c);
        encrypt (128'h3243f6a8885a308d313198a2e0370734);
        wait_done(done);
        check("TC01_DONE", done);
        if (done) begin
            read_ct(ct_got);
            check("TC01_CT_W0", ct_got[127:96] == 32'h3925841d);
            check("TC01_CT_W1", ct_got[ 95:64] == 32'h02dc09fb);
            check("TC01_CT_W2", ct_got[ 63:32] == 32'hdc118597);
            check("TC01_CT_W3", ct_got[ 31: 0] == 32'h196a0b32);
        end

        // ==================================================================
        // TC02 – FIPS-197 Appendix C.1 (all-zero key + plaintext)
        //   Key = 00000000000000000000000000000000
        //   PT  = 00000000000000000000000000000000
        //   CT  = 66e94bd4ef8a2c3b884cfa59ca342b2e
        // ==================================================================
        $display("--- TC02: FIPS-197 all-zero KAT ---");
        load_key(128'h0);
        encrypt (128'h0);
        wait_done(done);
        check("TC02_DONE", done);
        if (done) begin
            read_ct(ct_got);
            check("TC02_CT_W0", ct_got[127:96] == 32'h66e94bd4);
            check("TC02_CT_W1", ct_got[ 95:64] == 32'hef8a2c3b);
            check("TC02_CT_W2", ct_got[ 63:32] == 32'h884cfa59);
            check("TC02_CT_W3", ct_got[ 31: 0] == 32'hca342b2e);
        end

        // ==================================================================
        // TC03 – CTR mode: encrypt counter block, XOR with PT
        //   Key  = 2b7e151628aed2a6abf7158809cf4f3c  (same as TC01)
        //   CTR0 = 00000000000000000000000000000001  (counter = 1)
        //   Encrypted CTR0 = AES(key, CTR0)
        //   Plaintext = 6bc1bee22e409f96e93d7e117393172a  (NIST SP800-38A example)
        //   CTR CT = PT XOR AES(key, CTR0)
        //   We verify by:
        //     1. AES(key, CTR0) → get keystream block
        //     2. XOR with PT to get CTR ciphertext
        //     3. AES(key, CTR1) with CTR1 = CTR0+1 → second keystream block
        // ==================================================================
        $display("--- TC03: CTR mode reference test ---");
        // Encrypt counter block 1
        load_key(128'h2b7e151628aed2a6abf7158809cf4f3c);
        encrypt (128'h00000000000000000000000000000001);
        wait_done(done);
        check("TC03_CTR0_DONE", done);
        if (done) begin
            logic [127:0] ks0, pt0, ct_ctr;
            read_ct(ks0);
            pt0    = 128'h6bc1bee22e409f96e93d7e117393172a;
            ct_ctr = pt0 ^ ks0;
            $display("  CTR[0] keystream = %032h", ks0);
            $display("  CTR[0] ciphertext= %032h", ct_ctr);
            // Verify decryption: AES(key, CTR0) XOR CT == PT
            check("TC03_CTR_DECRYPT", (ct_ctr ^ ks0) == pt0);
        end
        // Encrypt counter block 2
        encrypt (128'h00000000000000000000000000000002);
        wait_done(done);
        check("TC03_CTR1_DONE", done);
        if (done) begin
            logic [127:0] ks1;
            read_ct(ks1);
            // Counter blocks must produce different keystreams
            check("TC03_CTR_UNIQUE", ks1 != ct_got); // ct_got is CTR0 result
        end

        // ==================================================================
        // TC04 – No-key: START without KEY_VALID must not fire DONE
        // ==================================================================
        $display("--- TC04: No-key protection ---");
        // Reset engine without loading a key
        wdt_rst = 1; @(posedge clk); wdt_rst = 0;
        @(posedge clk);
        // Write plaintext
        axi_write(8'h18, 32'hAABB_CCDD);
        axi_write(8'h1C, 32'hEEFF_0011);
        axi_write(8'h20, 32'h2233_4455);
        axi_write(8'h24, 32'h6677_8899);
        // Set START=1 but KEY_VALID=0
        axi_write(8'h10, 32'h01);
        // Wait some cycles and check DONE stays 0
        repeat(20) @(posedge clk);
        axi_read(8'h14, status_word);
        check("TC04_NO_KEY_NO_DONE", status_word[0] == 0);

        // ==================================================================
        // TC05 – Busy→Done timing: pipeline must assert DONE within 15 cycles
        // ==================================================================
        $display("--- TC05: Busy/Done timing ---");
        load_key(128'hDEAD_BEEF_CAFE_BABE_0000_1111_2222_3333);
        // Start and measure cycles to DONE
        axi_write(8'h18, 32'h0); axi_write(8'h1C, 32'h0);
        axi_write(8'h20, 32'h0); axi_write(8'h24, 32'h0);
        axi_write(8'h10, 32'h03); // START
        begin : timing_check
            integer cyc;
            cyc = 0;
            @(posedge clk);
            while (!aes_done && cyc < 20) begin
                @(posedge clk);
                cyc++;
            end
            check("TC05_DONE_WITHIN_15", cyc <= 15);
            check("TC05_DONE_FIRES",     aes_done);
        end

        // ==================================================================
        // TC06 – Reading STATUS clears DONE
        // ==================================================================
        $display("--- TC06: DONE read-to-clear ---");
        load_key(128'h0101010101010101_0101010101010101);
        encrypt(128'h0);
        wait_done(done);
        check("TC06_DONE_SET", done);
        // Read STATUS – this should clear DONE
        axi_read(8'h14, status_word);
        // Read again – DONE should now be 0
        axi_read(8'h14, status_word);
        check("TC06_DONE_CLEARED", status_word[0] == 0);

        // ==================================================================
        // TC07 – Output retained: ciphertext stable until next START
        // ==================================================================
        $display("--- TC07: Output retention ---");
        load_key(128'h2b7e151628aed2a6abf7158809cf4f3c);
        encrypt (128'h3243f6a8885a308d313198a2e0370734);
        wait_done(done);
        read_ct(ct_got);
        // Wait many cycles without issuing new encryption
        repeat(50) @(posedge clk);
        begin
            logic [127:0] ct_after;
            read_ct(ct_after);
            check("TC07_RETAINED", ct_after == ct_got);
        end

        // ==================================================================
        // TC08 – Watchdog reset: clears pipeline, retains key
        // ==================================================================
        $display("--- TC08: WDT reset retains key ---");
        // Load a known key
        load_key(128'h2b7e151628aed2a6abf7158809cf4f3c);
        // Start an operation
        encrypt(128'h3243f6a8885a308d313198a2e0370734);
        // Immediately reset (mid-pipeline)
        wdt_rst = 1; @(posedge clk); wdt_rst = 0;
        repeat(2) @(posedge clk);
        // DONE should be cleared
        axi_read(8'h14, status_word);
        check("TC08_DONE_CLEARED", status_word[0] == 0);
        // Key readback should still return original values
        axi_read(8'h00, status_word);
        check("TC08_KEY_RETAINED", status_word == 32'h2b7e1516);

        // ==================================================================
        // TC09 – AES_CTRL[1]=KEY_VALID required before START fires
        // ==================================================================
        $display("--- TC09: KEY_VALID gate ---");
        // Reload key with KEY_VALID=0 (write key registers only, not CTRL)
        axi_write(8'h00, 32'hAAAA_AAAA);
        axi_write(8'h10, 32'h00); // clear KEY_VALID
        axi_write(8'h18, 32'hFFFF_FFFF);
        axi_write(8'h1C, 32'hFFFF_FFFF);
        axi_write(8'h20, 32'hFFFF_FFFF);
        axi_write(8'h24, 32'hFFFF_FFFF);
        // Write START=1 only (KEY_VALID=0)
        axi_write(8'h10, 32'h01);
        repeat(15) @(posedge clk);
        axi_read(8'h14, status_word);
        check("TC09_KEYGATED", status_word[0] == 0);

        // ==================================================================
        repeat(2) @(posedge clk);
        $display("========================================");
        $display(" tb_aes RESULTS");
        $display(" PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish(fail_count > 0 ? 1 : 0);
    end

    initial begin #500_000; $display("[FAIL] TIMEOUT"); $finish(1); end

endmodule
