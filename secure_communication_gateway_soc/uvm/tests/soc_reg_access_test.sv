// =============================================================================
// File: soc_reg_access_test.sv
// Description: UVM Test for Register Sanity across all 9 Slaves
// =============================================================================

`ifndef SOC_REG_ACCESS_TEST_SV
`define SOC_REG_ACCESS_TEST_SV

class soc_reg_access_test extends soc_base_test;
    `uvm_component_utils(soc_reg_access_test)

    function new(string name = "soc_reg_access_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_reg_access_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_reg_access_test...", UVM_LOW)
        seq = soc_reg_access_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #100ns;
        phase.drop_objection(this);
    endtask

endclass : soc_reg_access_test

`endif // SOC_REG_ACCESS_TEST_SV

