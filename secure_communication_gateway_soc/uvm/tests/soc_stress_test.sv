// =============================================================================
// File: soc_stress_test.sv
// Description: UVM Test for High-Throughput Interleaved Bus Traffic Stress
// =============================================================================

`ifndef SOC_STRESS_TEST_SV
`define SOC_STRESS_TEST_SV

class soc_stress_test extends soc_base_test;
    `uvm_component_utils(soc_stress_test)

    function new(string name = "soc_stress_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_stress_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_stress_test...", UVM_LOW)
        seq = soc_stress_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #500ns;
        phase.drop_objection(this);
    endtask

endclass : soc_stress_test

`endif // SOC_STRESS_TEST_SV

