// =============================================================================
// File: soc_base_test.sv
// Description: UVM Base Test establishing Environment and Drainage Time
// =============================================================================

`ifndef SOC_BASE_TEST_SV
`define SOC_BASE_TEST_SV

class soc_base_test extends uvm_test;
    `uvm_component_utils(soc_base_test)

    soc_env env;

    function new(string name = "soc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = soc_env::type_id::create("env", this);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction

endclass : soc_base_test

`endif // SOC_BASE_TEST_SV

