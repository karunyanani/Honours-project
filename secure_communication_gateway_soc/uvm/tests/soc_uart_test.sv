// =============================================================================
// File: soc_uart_test.sv
// Description: UVM Test for UART Serial Communication Interface
// =============================================================================

`ifndef SOC_UART_TEST_SV
`define SOC_UART_TEST_SV

class soc_uart_test extends soc_base_test;
    `uvm_component_utils(soc_uart_test)

    function new(string name = "soc_uart_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_uart_seq seq;
        phase.raise_objection(this);

        `uvm_info("TEST", "Running soc_uart_test...", UVM_LOW)
        seq = soc_uart_seq::type_id::create("seq");
        seq.start(env.m_axi_agent.sequencer);

        #500ns;
        phase.drop_objection(this);
    endtask

endclass : soc_uart_test

`endif // SOC_UART_TEST_SV
