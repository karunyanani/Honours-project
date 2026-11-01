// =============================================================================
// File: interrupt_agent_config.sv
// Description: Configuration Object for Interrupt & Fault Recovery VIP
// =============================================================================

`ifndef INTERRUPT_AGENT_CONFIG_SV
`define INTERRUPT_AGENT_CONFIG_SV

class interrupt_agent_config extends uvm_object;
    `uvm_object_utils(interrupt_agent_config)

    bit monitor_gpio_irq  = 1'b1;
    bit monitor_timer_irq = 1'b1;
    bit monitor_wdt_fired = 1'b1;

    // Timeout thresholds (cycles)
    int max_irq_latency_cycles = 1000;
    int max_wdt_latency_cycles = 50000;

    function new(string name = "interrupt_agent_config");
        super.new(name);
    endfunction

endclass : interrupt_agent_config

`endif // INTERRUPT_AGENT_CONFIG_SV

