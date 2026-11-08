// =============================================================================
// Filelist: uvm_aes_filelist.f
// Description: VCS Compilation filelist for Block-Level AES UVM Testbench
// =============================================================================

+incdir+rtl/interconnect
+incdir+rtl/security
+incdir+uvm/if
+incdir+uvm/agents/axi_agent
+incdir+uvm/agents/clk_rst_agent
+incdir+uvm/tb

rtl/security/aes.v
uvm/if/axi_if.sv
uvm/if/clk_rst_if.sv
uvm/agents/axi_agent/axi_assertions.sv
uvm/tb/soc_uvm_pkg.sv
uvm/tb/tb_aes_uvm.sv
