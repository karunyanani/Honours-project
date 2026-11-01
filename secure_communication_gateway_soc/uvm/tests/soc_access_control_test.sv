// =============================================================================
// File: soc_access_control_test.sv
// Description: UVM Test for AXI Access Control Matrix & DECERR Enforcement
// =============================================================================

`ifndef SOC_ACCESS_CONTROL_TEST_SV
`define SOC_ACCESS_CONTROL_TEST_SV

class soc_access_control_test extends soc_base_test;
    `uvm_component_utils(soc_access_control_test)

    function new(string name = "soc_access_control_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_access_control_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_access_control_test...", UVM_LOW)
        seq = soc_access_control_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #100ns;
        phase.drop_objection(this);
    endtask

endclass : soc_access_control_test

`endif // SOC_ACCESS_CONTROL_TEST_SV

