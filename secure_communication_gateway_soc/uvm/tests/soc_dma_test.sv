// =============================================================================
// File: soc_dma_test.sv
// Description: UVM Test for DMA Controller (Modes 0 & 1, Configurations)
// =============================================================================

`ifndef SOC_DMA_TEST_SV
`define SOC_DMA_TEST_SV

class soc_dma_test extends soc_base_test;
    `uvm_component_utils(soc_dma_test)

    function new(string name = "soc_dma_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_dma_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_dma_test...", UVM_LOW)
        seq = soc_dma_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #500ns;
        phase.drop_objection(this);
    endtask

endclass : soc_dma_test

`endif // SOC_DMA_TEST_SV

