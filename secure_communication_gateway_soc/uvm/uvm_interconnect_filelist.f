// =============================================================================
// Filelist: uvm_interconnect_filelist.f
// Description: VCS Compilation filelist for Block-Level Interconnect UVM Testbench
// =============================================================================

+incdir+rtl/interconnect
+incdir+uvm/if
+incdir+uvm/agents/axi_agent
+incdir+uvm/agents/clk_rst_agent
+incdir+uvm/tb

rtl/third_party/verilog-axi/rtl/arbiter.v
rtl/third_party/verilog-axi/rtl/priority_encoder.v
rtl/third_party/verilog-axi/rtl/axi_interconnect.v
rtl/interconnect/soc_axi_interconnect_wrap_2x9.v
uvm/if/axi_if.sv
uvm/if/clk_rst_if.sv
uvm/agents/axi_agent/axi_assertions.sv
uvm/tb/soc_uvm_pkg.sv
uvm/tb/tb_interconnect_uvm.sv
