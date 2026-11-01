// =============================================================================
// File: clk_rst_if.sv
// Description: SystemVerilog Interface for Dynamic Clock and Reset Generation VIP
// =============================================================================

`ifndef CLK_RST_IF_SV
`define CLK_RST_IF_SV

interface clk_rst_if;

    logic clk;
    logic rst;    // Active-high synchronous/asynchronous reset
    logic rst_n;  // Active-low external reset (drives soc_top rst_n)

    initial begin
        clk   = 1'b0;
        rst   = 1'b1;
        rst_n = 1'b0;
    end

endinterface : clk_rst_if

`endif // CLK_RST_IF_SV

