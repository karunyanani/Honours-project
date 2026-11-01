// =============================================================================
// File: soc_wdt_recovery_test.sv
// Description: UVM Test for Watchdog Stall Detection & Scoped Recovery
// =============================================================================

`ifndef SOC_WDT_RECOVERY_TEST_SV
`define SOC_WDT_RECOVERY_TEST_SV

class soc_wdt_recovery_test extends soc_base_test;
    `uvm_component_utils(soc_wdt_recovery_test)

    function new(string name = "soc_wdt_recovery_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_wdt_recovery_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_wdt_recovery_test...", UVM_LOW)
        seq = soc_wdt_recovery_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #500ns;
        phase.drop_objection(this);
    endtask

endclass : soc_wdt_recovery_test

`endif // SOC_WDT_RECOVERY_TEST_SV

