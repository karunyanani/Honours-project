// =============================================================================
// File: spi_if.sv
// Description: SystemVerilog Interface for SPI Master and Sensor signals
// =============================================================================

`ifndef SPI_IF_SV
`define SPI_IF_SV

interface spi_if (
    input logic clk,
    input logic rst
);

    logic sclk;        // SoC SPI Master clock output
    logic cs_n;        // SoC SPI Chip Select (active low) output
    logic mosi;        // Master Out Slave In (from SoC)
    logic miso;        // Master In Slave Out (from Sensor VIP)
    logic sensor_drdy; // Sensor Data Ready flag into SoC

    // Sensor Slave Driver Clocking Block
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        input  sclk, cs_n, mosi;
        output miso, sensor_drdy;
    endclocking

    // Bus Monitor Clocking Block
    clocking mon_cb @(posedge clk);
        default input #1step;
        input sclk, cs_n, mosi, miso, sensor_drdy;
    endclocking

    modport driver  (clocking drv_cb, input clk, rst, sclk, cs_n, mosi, output miso, sensor_drdy);
    modport monitor (clocking mon_cb, input clk, rst, sclk, cs_n, mosi, miso, sensor_drdy);

endinterface : spi_if

`endif // SPI_IF_SV
