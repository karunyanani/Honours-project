// =============================================================================
// filelist.f – VCS/Icarus Verilog flat file list
//
// Secure Communication Gateway SoC
// Spec ref: Section 11 (Project Directory Structure)
//
// Usage (VCS):
//   vcs -full64 -sverilog -timescale=1ns/1ps \
//       -f filelist.f \
//       tb/soc/tb_soc_top.sv
//
// Usage (Icarus Verilog):
//   iverilog -g2012 -f filelist.f tb/soc/tb_soc_top.sv
//
// Include paths:
+incdir+rtl/interconnect
+incdir+tb

// =============================================================================
// Third-party AXI library (Alex Forencich verilog-axi)
// Pinned commit: see docs/ip_versions.md
// =============================================================================
rtl/third_party/verilog-axi/rtl/arbiter.v
rtl/third_party/verilog-axi/rtl/priority_encoder.v
rtl/third_party/verilog-axi/rtl/axi_interconnect.v

// =============================================================================
// AXI Interconnect wrapper (2 masters × 9 slaves)
// =============================================================================
rtl/interconnect/soc_axi_interconnect_wrap_2x9.v

// =============================================================================
// CPU subsystem
// =============================================================================
rtl/cpu/cpu_axi_adapter.v
rtl/cpu/cpu_axi_master.v

// =============================================================================
// Memories
// =============================================================================
rtl/memory/instruction_memory.v
rtl/memory/data_memory.v

// =============================================================================
// Peripherals
// =============================================================================
rtl/peripherals/uart.v
rtl/peripherals/spi.v
rtl/peripherals/gpio.v
rtl/peripherals/timer.v
rtl/peripherals/watchdog.v

// =============================================================================
// Security
// =============================================================================
rtl/security/aes.v

// =============================================================================
// DMA
// =============================================================================
rtl/dma/dma.v

// =============================================================================
// SoC top-level integration
// =============================================================================
rtl/top/soc_top.v
