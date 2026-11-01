// =============================================================================
// File: uart_agent_config.sv
// Description: Configuration Object for UART Verification IP
// =============================================================================

`ifndef UART_AGENT_CONFIG_SV
`define UART_AGENT_CONFIG_SV

class uart_agent_config extends uvm_object;
    `uvm_object_utils(uart_agent_config)

    uvm_active_passive_enum is_active = UVM_ACTIVE;

    int baud_rate     = 115200;
    int clk_freq_hz   = 50_000_000;
    int clks_per_bit  = 434; // 50MHz / 115200 ≈ 434 (or 100MHz / 115200 ≈ 868)

    int data_bits     = 8;
    int stop_bits     = 1;
    bit parity_enable = 0;
    bit parity_odd    = 0;

    function new(string name = "uart_agent_config");
        super.new(name);
    endfunction

    virtual function void set_clks_per_bit(int sys_clk_hz, int baud);
        this.clk_freq_hz  = sys_clk_hz;
        this.baud_rate    = baud;
        this.clks_per_bit = sys_clk_hz / baud;
    endfunction

endclass : uart_agent_config

`endif // UART_AGENT_CONFIG_SV

