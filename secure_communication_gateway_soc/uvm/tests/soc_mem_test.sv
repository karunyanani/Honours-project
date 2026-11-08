// =============================================================================
// File: soc_mem_test.sv
// Description: UVM Test for Memory Boundaries and Byte Strobes
// =============================================================================

`ifndef SOC_MEM_TEST_SV
`define SOC_MEM_TEST_SV

class soc_mem_test extends soc_base_test;
    `uvm_component_utils(soc_mem_test)

    function new(string name = "soc_mem_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_mem_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_mem_test...", UVM_LOW)
        seq = soc_mem_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #500ns;
        phase.drop_objection(this);
    endtask

endclass : soc_mem_test

`endif // SOC_MEM_TEST_SV

