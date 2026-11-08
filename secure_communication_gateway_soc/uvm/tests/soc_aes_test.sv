// =============================================================================
// File: soc_aes_test.sv
// Description: UVM Test for AES-128 Hardware Engine (ECB KAT & CTR Mode)
// =============================================================================

`ifndef SOC_AES_TEST_SV
`define SOC_AES_TEST_SV

class soc_aes_test extends soc_base_test;
    `uvm_component_utils(soc_aes_test)

    function new(string name = "soc_aes_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_aes_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_aes_test...", UVM_LOW)
        seq = soc_aes_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #500ns;
        phase.drop_objection(this);
    endtask

endclass : soc_aes_test

`endif // SOC_AES_TEST_SV

