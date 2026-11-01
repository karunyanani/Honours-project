// =============================================================================
// File: gpio_agent_config.sv
// Description: Configuration Object for GPIO Verification IP
// =============================================================================

`ifndef GPIO_AGENT_CONFIG_SV
`define GPIO_AGENT_CONFIG_SV

class gpio_agent_config extends uvm_object;
    `uvm_object_utils(gpio_agent_config)

    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit [7:0] default_dir             = 8'h00; // 0: Input, 1: Output
    bit [7:0] default_in              = 8'h00;
    int       sample_delay_cycles     = 1;
    bit       coverage_enable         = 1;

    function new(string name = "gpio_agent_config");
        super.new(name);
    endfunction

endclass : gpio_agent_config

`endif // GPIO_AGENT_CONFIG_SV

