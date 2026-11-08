// =============================================================================
// Filelist: uvm_dma_filelist.f
// Description: VCS Compilation filelist for Block-Level DMA UVM Testbench
// =============================================================================

+incdir+rtl/interconnect
+incdir+rtl/dma
+incdir+uvm/if
+incdir+uvm/agents/axi_agent
+incdir+uvm/agents/clk_rst_agent
+incdir+uvm/tb

rtl/dma/dma.v
uvm/if/axi_if.sv
uvm/if/clk_rst_if.sv
uvm/agents/axi_agent/axi_assertions.sv
uvm/tb/soc_uvm_pkg.sv
uvm/tb/tb_dma_uvm.sv

