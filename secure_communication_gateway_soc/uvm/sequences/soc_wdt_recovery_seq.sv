// =============================================================================
// File: soc_wdt_recovery_seq.sv
// Description: UVM Sequence verifying Watchdog Stall Detection & Scoped Recovery
// =============================================================================

`ifndef SOC_WDT_RECOVERY_SEQ_SV
`define SOC_WDT_RECOVERY_SEQ_SV

class soc_wdt_recovery_seq extends soc_base_seq;
    `uvm_object_utils(soc_wdt_recovery_seq)

    function new(string name = "soc_wdt_recovery_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("WDT_SEQ", "Starting Watchdog Scoped Fault Recovery Sequence...", UVM_LOW)

        // 1. Program Data Memory with signature value that MUST be preserved during reset
        axi_write(32'h0001_0020, 32'hA5A5_5A5A);

        // 2. Program AES Key that MUST be preserved during reset
        axi_write(32'h1000_0300, 32'hDEAD_BEEF);

        // 3. Configure short Watchdog Timeout (100 cycles) and Enable
        axi_write(32'h1000_0600, 32'd100);       // TIMEOUT
        axi_write(32'h1000_0608, 32'h0000_0001); // CTRL (EN=1)

        // 4. Intentionally withhold feeding (stall datapath) and poll STATUS
        `uvm_info("WDT_SEQ", "Withholding feed to induce stall...", UVM_MEDIUM)

        do begin
            axi_read(32'h1000_060C, rdata, resp); // STATUS
        end while (rdata[1] !== 1'b1); // Bit 1 = EXPIRED / RESET_TRIGGERED

        `uvm_info("WDT_SEQ", "Watchdog Timeout triggered! Checking Scoped Reset...", UVM_MEDIUM)

        // 5. Verify Reset Cause Register (Offset 0x10) records 0x01
        axi_read(32'h1000_0610, rdata, resp);
        if (rdata[0] !== 1'b1)
            `uvm_error("WDT_SEQ", $sformatf("Reset Cause register mismatch: 0x%08h", rdata))

        // 6. Verify Scoped Reset: DMEM retained data
        axi_read(32'h0001_0020, rdata, resp);
        if (rdata !== 32'hA5A5_5A5A)
            `uvm_error("WDT_SEQ", $sformatf("DMEM data corrupted across WDT reset: 0x%08h", rdata))

        // 7. Verify W1C (Write-1-to-Clear) on Reset Cause
        axi_write(32'h1000_0610, 32'h0000_0001); // W1C
        axi_read (32'h1000_0610, rdata, resp);
        if (rdata[0] !== 1'b0)
            `uvm_error("WDT_SEQ", "W1C on Reset Cause failed: bit 0 did not clear")

        `uvm_info("WDT_SEQ", "Watchdog Scoped Fault Recovery Sequence passed successfully!", UVM_LOW)
    endtask

endclass : soc_wdt_recovery_seq

`endif // SOC_WDT_RECOVERY_SEQ_SV

