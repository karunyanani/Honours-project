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

### 1. Automated RTL Standalone Regression Suite (`./scripts/run_tests.sh`)
Tool: Icarus Verilog v12.0 / Synopsys VCS — **100% PASS across all 7 testbenches (168/168 assertions)**

| Testbench / Suite | Component Verified | Scope & Checks | Pass / Fail |
|---|---|---|:---:|
| `tb/interconnect/tb_interconnect.sv` | 2×9 AXI4 Interconnect | 52 assertions (Fixed-priority S0>S1 arb, DECERR, 9 slaves) | **52 / 0 PASS** |
| `tb/cpu/tb_cpu_adapter.sv` | CPU AXI Adapter | 23 assertions (IFU/LSU arbitration, 64-to-32 conversion, byte strobes) | **23 / 0 PASS** |
| `tb/ip/tb_aes.sv` | Dual-Mode AES Engine | 23 assertions (NIST FIPS-197 ECB KAT, CTR auto-increment, key retention) | **23 / 0 PASS** |
| `tb/ip/tb_dma.sv` | DMA Controller | 19 assertions (Mode 0 SPI→AES, Mode 1 AES→UART, FIFO handshakes) | **19 / 0 PASS** |
| `tb/ip/tb_watchdog.sv` | Watchdog Timer | 25 assertions (Quiescent drain, scoped reset, warm-reset retention, W1C) | **25 / 0 PASS** |
| `tb/soc/tb_soc_top.sv` | Full SoC Hardware | 20 assertions (Power-on state, UART/SPI pads, DMEM, GPIO, Timer) | **20 / 0 PASS** |
| `tb/soc/tb_soc_firmware.sv` | End-to-End Pipeline | 6 assertions (Sensor injection $\to$ SPI $\to$ DMA0 $\to$ AES $\to$ DMA1 $\to$ UART golden match) | **6 / 0 PASS** |
| **Total Automated RTL Checks** | **Full System** | **7/7 Testbenches Executed** | **168 / 168 PASS (100%)** |

### 2. Comprehensive UVM 1.2 Verification Suite (`./scripts/run_all_uvm_tests.sh`)
Standard: IEEE 1800.2 UVM 1.2 / Synopsys VCS & Verdi

| UVM Test Name | Testbench | Verification Focus & Checks | Status |
|---|---|---|:---:|
| `soc_gateway_pipeline_test` | `tb_top.sv` | End-to-End automated datapath: Sensor $\to$ SPI $\to$ DMA0 $\to$ AES $\to$ DMA1 $\to$ UART | **VERIFIED** |
| `soc_reg_access_test` | `tb_top.sv` | Comprehensive R/W bit walk (0x55/0xAA), status read-only, default reset values | **VERIFIED** |
| `soc_access_control_test` | `tb_top.sv` | AXI security matrix: DMA prohibited from IMEM/Timer/GPIO/DMA/WDT (DECERR) | **VERIFIED** |
| `soc_wdt_recovery_test` | `tb_top.sv` | Watchdog timeout stall detection, 8-cycle quiescent drain, scoped reset, W1C cause | **VERIFIED** |
| `soc_aes_test` | `tb_top.sv` / `tb_aes_uvm.sv` | NIST FIPS-197 ECB KAT, CTR Mode 128-bit auto-increment, key retention | **VERIFIED** |
| `soc_dma_test` | `tb_top.sv` / `tb_dma_uvm.sv` | DMA Mode 0 & Mode 1 autonomous transfers, transfer length bounds, FIFO back-pressure | **VERIFIED** |
| `soc_mem_test` | `tb_top.sv` | 64KB IMEM & DMEM boundaries (0x0000_0000, 0x0001_FFFC), walking bits, byte strobes | **VERIFIED** |
| `soc_stress_test` | `tb_top.sv` | 50 continuous rapid interleaved CPU & DMA simultaneous accesses (no deadlock) | **VERIFIED** |
| `soc_spi_test` | `tb_top.sv` | Sensor telemetry burst capture, clock divider scaling, control modes, FIFO overflow | **VERIFIED** |
| `soc_uart_test` | `tb_top.sv` | Full-duplex 8N1 transmission, baud divisor dynamic scaling, TX_DMA_REQ handshakes | **VERIFIED** |

#### Dedicated Block-Level UVM Testbenches
- **`uvm/tb/tb_aes_uvm.sv`**: Standalone AES-128 CTR Engine UVM environment with AXI VIP & SVA checkers.
- **`uvm/tb/tb_dma_uvm.sv`**: Standalone DMA Controller UVM environment verifying master/slave handshakes.
- **`uvm/tb/tb_watchdog_uvm.sv`**: Standalone Watchdog Timer UVM environment verifying quiescent drain & scoped resets.
- **`uvm/tb/tb_interconnect_uvm.sv`**: Standalone 2x9 Interconnect UVM environment testing 2 masters & 9 slave responders.

---

## Quick Start & Build Instructions

```bash
# 1. Run Complete Automated RTL Regression Suite (All 7 Testbenches, 100% PASS)
./scripts/run_tests.sh

# 2. Run Comprehensive UVM 1.2 Verification Suite (Synopsys VCS)
./scripts/run_all_uvm_tests.sh --all

# 3. Run Individual UVM Tests or Block-Level UVM Testbenches
./scripts/run_all_uvm_tests.sh soc_gateway_pipeline_test
./scripts/run_all_uvm_tests.sh soc_aes_test
./scripts/run_all_uvm_tests.sh --block aes
./scripts/run_all_uvm_tests.sh --block dma

# 4. Run via Makefile Targets
make sim_uvm_all           # Run all UVM tests
make sim_uvm_pipeline      # Run UVM pipeline test
make sim_uvm_aes           # Run UVM AES test
make sim_uvm_dma           # Run UVM DMA test
make sim_uvm_wdt           # Run UVM Watchdog test
make sim_uvm_stress        # Run UVM bus stress test
make sim_firmware          # Run full SoC end-to-end simulation with compiled C firmware
make sim_soc               # Run hardware integration testbench
make verdi                 # Launch Synopsys Verdi waveform debugging
make lint                  # Run RTL synthesizability and linting checks
```
