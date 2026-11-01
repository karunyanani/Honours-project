// =============================================================================
// File: interrupt_if.sv
// Description: SystemVerilog Interface for SoC Interrupt and Fault Recovery signals
// =============================================================================

`ifndef INTERRUPT_IF_SV
`define INTERRUPT_IF_SV

interface interrupt_if (
    input logic clk,
    input logic rst
);

    logic gpio_irq;    // Edge-detect interrupt from GPIO
    logic timer_irq;   // Countdown interrupt from Timer
    logic wdt_fired;   // Scoped fault reset trigger from Watchdog

    clocking mon_cb @(posedge clk);
        default input #1step;
        input gpio_irq, timer_irq, wdt_fired;
    endclocking

    modport monitor (clocking mon_cb, input clk, rst, gpio_irq, timer_irq, wdt_fired);

endinterface : interrupt_if

`endif // INTERRUPT_IF_SV

