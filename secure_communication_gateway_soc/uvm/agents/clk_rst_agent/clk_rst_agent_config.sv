// =============================================================================
// File: clk_rst_agent_config.sv
// Description: Configuration Object for Clock and Reset Generation VIP
// =============================================================================

`ifndef CLK_RST_AGENT_CONFIG_SV
`define CLK_RST_AGENT_CONFIG_SV

class clk_rst_agent_config extends uvm_object;
    `uvm_object_utils(clk_rst_agent_config)

    time clk_period_ns      = 20ns; // 50 MHz default SoC clock (or 10ns for 100MHz)
    real duty_cycle         = 50.0;
    time reset_duration_ns  = 100ns;
    bit  start_in_reset     = 1'b1;

    function new(string name = "clk_rst_agent_config");
        super.new(name);
    endfunction

endclass : clk_rst_agent_config

`endif // CLK_RST_AGENT_CONFIG_SV

