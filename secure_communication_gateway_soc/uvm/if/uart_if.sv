// =============================================================================
// File: uart_if.sv
// Description: SystemVerilog Interface for Full-Duplex UART Serial Interface
// =============================================================================

`ifndef UART_IF_SV
`define UART_IF_SV

interface uart_if (
    input logic clk,
    input logic rst
);

    logic uart_tx; // SoC output -> external receiver input
    logic uart_rx; // External driver output -> SoC input

    // Driver Clocking Block (drives uart_rx into SoC)
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output uart_rx;
        input  uart_tx;
    endclocking

    // Monitor Clocking Block (monitors both uart_tx and uart_rx)
    clocking mon_cb @(posedge clk);
        default input #1step;
        input uart_tx, uart_rx;
    endclocking

    modport driver  (clocking drv_cb, input clk, rst);
    modport monitor (clocking mon_cb, input clk, rst);

endinterface : uart_if

`endif // UART_IF_SV
