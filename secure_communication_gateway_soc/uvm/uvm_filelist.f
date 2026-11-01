// =============================================================================
// Filelist: uvm_filelist.f
// Description: Compilation filelist for UVM Verification Suite in VCS
// =============================================================================

// Include directories
+incdir+rtl/interconnect
+incdir+rtl/memory
+incdir+rtl/peripherals
+incdir+rtl/security
+incdir+rtl/dma
+incdir+rtl/cpu
+incdir+rtl/top
+incdir+uvm/if
+incdir+uvm/agents/axi_agent
+incdir+uvm/agents/spi_agent
+incdir+uvm/agents/uart_agent
+incdir+uvm/agents/gpio_agent
+incdir+uvm/agents/interrupt_agent
+incdir+uvm/agents/clk_rst_agent
+incdir+uvm/scoreboard
+incdir+uvm/coverage
+incdir+uvm/env
+incdir+uvm/sequences
+incdir+uvm/tests
+incdir+uvm/tb

// Alex Forencich verilog-axi Third-Party IP
rtl/third_party/verilog-axi/rtl/arbiter.v
rtl/third_party/verilog-axi/rtl/priority_encoder.v
rtl/third_party/verilog-axi/rtl/axi_interconnect.v

// Main 2x9 Interconnect Wrapper
rtl/interconnect/soc_axi_interconnect_wrap_2x9.v

// Memory IP
rtl/memory/instruction_memory.v
rtl/memory/data_memory.v

// Peripherals IP
rtl/peripherals/uart.v
rtl/peripherals/spi.v
rtl/peripherals/gpio.v
rtl/peripherals/timer.v
rtl/peripherals/watchdog.v

// Security & DMA
rtl/security/aes.v
rtl/dma/dma.v

// CPU Subsystem
rtl/cpu/cpu_axi_master.v
rtl/cpu/cpu_axi_adapter.v
rtl/cpu/veer_el2_wrapper.v

// SoC Top
rtl/top/soc_top.v

// UVM Interfaces
uvm/if/axi_if.sv
uvm/if/spi_if.sv
uvm/if/uart_if.sv
uvm/if/gpio_if.sv
uvm/if/interrupt_if.sv
uvm/if/clk_rst_if.sv

// Assertions
uvm/agents/axi_agent/axi_assertions.sv

// UVM Package & Testbench Top
uvm/tb/soc_uvm_pkg.sv
uvm/tb/tb_top.sv
