// =============================================================================
// File: clk_rst_sequencer.sv
// Description: UVM Sequencer for Clock and Reset VIP
// =============================================================================

`ifndef CLK_RST_SEQUENCER_SV
`define CLK_RST_SEQUENCER_SV

class clk_rst_sequencer extends uvm_sequencer #(clk_rst_seq_item);
    `uvm_component_utils(clk_rst_sequencer)

    function new(string name = "clk_rst_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass : clk_rst_sequencer

`endif // CLK_RST_SEQUENCER_SV

