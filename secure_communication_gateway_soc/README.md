# Secure Communication Gateway SoC

Design and Verification of a RISC-V Based Secure Communication Gateway SoC
with Hardware AES Encryption and Watchdog-Based Fault Recovery.

---

## Project Overview

An industrial secure IoT/sensor SoC featuring:
1. Sensor data acquisition through SPI
2. Hardware AES-128 CTR encryption pipeline
3. Encrypted ciphertext transmission via 8N1 UART
4. Dual-master DMA engine autonomous data movement (SPI → AES → UART)
5. Scoped Watchdog Timer fault detection and recovery
6. CHIPS Alliance VeeR EL2 (RV32IMC) core control via 2×9 AXI4 Interconnect

---

## Repository Structure

```
secure_communication_gateway_soc/
├── config/
│   └── address_map.yaml          # Single authoritative address map
├── docs/
│   ├── FINAL_PROJECT_REPORT.md   # Complete Honours Engineering Final Report
│   ├── UVM_TEST_PLAN.md          # Comprehensive UVM Verification Test Plan (All Cases)
│   ├── UVM_VIP_ARCHITECTURE.md   # UVM Verification IP Architecture & Integration Guide
│   └── ip_versions.md            # Third-party IP versions & interface specs
├── rtl/
│   ├── interconnect/
│   │   ├── soc_axi_interconnect_wrap_2x9.v # 2-master x 9-slave AXI4 wrapper
│   │   └── soc_defines.vh        # Generated Verilog macros & constants
│   ├── cpu/
│   │   ├── cpu_axi_adapter.v     # IFU + LSU 64-to-32 bit AXI4 bridge
│   │   ├── cpu_axi_master.v      # CPU AXI master model/helper
│   │   └── veer_el2_wrapper.v    # VeeR EL2 core top-level wrapper
│   ├── memory/
│   │   ├── instruction_memory.v  # 64 KB AXI4 IMEM with HEX loader
│   │   └── data_memory.v         # 64 KB AXI4 DMEM with byte write strobes
│   ├── peripherals/
│   │   ├── uart.v                # Configurable 8N1 UART with TX FIFO & DMA req
│   │   ├── spi.v                 # SPI master with RX FIFO & DMA req
│   │   ├── gpio.v                # Synchronized DRDY edge detect & IRQ
│   │   ├── timer.v               # Countdown timer with interrupt
│   │   └── watchdog.v            # Scoped reset recovery watchdog
│   ├── security/
│   │   └── aes.v                 # AES-128 CTR engine (10-round pipeline)
│   ├── dma/
│   │   └── dma.v                 # 2nd AXI master (SPI->AES, AES->UART)
│   ├── top/
│   │   └── soc_top.v             # Full SoC integration top module
│   └── third_party/
│       ├── verilog-axi/          # Alex Forencich AXI interconnect library
│       └── Cores-VeeR-EL2/       # CHIPS Alliance VeeR EL2 RISC-V core
├── sw/
│   ├── application/
│   │   └── main.c                # SoC firmware application
│   ├── include/
│   │   ├── soc_map.h             # Memory map definitions
│   │   ├── aes.h, dma.h, gpio.h  # Peripheral register drivers
│   │   └── spi.h, timer.h, uart.h, wdt.h
│   ├── linker/
│   │   └── soc.ld                # Linker script (IMEM/DMEM layout)
│   ├── startup/
│   │   └── startup.S             # Boot code and trap vectors
│   └── build/                    # Firmware compilation artifacts
├── tb/
│   ├── soc_tb_defines.svh        # SystemVerilog testbench macros
│   ├── interconnect/
│   │   └── tb_interconnect.sv    # Interconnect standalone self-checking TB
│   ├── cpu/
│   │   └── tb_cpu_adapter.sv     # CPU AXI adapter standalone TB
│   ├── ip/
│   │   ├── tb_aes.sv             # AES FIPS-197 KAT + CTR testbench
│   │   ├── tb_dma.sv             # DMA transfer testbench
│   │   └── tb_watchdog.sv        # Watchdog scoped recovery testbench
│   └── soc/
│       └── tb_soc_top.sv         # Full SoC integration testbench
├── uvm/
│   ├── UVM_TEST_PLAN.md          # Comprehensive UVM Verification Test Plan
│   ├── agents/                   # Verification IPs (VIPs)
│   │   ├── axi_agent/            # AXI4 Master/Slave VIP & SVA Assertions
│   │   ├── spi_agent/            # SPI Industrial Sensor VIP & Sequencer
│   │   ├── uart_agent/           # Full-Duplex UART VIP & RX/TX Drivers
│   │   ├── gpio_agent/           # GPIO & Pad Verification IP
│   │   ├── interrupt_agent/      # Interrupt & WDT Fault Recovery VIP
│   │   └── clk_rst_agent/        # Dynamic Clock & Reset Generator VIP
│   ├── env/                      # UVM environment (soc_env.sv)
│   ├── if/                       # SystemVerilog interfaces (axi, spi, uart, gpio, irq, clk_rst)
│   ├── sequences/                # Verification sequences & test libraries
│   ├── tests/                    # UVM test cases
│   ├── scoreboard/               # Multi-VIP Scoreboard & FIPS-197 predictor
│   └── coverage/                 # Functional coverage models
├── scripts/
│   ├── generate_address_map.py   # YAML -> Verilog/C/SV address map
│   ├── gen_interconnect_wrap.py  # AXI 2x9 wrapper generator
│   ├── build.sh                  # Simulation and build runner
│   └── run_tests.sh              # Automated regression test runner
├── filelist.f                    # Flat file list for VCS / Icarus Verilog
├── Makefile                      # Standard build and simulation targets
└── README.md                     # Project documentation
```

---

## Address Map

| M Port | Peripheral | Base Address | Size | Access (CPU / DMA) |
|---|---|---|---|---|
| M0 | Instruction Memory | `0x0000_0000` | 64 KB | Read/Write / **Denied** |
| M1 | Data Memory | `0x0001_0000` | 64 KB | Read/Write / Read/Write |
| M2 | UART | `0x1000_0000` | 256 B | Read/Write / Read/Write |
| M3 | Timer | `0x1000_0100` | 256 B | Read/Write / **Denied** |
| M4 | GPIO | `0x1000_0200` | 256 B | Read/Write / **Denied** |
| M5 | AES Engine | `0x1000_0300` | 256 B | Read/Write / Read/Write |
| M6 | DMA Registers | `0x1000_0400` | 256 B | Read/Write / **Denied** |
| M7 | SPI Controller | `0x1000_0500` | 256 B | Read/Write / Read/Write |
| M8 | Watchdog Timer | `0x1000_0600` | 256 B | Read/Write / **Denied** |

*Note: Unmapped addresses and unauthorized DMA accesses return AXI DECERR (`2'b11`).*

---

## Third-Party IP Status

| IP | Repository | Commit Hash |
|---|---|---|
| **VeeR EL2** | https://github.com/chipsalliance/Cores-VeeR-EL2.git | `fa00c8aadc4a077d78b277129c1badf90d881255` |
| **verilog-axi** | https://github.com/alexforencich/verilog-axi.git | `516bd5dadc3365b7f9e225d2af8fe0b8d804fe53` |

---

## Verification Results Summary

| Testbench / Suite | Target Simulator | Checks | Result |
|---|---|---|---|
| `tb/interconnect/tb_interconnect.sv` | Icarus / VCS | 52 assertions across 11 testcases | **100% PASS** |
| `tb/cpu/tb_cpu_adapter.sv` | Icarus / VCS | 23 assertions (IFU/LSU arbitration, byte strobes) | **100% PASS** |
| `tb/ip/tb_aes.sv` | Icarus / VCS | 23 assertions (NIST FIPS-197 KAT, CTR mode) | **100% PASS** |
| `tb/ip/tb_dma.sv` | Icarus / VCS | 19 assertions (Dual-mode DMA transfer, abort) | **100% PASS** |
| `tb/ip/tb_watchdog.sv` | Icarus / VCS | 25 assertions (Scoped reset, W1C cause register) | **100% PASS** |
| `tb/soc/tb_soc_top.sv` | Icarus / VCS | 20 assertions across 8 system testcases | **100% PASS** |
| `tb/soc/tb_soc_firmware.sv` | Icarus / VCS | 6 assertions (End-to-End C Firmware Pipeline) | **100% PASS** |
| `uvm/tb/tb_top.sv` | Synopsys VCS / Verdi | Full UVM 1.2 Suite (4 Test Cases) | **Ready / Synthesized** |

---

## Quick Start & Build Instructions

```bash
# Check RTL synthesizability & lint
make lint

# Compile RISC-V Bare-Metal C Firmware
make firmware

# Run Full SoC End-to-End Simulation with C Firmware
make sim_firmware

# Run Individual IP & Interconnect Unit Tests
make sim_interconnect
make sim_cpu_adapter
make sim_aes
make sim_dma
make sim_watchdog

# Run Hardware Top-Level Integration Testbench
make sim_soc

# Run Synopsys VCS UVM Suite & Launch Verdi
make sim_vcs_uvm
make verdi
```
