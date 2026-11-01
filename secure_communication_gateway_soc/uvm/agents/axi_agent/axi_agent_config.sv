// =============================================================================
// File: axi_agent_config.sv
// Description: Configuration Object for AXI4 Verification IP
// =============================================================================

`ifndef AXI_AGENT_CONFIG_SV
`define AXI_AGENT_CONFIG_SV

class axi_agent_config extends uvm_object;
    `uvm_object_utils(axi_agent_config)

    typedef enum bit {
        AXI_ROLE_MASTER = 1'b0,
        AXI_ROLE_SLAVE  = 1'b1
    } axi_role_e;

    uvm_active_passive_enum is_active = UVM_ACTIVE;
    axi_role_e              role      = AXI_ROLE_MASTER;

    // Default responder memory size for slave mode (e.g. 64KB)
    int responder_mem_size_bytes = 65536;

    // Latency controls
    int awready_delay = 0;
    int wready_delay  = 0;
    int arready_delay = 0;
    int bvalid_delay  = 1;
    int rvalid_delay  = 1;

    // Coverage & assertions
    bit enable_coverage   = 1'b1;
    bit enable_assertions = 1'b1;

    function new(string name = "axi_agent_config");
        super.new(name);
    endfunction

endclass : axi_agent_config

`endif // AXI_AGENT_CONFIG_SV

