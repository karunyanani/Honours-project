// =============================================================================
// File: soc_gateway_pipeline_test.sv
// Description: UVM Test for Full Sensor->SPI->DMA->AES->UART Pipeline
// =============================================================================

`ifndef SOC_GATEWAY_PIPELINE_TEST_SV
`define SOC_GATEWAY_PIPELINE_TEST_SV

class soc_gateway_pipeline_test extends soc_base_test;
    `uvm_component_utils(soc_gateway_pipeline_test)

    function new(string name = "soc_gateway_pipeline_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_gateway_pipeline_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_gateway_pipeline_test...", UVM_LOW)
        seq = soc_gateway_pipeline_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #1000ns;
        phase.drop_objection(this);
    endtask

endclass : soc_gateway_pipeline_test

`endif // SOC_GATEWAY_PIPELINE_TEST_SV

