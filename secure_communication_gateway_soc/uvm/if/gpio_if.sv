// =============================================================================
// File: gpio_if.sv
// Description: SystemVerilog Interface for SoC GPIO Peripheral and IRQ Signals
// =============================================================================

`ifndef GPIO_IF_SV
`define GPIO_IF_SV

interface gpio_if (
    input logic clk,
    input logic rst
);

    logic [7:0] gpio_in;
    logic [7:0] gpio_out;
    logic [7:0] gpio_oe;
    logic       gpio_irq;

    // Driver Clocking Block
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output gpio_in;
        input  gpio_out, gpio_oe, gpio_irq;
    endclocking

    // Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1step;
        input gpio_in, gpio_out, gpio_oe, gpio_irq;
    endclocking

    modport driver  (clocking drv_cb, input clk, rst);
    modport monitor (clocking mon_cb, input clk, rst);

endinterface : gpio_if

`endif // GPIO_IF_SV
