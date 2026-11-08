// =============================================================================
// File: soc_spi_test.sv
// Description: UVM Test for SPI Controller Interface
// =============================================================================

`ifndef SOC_SPI_TEST_SV
`define SOC_SPI_TEST_SV

class soc_spi_test extends soc_base_test;
    `uvm_component_utils(soc_spi_test)

    function new(string name = "soc_spi_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_spi_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_spi_test...", UVM_LOW)
        seq = soc_spi_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #500ns;
        phase.drop_objection(this);
    endtask

endclass : soc_spi_test

`endif // SOC_SPI_TEST_SV

