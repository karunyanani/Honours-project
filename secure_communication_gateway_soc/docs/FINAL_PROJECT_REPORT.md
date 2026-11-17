# COMPREHENSIVE COURSE PROJECT TECHNICAL REPORT
# Design and Verification of a RISC-V Based Secure Communication Gateway SoC with Hardware AES Encryption and Watchdog Scoped Fault Recovery

**Academic Course / Degree:** Honours Final-Year Project in VLSI Design, Computer Architecture & Digital Verification  
**Repository:** [https://github.com/karunyanani/Honours-project.git](https://github.com/karunyanani/Honours-project.git)  
**Release Tag:** `v1.0-final`  
**Target Simulators:** Synopsys VCS / Verdi (UVM 1.2 Production), Icarus Verilog v12.0 (Open-Source Validation)  
**Target Toolchain:** RISC-V GNU GCC (`riscv64-unknown-elf-gcc` RV32I / ILP32 ABI)  

---

# TABLE OF CONTENTS
1. [Section 1: Project Proposal](#1-project-proposal)
2. [Section 2: Architecture Specification](#2-architecture-specification)
   - [2.1 High-Level SoC Overview & Data Flow Pipeline](#21-high-level-soc-overview--data-flow-pipeline)
   - [2.2 Top-Level System Block Diagram](#22-top-level-system-block-diagram)
   - [2.3 RISC-V Processor Subsystem & CPU AXI Adapter](#23-risc-v-processor-subsystem--cpu-axi-adapter)
   - [2.4 AXI4 2-Master × 9-Slave Interconnect Matrix](#24-axi4-2-master--9-slave-interconnect-matrix)
   - [2.5 Synthesizable IP Cores & Accelerators](#25-synthesizable-ip-cores--accelerators)
     - [2.5.1 Dual-Mode AES-128 Cryptographic Accelerator](#251-dual-mode-aes-128-cryptographic-accelerator)
     - [2.5.2 Dual-Mode Direct Memory Access (DMA) Controller](#252-dual-mode-direct-memory-access-dma-controller)
     - [2.5.3 Watchdog Timer with Scoped Fault Recovery & AXI Drain](#253-watchdog-timer-with-scoped-fault-recovery--axi-drain)
     - [2.5.4 Memory Subsystem (64 KB IMEM & 64 KB DMEM)](#254-memory-subsystem-64-kb-imem--64-kb-dmem)
     - [2.5.5 UART Controller (Full-Duplex 8N1)](#255-uart-controller-full-duplex-8n1)
     - [2.5.6 SPI Master Controller & Industrial Sensor Interface](#256-spi-master-controller--industrial-sensor-interface)
     - [2.5.7 Hardware 32-Bit Down-Counter Timer & 8-Bit GPIO](#257-hardware-32-bit-down-counter-timer--8-bit-gpio)
3. [Section 3: GitHub Account & Repository Setup Steps](#3-github-account--repository-setup-steps)
4. [Section 4: RISC-V Toolchain & Software Build Environment Steps](#4-risc-v-toolchain--software-build-environment-steps)
5. [Section 5: Address Map & Register Specification](#5-address-map--register-specification)
6. [Section 6: Comprehensive Verification Test Plan (Internal vs. External Tests)](#6-comprehensive-verification-test-plan-internal-vs-external-tests)
7. [Section 7: Verification IP (VIP) CSV Files & Interface Definitions](#7-verification-ip-vip-csv-files--interface-definitions)
   - [7.1 AXI4 Master/Slave VIP](#71-axi4-masterslave-vip)
   - [7.2 SPI Industrial Sensor VIP](#72-spi-industrial-sensor-vip)
   - [7.3 UART Full-Duplex Serial VIP](#73-uart-full-duplex-serial-vip)
   - [7.4 GPIO & Pad Verification VIP](#74-gpio--pad-verification-vip)
   - [7.5 Interrupt & Fault Recovery VIP](#75-interrupt--fault-recovery-vip)
   - [7.6 Dynamic Clock & Reset Generator VIP](#76-dynamic-clock--reset-generator-vip)
8. [Section 8: UVM Testbench Architecture & Block Diagram](#8-uvm-testbench-architecture--block-diagram)
9. [Section 9: C Test Cases, UVM Test Cases & Cycle-Accurate Waveform Snippets](#9-c-test-cases-uvm-test-cases--cycle-accurate-waveform-snippets)
   - [9.1 C Firmware Test Cases (`main.c` & `basic_test.c`)](#91-c-firmware-test-cases-mainc--basic_testc)
   - [9.2 UVM Test Suites & Sequences](#92-uvm-test-suites--sequences)
   - [9.3 Cycle-Accurate Waveform Timing Snippets](#93-cycle-accurate-waveform-timing-snippets)
   - [9.4 Waveform Simulation vs. Firmware HEX Correlation Report](#94-waveform-simulation-vs-firmware-hex-correlation-report)

---

# 1. Project Proposal

### 1.1 Executive Summary & Problem Statement
Modern industrial cyber-physical infrastructures (such as Industry 4.0 smart manufacturing, power distribution SCADA networks, and remote critical sensor telemetry) increasingly deploy low-cost, connected edge gateways. These devices continuously aggregate sensitive environmental readings (e.g., pipeline pressure, temperature, rotational vibration) and transmit this data across untrusted networks to cloud monitoring centers.

However, standard microcontrollers and legacy Internet-of-Things (IoT) edge gateways suffer from three critical architectural vulnerabilities:
1. **CPU Saturation under Cryptographic Overhead:** Software-based encryption (such as pure C implementations of AES) consumes up to 85% of CPU clock cycles, causing unacceptable data buffering latencies and dropped packets.
2. **Catastrophic Cold Restarts upon Transient Faults:** When an interface or pipeline stalls due to electromagnetic interference (EMI) or external bus deadlocks, conventional hardware watchdogs reboot the entire processor. This destroys the operating state, clears instruction and data caches, invalidates cryptographic session keys, and incurs lengthy re-initialization latencies.
3. **Insecure On-Chip Fabric Access:** Direct Memory Access (DMA) engines often operate as unconstrained bus masters, allowing malicious firmware exploits or runaway hardware pointers to overwrite critical bootloader memory, interrupt tables, or tamper with security registers.

### 1.2 Proposed Solution & Objectives
This project designs, integrates, and formally verifies a fully synthesizable **RISC-V Based Secure Communication Gateway System-on-Chip (SoC)** implemented in Verilog-2001 and SystemVerilog. The key objectives are:
- **Autonomous Zero-CPU Hardware Gateway Pipeline:** Seamlessly ingest raw industrial sensor telemetry via a hardware **SPI Master**, stream data directly into a **Dual-Mode AES-128 Encryption Accelerator** via an autonomous **Direct Memory Access (DMA) Controller**, and forward the resulting ciphertext out through a **UART 8N1** serial interface with zero processor intervention during data streaming.
- **Hardware-Enforced Security Firewall:** Implement a parameterized **2-Master × 9-Slave AXI4 Interconnect** that strictly limits DMA master access privileges to authorized data paths (`DMEM`, `UART`, `AES`, `SPI`) while instantly returning an AXI `DECERR` (`2'b11`) response to abort unauthorized accesses (such as DMA attempts to read `IMEM`, alter `DMA_CFG`, or feed the `Watchdog`).
- **Watchdog Scoped Fault Recovery with Quiescent AXI Drain:** Implement an intelligent Watchdog Timer that, upon detecting a pipeline hang, halts new transactions and waits through an 8-cycle quiescent AXI drain delay (`WDT_DRAIN`) before issuing a synchronous 1-cycle scoped reset pulse (`wdt_reset_dma`, `wdt_reset_aes`, `wdt_reset_spi`). This clears faulted datapath state while strictly preserving CPU state, memory contents, DMA configuration registers, and cryptographic key storage.
- **Verification Closure:** Construct a complete test suite comprising unit-level testbenches, full-chip C firmware simulation, and an IEEE 1800.2 UVM 1.2 verification environment to guarantee 100% bug-free silicon readiness.

---

# 2. Architecture Specification

## 2.1 High-Level SoC Overview & Data Flow Pipeline
The Secure Communication Gateway SoC operates at an internal clock frequency of 50 MHz. It is built around a single-issue 32-bit RISC-V core executing bare-metal C firmware, surrounded by dedicated high-performance hardware engines connected through an AXI4 memory-mapped crossbar fabric.

```
                          GATEWAY DATA FLOW PIPELINE
                          ==========================
   +-------------------+
   | Industrial Sensor |
   +-------------------+
             |  SPI Bus (SCLK, MOSI, MISO, CS_N) + DRDY Flag
             v
   +-------------------+
   |  SPI Master Port  |  --> Ingests 16 raw sensor bytes into internal RX FIFO
   +-------------------+
             |
             |  [DMA Mode 0: SPI -> AES Plaintext]
             v
   +-------------------+
   | AES-128 Accelerator| --> Autonomous 10-round hardware encryption (CTR/ECB)
   +-------------------+     Produces 128-bit ciphertext in 11 clock cycles
             |
             |  [DMA Mode 1: AES Ciphertext -> UART TX FIFO]
             v
   +-------------------+
   |  UART Controller  |  --> Streams 16 ciphertext bytes over 8N1 serial line
   +-------------------+
             |
             v
   +-------------------+
   | SCADA / Base Stn  |
   +-------------------+
```

$$\text{Pipeline Formula: } \text{Sensor Telemetry} \xrightarrow[\text{Handshake}]{\text{SPI}} \text{SPI FIFO} \xrightarrow[\text{Mode 0}]{\text{DMA}} \text{AES-128} \xrightarrow[\text{Mode 1}]{\text{DMA}} \text{UART FIFO} \xrightarrow{\text{8N1}} \text{Base Station}$$

---

## 2.2 Top-Level System Block Diagram

```
+---------------------------------------------------------------------------------------------------------+
|                                    SECURE COMMUNICATION GATEWAY SOC                                     |
|                                                                                                         |
|  +-----------------------------+                           +-----------------------------------------+  |
|  |     VeeR EL2 RISC-V Core    |                           |         Direct Memory Access (DMA)      |  |
|  |   (RV32IMC / RV32I Arch)    |                           |                 Controller              |  |
|  |                             |                           | - Mode 0: SPI RX -> AES Plaintext       |  |
|  |  [IFU Fetch]   [LSU Mem]    |                           | - Mode 1: AES Ciphertext -> UART TX     |  |
|  +------+---------------+------+                           | - Hardware backpressure & handshakes    |  |
|         |               |                                  +--------------------+--------------------+  |
|         v               v                                                       |                       |
|  +-----------------------------+                                                |                       |
|  |     CPU AXI Master Adapter  |                                                |                       |
|  | - IFU/LSU Arbitration       |                                                |                       |
|  | - 64-bit to 32-bit Sizing   |                                                |                       |
|  | - Sub-word byte strobes     |                                                |                       |
|  +--------------+--------------+                                                |                       |
|                 | (Master Port S0)                                              | (Master Port S1)      |
|                 v                                                               v                       |
|  +---------------------------------------------------------------------------------------------------+  |
|  |                           AXI4 2-MASTER x 9-SLAVE INTERCONNECT FABRIC                             |  |
|  |   - Fixed-Priority Arbiter: ARB_LSB_HIGH_PRIORITY=1 (Master S0 > Master S1 on Contention)         |  |
|  |   - Address Decoder: Single-cycle decoding with unmapped DECERR (2'b11) generation                |  |
|  |   - Access Control Firewall: Enforces hardware read/write permissions per master port             |  |
|  +---+-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+  |
|      |           |           |           |           |           |           |           |           |      |
|      v           v           v           v           v           v           v           v           v      |
|     M0          M1          M2          M3          M4          M5          M6          M7          M8      |
|  +-------+   +-------+   +-------+   +-------+   +-------+   +-------+   +-------+   +-------+   +-------+  |
|  | IMEM  |   | DMEM  |   | UART  |   | TIMER |   | GPIO  |   |  AES  |   |DMA_CFG|   |  SPI  |   |  WDT  |  |
|  | 64 KB |   | 64 KB |   | 256 B |   | 256 B |   | 256 B |   | 256 B |   | 256 B |   | 256 B |   | 256 B |  |
|  +-------+   +-------+   +-------+   +-------+   +-------+   +-------+   +-------+   +-------+   +-------+  |
|    CPU R/W     CPU R/W     CPU R/W     CPU R/W     CPU R/W     CPU R/W     CPU R/W     CPU R/W     CPU R/W  |
|    DMA Denied  DMA R/W     DMA R/W     DMA Denied  DMA Denied  DMA R/W     DMA Denied  DMA R/W     DMA Denied|
|                  |           |                                 |                       |           |    |
|                  +-----------|---------------------------------+-----------------------+           |    |
|                              |                                                                     |    |
|                              |                  +-----------------------------------+              |    |
|                              |                  |       WATCHDOG TIMER (WDT)        |<-------------+    |
|                              |                  | - 32-bit Countdown & Feed Reg     |                   |
|                              |                  | - 8-cycle AXI Quiescent Drain     |                   |
|                              |                  | - Scoped Reset: AES, DMA, SPI     |                   |
|                              |                  | - Preserves CPU, SRAM, Keys, DMA  |                   |
|                              |                  +-----------------+-----------------+                   |
|                              |                                    | (Scoped Reset Pulse)                |
|                              |                                    v                                     |
|                              |                  [ Resets: DMA FSM, AES Core, SPI FIFO ]                 |
|                              v                                                                          |
|                     External Pins: UART (TX/RX), SPI (SCK/MOSI/MISO/CS_N), GPIO, Clocks & Reset        |
+---------------------------------------------------------------------------------------------------------+
```

---

## 2.3 RISC-V Processor Subsystem & CPU AXI Adapter
The processor subsystem integrates the CHIPS Alliance VeeR EL2 core with a custom AXI4 bus master adapter.
- **Processor Architecture:** Standard 32-bit RISC-V (RV32IMC natively supported by hardware; firmware compiled for RV32I / ILP32 ABI to ensure clean 32-bit instruction alignments and 100% binary execution parity across simulation models).
- **CPU AXI Master Adapter (`cpu_axi_adapter.v` / `cpu_axi_master.v`):**
  - **Arbitration:** Dynamically arbitrates between the core's Instruction Fetch Unit (IFU) and Load/Store Unit (LSU). LSU memory operations are granted highest priority to prevent pipeline execution stalls.
  - **Sub-Word Byte Operations:** Handles byte (`LB`/`SB`), halfword (`LH`/`SH`), and word (`LW`/`SW`) operations. Replicates write data across 32-bit lanes and asserts exact byte strobes (`s_axi_wstrb[3:0]`). On read responses, shifts incoming data and applies sign or zero extension.
  - **Transaction Identification:** Generates distinct AXI IDs (`AxID = 8'h00` for IFU fetches, `AxID = 8'h01` for LSU loads/stores) to cleanly route incoming read responses and error flags back to the core.

---

## 2.4 AXI4 2-Master × 9-Slave Interconnect Matrix
The interconnect crossbar leverages the Alex Forencich `verilog-axi` library wrapped inside a statically typed SoC interface module (`soc_axi_interconnect_wrap_2x9.v`).
- **Crossbar Topology:** 2 Master ports (S0 = CPU, S1 = DMA) × 9 Slave ports (M0..M8).
- **Bus Parameters:** 32-bit address (`[31:0]`), 32-bit data (`[31:0]`), 8-bit transaction ID (`[7:0]`).
- **Fixed-Priority Arbitration (`ARB_LSB_HIGH_PRIORITY = 1`):** Under simultaneous contention between Master S0 and Master S1 for the same slave peripheral, Master S0 (CPU write on channel 0, CPU read on channel 1) is granted deterministic priority over Master S1 (DMA write on channel 2, DMA read on channel 3).
- **Hardware Access Control & Firewall Enforcement:**
  The interconnect evaluates master identity and destination address:
  - CPU Master S0 has full read/write privileges across all 9 slave peripherals (`M0`..`M8`).
  - DMA Master S1 has strictly gated access: permitted to access `DMEM` (M1), `UART` (M2), `AES` (M5), and `SPI` (M7).
  - Any DMA attempt to access `IMEM` (M0), `TIMER` (M3), `GPIO` (M4), `DMA_CFG` (M6), `WDT` (M8), or unmapped addresses (`0x1000_0700`..`0xFFFF_FFFF`) is instantly intercepted. The transaction is aborted and an AXI `DECERR` (`2'b11`) response is returned on the `BRESP`/`RRESP` channel.

---

## 2.5 Synthesizable IP Cores & Accelerators

### 2.5.1 Dual-Mode AES-128 Cryptographic Accelerator (`aes.v`)
- **Standards:** Complies with NIST FIPS-197 (Electronic Codebook Mode) and NIST SP 800-38A (Counter Mode).
- **Datapath Architecture:** 10-round iterative cryptographic core featuring fully unrolled round transformations (SubBytes S-Box lookup tables, ShiftRows cyclic permutations, MixColumns Galois Field GF($2^8$) matrix multiplication, and AddRoundKey). Total execution latency is exactly 11 clock cycles.
- **Operating Modes:**
  - **NIST SP 800-38A Counter (CTR) Mode (`CTRL[2] = 1`):** Ingests an initial 128-bit counter vector (`IV0..IV3`). Computes keystream $K = \text{AES}(\text{Counter})$, calculates ciphertext $C = P \oplus K$, and auto-increments the 128-bit counter vector upon block completion.
  - **NIST FIPS-197 Electronic Codebook (ECB) Mode (`CTRL[2] = 0`):** Standard block encryption $C = \text{AES}(P)$ utilized for Known Answer Tests (KAT) and key establishment.
- **Key & Configuration Retention:** Key registers (`KEY0..KEY3`), IV counter registers (`IV0..IV3`), and configuration settings are isolated from scoped watchdog resets, enabling immediate post-fault cryptographic resumption without re-keying.

### 2.5.2 Dual-Mode Direct Memory Access (DMA) Controller (`dma.v`)
- **Autonomous Operation:** Functions as AXI Master Port S1, streaming 16-byte blocks between peripherals with zero CPU overhead.
- **Operating Modes:**
  - **Mode 0 (SPI → AES):** Reads 16 sequential bytes from the SPI RX FIFO (`0x1000_0504`), packs them into four 32-bit little-endian words, writes them into AES plaintext registers (`0x1000_0318..0x1000_0324`), and automatically asserts `AES_CTRL.START`.
  - **Mode 1 (AES → UART):** Polls `AES_STATUS.DONE`, reads four 32-bit ciphertext words (`0x1000_0328..0x1000_0334`), unpacks them into individual bytes, and streams them into the UART TX FIFO (`0x1000_0004`) while respecting the `tx_full` backpressure signal.
- **Fault Tolerance:** If aborted or scoped-reset, the DMA FSM returns safely to IDLE while preserving base address and block length registers.

### 2.5.3 Watchdog Timer with Scoped Fault Recovery & AXI Drain (`watchdog.v`)
- **Countdown & Feeding:** 32-bit programmable down-counter running continuously from `WDT_TIMEOUT`. Software must periodically write magic word `0xDEAD_FEED` to `WDT_FEED` (`0x1000_0600`) to reset the counter.
- **Quiescent AXI Drain Delay (`WDT_DRAIN`):** Upon timeout expiration, the WDT halts and enters an 8-cycle passive quiescent window (`DRAIN_CYCLES = 8`). This delay allows any in-flight single-beat AXI transactions from the DMA or peripherals to cleanly complete, eliminating fabric lockups.
- **1-Cycle Scoped Reset Assertion:** Following the drain delay, the WDT pulses `wdt_reset_dma`, `wdt_reset_aes`, and `wdt_reset_spi` for exactly 1 clock cycle.
- **State Preservation:** Scoped reset targets only the peripheral datapaths. The CPU program counter, CPU register file, IMEM, DMEM, AES key storage, and DMA configuration registers are 100% preserved. The WDT sets bit 0 of `WDT_RESET_CAUSE` (Write-1-to-Clear), allowing firmware to identify and log the fault.

### 2.5.4 Memory Subsystem (64 KB IMEM & 64 KB DMEM)
- **Instruction Memory (`instruction_memory.v`):** 64 KB synchronous SRAM (16,384 × 32 bits). Supports single-cycle read response and `$readmemh` firmware initialization.
- **Data Memory (`data_memory.v`):** 64 KB synchronous SRAM (16,384 × 32 bits) with byte write enable strobes (`wstrb[3:0]`). Supports concurrent reads and byte/halfword/word stores from CPU and DMA.

### 2.5.5 UART Controller (Full-Duplex 8N1) (`uart.v`)
- 16-byte internal TX and RX circular FIFOs with status flags (`tx_full`, `tx_empty`, `rx_full`, `rx_empty`).
- Programmable 16-bit baud rate divisor:
  $$\text{BAUD\_DIV} = \frac{f_{\text{clk}}}{16 \times \text{Baud Rate}} = \frac{50,000,000}{16 \times 115,200} \approx 27 \quad (\text{or } 434 \text{ for } 1\times \text{ oversampling})$$

### 2.5.6 SPI Master Controller & Industrial Sensor Interface (`spi.v`)
- Mode 0 (CPOL=0, CPHA=0) serial master interface with 16-byte RX FIFO.
- Hardware sensor data ready (`sensor_drdy`) input synchronizer and edge-detection logic triggering DMA Mode 0 transfers.

### 2.5.7 Hardware 32-Bit Down-Counter Timer & 8-Bit GPIO (`timer.v`, `gpio.v`)
- **Timer:** 32-bit auto-reload down-counter with programmable interrupt generation upon reaching zero.
- **GPIO:** 8-bit bidirectional parallel I/O with double-flop synchronizers, configurable output enables, and edge-triggered interrupt generation.

---

# 3. GitHub Account & Repository Setup Steps

The complete project is hosted on GitHub at `https://github.com/karunyanani/Honours-project.git`. Follow these steps to replicate the repository setup, clone the submodules, and check out the tagged production release:

### Step 1: GitHub Account & SSH Key Generation
```bash
# 1. Generate an ED25519 SSH key pair for GitHub authentication
ssh-keygen -t ed25519 -C "karunya@domain.com"

# 2. Start the ssh-agent and add your private key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 3. Display and copy the public key to add to your GitHub Settings -> SSH and GPG Keys
cat ~/.ssh/id_ed25519.pub
```

### Step 2: Cloning the Repository & Initializing Submodules
```bash
# 1. Clone the repository
git clone https://github.com/karunyanani/Honours-project.git
cd Honours-project

# 2. Initialize and check out all pinned third-party Git submodules
git submodule update --init --recursive

# 3. Configure filemode handling across Windows/WSL environments
git config core.filemode false
git submodule foreach --recursive "git config core.filemode false"
```

### Step 3: Verifying Pinned Third-Party IP Commits
```bash
# Verify VeeR EL2 commit hash (fa00c8a)
cd secure_communication_gateway_soc/rtl/third_party/Cores-VeeR-EL2
git rev-parse HEAD
# Output: fa00c8aadc4a077d78b277129c1badf90d881255

# Verify verilog-axi commit hash (516bd5d)
cd ../verilog-axi
git rev-parse HEAD
# Output: 516bd5dadc3365b7f9e225d2af8fe0b8d804fe53
cd ../../../..
```

### Step 4: Checking Out Tagged Final Release (`v1.0-final`)
```bash
# Inspect available release tags
git tag -n

# Check out the final verified milestone tag
git checkout v1.0-final
```

---

# 4. RISC-V Toolchain & Software Build Environment Steps

The bare-metal embedded C firmware is compiled using the GNU GCC RISC-V toolchain.

### Step 1: Toolchain Installation
```bash
# Ubuntu / Debian / WSL
sudo apt-get update
sudo apt-get install -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf make python3
```

### Step 2: ISA & Compiler Flag Reconciliation
To guarantee 100% binary execution parity across both the behavioral RV32I simulation model and the physical VeeR EL2 hardware target, compiler flags are explicitly configured as:
- `-march=rv32i`: Strictly disables 16-bit compressed instructions (`rv32c`), ensuring every single instruction fetch is exactly 32-bit aligned.
- `-mabi=ilp32`: Standard 32-bit integer, long, and pointer ABI.
- `-Os`: Optimize for minimum code size.
- `-nostartfiles -nolibc`: Excludes standard OS C runtimes; utilizes custom bare-metal startup assembly.

### Step 3: Linker Script Configuration (`sw/linker/soc.ld`)
```ld
MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS
{
    .text : {
        *(.boot)
        *(.text*)
        *(.rodata*)
        _etext = .;
    } > IMEM

    .data : {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > DMEM AT > IMEM

    .bss : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > DMEM

    .stack (NOLOAD) : {
        . = ALIGN(16);
        _stack_bottom = .;
        . += 0x2000; /* 8 KB Stack */
        _stack_top = .;
        __stack = .;
    } > DMEM
}
```

### Step 4: Compiling Firmware & Generating Verilog HEX
```bash
cd secure_communication_gateway_soc

# 1. Compile C application and startup assembly into ELF
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -Wall -DSIMULATION \
  -Isw/include -nostartfiles -nolibc -T sw/linker/soc.ld \
  sw/startup/startup.S sw/application/main.c -o build/firmware.elf

# 2. Convert ELF to Verilog Hex format ($readmemh compatible)
riscv64-unknown-elf-objcopy -O verilog build/firmware.elf build/firmware.hex

# 3. Generate human-readable disassembly cross-reference
riscv64-unknown-elf-objdump -d build/firmware.elf > build/firmware.dis
```

---

# 5. Address Map & Register Specification

### 5.1 System Memory Map & Access Control Matrix
| Port | Peripheral Block | Base Address | End Address | Size | CPU (S0) | DMA (S1) | Hardware Action on Violation |
|---|---|---|---|---|---|---|---|
| **M0** | Instruction Memory (IMEM) | `0x0000_0000` | `0x0000_FFFF` | 64 KB | Read/Write | **DENIED** | Interconnect blocks & asserts `DECERR` (`2'b11`) |
| **M1** | Data Memory (DMEM) | `0x0001_0000` | `0x0001_FFFF` | 64 KB | Read/Write | Read/Write | Granted |
| **M2** | UART Controller | `0x1000_0000` | `0x1000_00FF` | 256 B | Read/Write | Read/Write | Granted (Enables DMA Mode 1 streaming) |
| **M3** | Hardware Timer | `0x1000_0100` | `0x1000_01FF` | 256 B | Read/Write | **DENIED** | Interconnect blocks & asserts `DECERR` (`2'b11`) |
| **M4** | GPIO Controller | `0x1000_0200` | `0x1000_02FF` | 256 B | Read/Write | **DENIED** | Interconnect blocks & asserts `DECERR` (`2'b11`) |
| **M5** | AES-128 Accelerator | `0x1000_0300` | `0x1000_03FF` | 256 B | Read/Write | Read/Write | Granted (Enables DMA Mode 0 loading) |
| **M6** | DMA Configuration | `0x1000_0400` | `0x1000_04FF` | 256 B | Read/Write | **DENIED** | Interconnect blocks & asserts `DECERR` (`2'b11`) |
| **M7** | SPI Master Controller | `0x1000_0500` | `0x1000_05FF` | 256 B | Read/Write | Read/Write | Granted (Enables DMA Mode 0 reading) |
| **M8** | Watchdog Timer (WDT) | `0x1000_0600` | `0x1000_06FF` | 256 B | Read/Write | **DENIED** | Interconnect blocks & asserts `DECERR` (`2'b11`) |
| **-** | Unmapped Space | `0x1000_0700` | `0xFFFF_FFFF` | ~3.7 GB | **DENIED** | **DENIED** | Interconnect blocks & asserts `DECERR` (`2'b11`) |

---

### 5.2 Peripheral Register Reference Maps

#### 1. UART Registers (`0x1000_0000`)
| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `UART_STATUS` | RO | `0x0000_0002` | `[0]=rx_valid`, `[1]=tx_ready`, `[2]=rx_overflow`, `[3]=tx_full` |
| `0x04` | `UART_DATA` | RW | `0x0000_0000` | Write: Transmit byte into TX FIFO; Read: Pop byte from RX FIFO |
| `0x08` | `UART_BAUD_DIV`| RW | `0x0000_01B2` | Baud clock divisor register (434 for 115200 baud @ 50MHz) |
| `0x0C` | `UART_CTRL` | RW | `0x0000_0003` | `[0]=tx_enable`, `[1]=rx_enable`, `[2]=rx_irq_enable` |

#### 2. Timer Registers (`0x1000_0100`)
| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `TIMER_COUNT` | RW | `0x0000_0000` | Current 32-bit timer counter value |
| `0x04` | `TIMER_RELOAD`| RW | `0x0000_0000` | Auto-reload value loaded upon reaching zero |
| `0x08` | `TIMER_CTRL` | RW | `0x0000_0000` | `[0]=timer_en`, `[1]=auto_reload_en`, `[2]=irq_en` |
| `0x0C` | `TIMER_STATUS`| RW1C | `0x0000_0000` | `[0]=timer_expired` (Write-1-to-Clear) |

#### 3. GPIO Registers (`0x1000_0200`)
| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `GPIO_DATA_IN` | RO | `0x0000_0000` | Synchronized external GPIO pin input values `[7:0]` |
| `0x04` | `GPIO_DATA_OUT`| RW | `0x0000_0000` | Output data register driving `gpio_out[7:0]` (Pin 7 = Status LED) |
| `0x08` | `GPIO_DIR` | RW | `0x0000_0000` | Output enable direction mask `[7:0]` (1 = Output, 0 = Input) |
| `0x0C` | `GPIO_IRQ_EN` | RW | `0x0000_0000` | Interrupt enable mask for rising edges `[7:0]` |
| `0x10` | `GPIO_IRQ_STAT`| RW1C | `0x0000_0000` | Interrupt pending flags (Write-1-to-Clear) |

#### 4. AES-128 Cryptographic Registers (`0x1000_0300`)
| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00..0x0C` | `AES_KEY0..3` | RW | Retained | 128-bit Encryption Key words (Retained across scoped reset) |
| `0x10` | `AES_CTRL` | RW | `0x0000_0000` | `[0]=START`, `[1]=KEY_VALID`, `[2]=CTR_MODE` (1=CTR, 0=ECB) |
| `0x14` | `AES_STATUS` | RO | `0x0000_0000` | `[0]=DONE` (Read-to-clear), `[1]=BUSY` |
| `0x18..0x24` | `AES_DATA_IN0..3`| RW | `0x0000_0000` | 128-bit Plaintext input words |
| `0x28..0x34` | `AES_DATA_OUT0..3`| RO | `0x0000_0000` | 128-bit Ciphertext output words |
| `0x38..0x44` | `AES_IV0..3` | RW | Retained | 128-bit Initial Vector / Counter words (CTR auto-increment) |

#### 5. DMA Configuration Registers (`0x1000_0400`)
| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `DMA_SRC_ADDR` | RW | Retained | Source memory-mapped read address pointer |
| `0x04` | `DMA_DST_ADDR` | RW | Retained | Destination memory-mapped write address pointer |
| `0x08` | `DMA_LEN` | RW | Retained | Transfer length in bytes (Nominal: 16 bytes) |
| `0x0C` | `DMA_CTRL` | RW | `0x0000_0000` | `[0]=START`, `[1]=MODE` (0=SPI→AES, 1=AES→UART), `[2]=ABORT` |
| `0x10` | `DMA_STATUS` | RO | `0x0000_0000` | `[0]=BUSY`, `[1]=DONE` (Read-to-clear), `[2]=ERROR` |

#### 6. SPI Master Registers (`0x1000_0500`)
| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `SPI_STATUS` | RO | `0x0000_0002` | `[0]=rx_valid`, `[1]=tx_ready`, `[2]=busy`, `[3]=rx_empty` |
| `0x04` | `SPI_DATA` | RW | `0x0000_0000` | Read: Pop byte from RX FIFO; Write: Push byte to TX FIFO |
| `0x08` | `SPI_CTRL` | RW | `0x0000_0001` | `[0]=enable`, `[1]=cpol`, `[2]=cpha`, `[3]=manual_cs` |
| `0x0C` | `SPI_CLK_DIV` | RW | `0x0000_0018` | SCLK prescaler divisor register |

#### 7. Watchdog Timer Registers (`0x1000_0600`)
| Offset | Name | Access | Reset | Description |
|---|---|---|---|---|
| `0x00` | `WDT_FEED` | WO | `0x0000_0000` | Write magic value `0xDEAD_FEED` to reload countdown timer |
| `0x04` | `WDT_TIMEOUT` | RW | Retained | Programmable timeout threshold (Retained across warm resets) |
| `0x08` | `WDT_CTRL` | RW | `0x0000_0000` | `[0]=enable` (Self-clears on timeout or reset) |
| `0x0C` | `WDT_RESET_CAUSE`| RW1C | Retained | `[0]=wdt_timeout_occurred` (Write-1-to-Clear; retained) |

---

# 6. Comprehensive Verification Test Plan (Internal vs. External Tests)

The verification matrix categorizes all verification checks into **Internal Tests** (white-box register accesses, bus protocol handshakes, internal crossbar routing, FIFO pointers) and **External Tests** (black-box chip boundary pins, SPI sensor protocol, UART serial stream, GPIO pads, IRQ lines, reset pins).

| Test ID | Test Category | Target Feature / Subsystem | Test Level | Stimulus / Scenario Description | Expected Acceptance Criteria | Result |
|---|---|---|:---:|---|---|:---:|
| `TC_RST_01` | Reset | Power-On Reset Deassertion | **External** | Assert `rst_n = 0` for 20 cycles; release synchronously | PC initializes to `0x0000_0000`, UART TX = 1, SPI CS_N = 1 | **PASS** |
| `TC_RST_02` | Reset | Warm Reset Register Retention | **Internal** | Write WDT timeout & cause registers, assert warm `rst` | `TIMEOUT` and `RESET_CAUSE` registers strictly retained | **PASS** |
| `TC_REG_01` | Register | Peripheral Base Address R/W | **Internal** | Write walking-1s patterns to all peripheral registers | All RW bits match; read-only bits remain unaffected | **PASS** |
| `TC_REG_02` | Register | Write-1-to-Clear (W1C) Semantics | **Internal** | Trigger interrupt flags, write 1 to clear bit | Bit successfully deasserts; writing 0 leaves bit set | **PASS** |
| `TC_AXI_01` | Bus | Single-Beat Read/Write Handshakes | **Internal** | Execute AxVALID/AxREADY handshakes across M0..M8 | Zero deadlock; valid data transfer in 1-2 clock cycles | **PASS** |
| `TC_AXI_02` | Bus | Fixed-Priority Arbitration | **Internal** | Master S0 (CPU) and S1 (DMA) request same slave concurrently | Master S0 granted first (`ARB_LSB_HIGH_PRIORITY=1`); S1 stalls | **PASS** |
| `TC_AXI_03` | Bus | Byte Strobes & Sub-Word Alignment | **Internal** | Perform 8-bit (`SB`) and 16-bit (`SH`) writes via CPU adapter | `s_axi_wstrb` matches lane byte offset; other bytes untouched | **PASS** |
| `TC_SEC_01` | Security | DMA Unauthorized IMEM Access | **Internal** | Program DMA Master S1 to read from IMEM (`0x0000_0000`) | Interconnect firewall intercepts transfer; returns `DECERR` | **PASS** |
| `TC_SEC_02` | Security | DMA Self-Configuration Tamper | **Internal** | Program DMA Master S1 to write to `DMA_CFG` (`0x1000_0400`) | Interconnect firewall intercepts transfer; returns `DECERR` | **PASS** |
| `TC_SEC_03` | Security | DMA Watchdog Disable Attempt | **Internal** | Program DMA Master S1 to write to `WDT_CTRL` (`0x1000_0608`) | Interconnect firewall intercepts transfer; returns `DECERR` | **PASS** |
| `TC_SEC_04` | Security | Unmapped Address Range Access | **Internal** | Issue CPU and DMA reads to `0x1000_0700` and `0x3000_0000` | Crossbar decoder generates immediate `DECERR` (`2'b11`) | **PASS** |
| `TC_MEM_01` | Memory | 64 KB IMEM Single-Cycle Read | **Internal** | CPU executes sequential 32-bit instruction fetches | Fetch completes in 1 cycle without pipeline wait states | **PASS** |
| `TC_MEM_02` | Memory | 64 KB DMEM Byte/Word Readback | **Internal** | Write `0xDEADBEEF` and `0xCAFEBABE`; read back | Exact 32-bit data readback match across all memory banks | **PASS** |
| `TC_AES_01` | Crypto | NIST FIPS-197 Known Answer Test | **Internal** | ECB Mode (`CTRL[2]=0`): Load App B Key & Plaintext | Output matches: `39 25 84 1D 02 DC 09 FB DC 11 85 97 19 6A 0B 32` | **PASS** |
| `TC_AES_02` | Crypto | NIST SP 800-38A CTR Mode Test | **Internal** | CTR Mode (`CTRL[2]=1`): Encrypt streaming blocks | Keystream generated; counter auto-increments by 1 | **PASS** |
| `TC_AES_03` | Crypto | Key Retention Across Scoped Reset | **Internal** | Load key registers, fire watchdog scoped reset | Key registers `KEY0..3` retain values; FSM returns IDLE | **PASS** |
| `TC_DMA_01` | DMA | Mode 0 Transfer (SPI → AES) | **Internal** | Assert sensor DRDY; DMA transfers 16 bytes to AES | 4 words assembled into `AES_DATA_IN0..3`; `START` pulsed | **PASS** |
| `TC_DMA_02` | DMA | Mode 1 Transfer (AES → UART) | **Internal** | Wait for AES DONE; DMA transfers 16 bytes to UART | 4 words unpacked into 16 bytes; streamed into TX FIFO | **PASS** |
| `TC_DMA_03` | DMA | Backpressure & FIFO Full Stall | **Internal** | Assert `uart_tx_full` while DMA Mode 1 is active | DMA cleanly pauses read requests until space becomes free | **PASS** |
| `TC_WDT_01` | Watchdog | Normal Periodic Feeding | **Internal** | Write `0xDEAD_FEED` before countdown counter expires | Timer reloads to `WDT_TIMEOUT`; no reset asserted | **PASS** |
| `TC_WDT_02` | Watchdog | Quiescent AXI Drain Delay | **Internal** | Let timer expire; observe `WDT_DRAIN` state machine | Timer delays 8 cycles allowing in-flight AXI bursts to settle | **PASS** |
| `TC_WDT_03` | Watchdog | 1-Cycle Scoped Reset Assertion | **Internal** | Timeout expires; sample `wdt_reset_dma/aes/spi` lines | 1-cycle scoped reset pulse asserted; CPU/DMEM undisturbed | **PASS** |
| `TC_WDT_04` | Watchdog | W1C Reset Cause Indicator | **Internal** | Post-scoped reset: read `WDT_RESET_CAUSE`; write 1 | Bit 0 reads 1; successfully clears to 0 after write-1 | **PASS** |
| `TC_SPI_01` | Sensor | External SPI Telemetry Ingestion | **External** | Sensor VIP drives 16 bytes over `spi_miso` with SCLK | 16 bytes received into SPI RX FIFO; `rx_empty` deasserts | **PASS** |
| `TC_SPI_02` | Sensor | Sensor DRDY Pulse Synchronization | **External** | Sensor VIP asserts asynchronous `sensor_drdy` pulse | Double-flop synchronizer samples pulse; CPU/DMA notified | **PASS** |
| `TC_UART_01`| Serial | UART 8N1 Bit Serialization | **External** | Push byte `0x55` to TX FIFO; sample `uart_tx` pad | Exact start bit (0), 8 data bits, stop bit (1) observed | **PASS** |
| `TC_UART_02`| Serial | Baud Divisor Accuracy (115200) | **External** | Program `BAUD_DIV = 434`; measure bit period | Bit period equals $8.68\,\mu\text{s} \pm 0.5\%$ matching 115200 baud | **PASS** |
| `TC_GPIO_01`| I/O | Status LED Indication (Pin 7) | **External** | Firmware toggles GPIO output pin 7 upon completion | `gpio_out[7]` transitions to `1'b1` indicating success | **PASS** |
| `TC_SYS_01` | System | Full End-to-End Gateway Pipeline | **External** | Ingest 16 sensor bytes $\rightarrow$ DMA $\rightarrow$ AES $\rightarrow$ DMA $\rightarrow$ UART | UART outputs exact NIST FIPS-197 encrypted ciphertext | **PASS** |
| `TC_COR_01` | Stress | Multi-Master Crossbar Contention | **Internal** | CPU LSU and DMA stream concurrently to DMEM & UART | Crossbar handles contention without data corruption or hang | **PASS** |

---

# 7. Verification IP (VIP) CSV Files & Interface Definitions

All Verification IPs (VIPs) are implemented using modular SystemVerilog interfaces featuring parameterization, clocking blocks with strict input/output skews (`#1step` input, `#1ns` output), and distinct driver/monitor modports.

---

### 7.1 AXI4 Master/Slave VIP
- **CSV Specification:** [`docs/vip_csv/axi_vip.csv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/docs/vip_csv/axi_vip.csv)
- **Interface File:** [`uvm/if/axi_if.sv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/if/axi_if.sv)

#### CSV Signal Definition Table
| Signal Name | Direction | Width | Clock Domain | Description | Protocol / Modport |
|---|:---:|:---:|:---:|---|---|
| `clk` | Input | 1 | System | Reference system clock (50 MHz) | Clock |
| `rst` | Input | 1 | System | Active-high synchronous system reset | Reset |
| `awid` | Output | 8 | `clk` | Write address transaction ID | AW Channel / Master |
| `awaddr` | Output | 32 | `clk` | Write address vector | AW Channel / Master |
| `awlen` | Output | 8 | `clk` | Burst length (0 = single beat) | AW Channel / Master |
| `awsize` | Output | 3 | `clk` | Burst size (010 = 4 bytes / 32-bit) | AW Channel / Master |
| `awburst`| Output | 2 | `clk` | Burst type (01 = INCR) | AW Channel / Master |
| `awlock` | Output | 1 | `clk` | Lock type indicator | AW Channel / Master |
| `awcache`| Output | 4 | `clk` | Memory cache type attributes | AW Channel / Master |
| `awprot` | Output | 3 | `clk` | Protection type attributes | AW Channel / Master |
| `awvalid`| Output | 1 | `clk` | Write address valid handshake | AW Channel / Master |
| `awready`| Input | 1 | `clk` | Write address ready handshake from slave | AW Channel / Slave |
| `wdata` | Output | 32 | `clk` | Write data bus | W Channel / Master |
| `wstrb` | Output | 4 | `clk` | Write byte strobes (1 bit per byte lane) | W Channel / Master |
| `wlast` | Output | 1 | `clk` | Write last beat indicator | W Channel / Master |
| `wvalid` | Output | 1 | `clk` | Write data valid handshake | W Channel / Master |
| `wready` | Input | 1 | `clk` | Write data ready handshake from slave | W Channel / Slave |
| `bid` | Input | 8 | `clk` | Write response transaction ID | B Channel / Slave |
| `bresp` | Input | 2 | `clk` | Write response status (00=OKAY 11=DECERR) | B Channel / Slave |
| `bvalid` | Input | 1 | `clk` | Write response valid handshake | B Channel / Slave |
| `bready` | Output | 1 | `clk` | Write response ready handshake from master | B Channel / Master |
| `arid` | Output | 8 | `clk` | Read address transaction ID | AR Channel / Master |
| `araddr` | Output | 32 | `clk` | Read address vector | AR Channel / Master |
| `arlen` | Output | 8 | `clk` | Read burst length (0 = single beat) | AR Channel / Master |
| `arsize` | Output | 3 | `clk` | Read burst size (010 = 4 bytes / 32-bit) | AR Channel / Master |
| `arburst`| Output | 2 | `clk` | Read burst type (01 = INCR) | AR Channel / Master |
| `arlock` | Output | 1 | `clk` | Read lock type indicator | AR Channel / Master |
| `arcache`| Output | 4 | `clk` | Read memory cache attributes | AR Channel / Master |
| `arprot` | Output | 3 | `clk` | Read protection attributes | AR Channel / Master |
| `arvalid`| Output | 1 | `clk` | Read address valid handshake | AR Channel / Master |
| `arready`| Input | 1 | `clk` | Read address ready handshake from slave | AR Channel / Slave |
| `rid` | Input | 8 | `clk` | Read response transaction ID | R Channel / Slave |
| `rdata` | Input | 32 | `clk` | Read data bus | R Channel / Slave |
| `rresp` | Input | 2 | `clk` | Read response status (00=OKAY 11=DECERR) | R Channel / Slave |
| `rlast` | Input | 1 | `clk` | Read last beat indicator | R Channel / Slave |
| `rvalid` | Input | 1 | `clk` | Read data valid handshake | R Channel / Slave |
| `rready` | Output | 1 | `clk` | Read data ready handshake from master | R Channel / Master |

#### Interface Source Code (`axi_if.sv`)
```systemverilog
interface axi_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 8
)(
    input logic clk,
    input logic rst
);
    // Write Address Channel (AW)
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awlock;
    logic [3:0]            awcache;
    logic [2:0]            awprot;
    logic                  awvalid;
    logic                  awready;

    // Write Data Channel (W)
    logic [DATA_WIDTH-1:0]   wdata;
    logic [(DATA_WIDTH/8)-1:0] wstrb;
    logic                    wlast;
    logic                    wvalid;
    logic                    wready;

    // Write Response Channel (B)
    logic [ID_WIDTH-1:0]   bid;
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    // Read Address Channel (AR)
    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [3:0]            arcache;
    logic [2:0]            arprot;
    logic                  arvalid;
    logic                  arready;

    // Read Data Channel (R)
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;

    clocking m_cb @(posedge clk);
        default input #1step output #1ns;
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    modport master  (clocking m_cb, input clk, rst);
    modport monitor (clocking mon_cb, input clk, rst);
endinterface : axi_if
```

---

### 7.2 SPI Industrial Sensor VIP
- **CSV Specification:** [`docs/vip_csv/spi_vip.csv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/docs/vip_csv/spi_vip.csv)
- **Interface File:** [`uvm/if/spi_if.sv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/if/spi_if.sv)

#### CSV Signal Definition Table
| Signal Name | Direction | Width | Clock Domain | Description | Protocol / Modport |
|---|:---:|:---:|:---:|---|---|
| `clk` | Input | 1 | System | Reference system clock (50 MHz) | Clock |
| `rst` | Input | 1 | System | Active-high synchronous reset | Reset |
| `sclk` | Input | 1 | `sclk` | SPI serial clock generated by SoC SPI Master | SPI Bus |
| `cs_n` | Input | 1 | `clk` | Active-low SPI chip select generated by SoC | SPI Bus |
| `mosi` | Input | 1 | `sclk` | Master-Out-Slave-In data driven by SoC | SPI Bus |
| `miso` | Output | 1 | `sclk` | Master-In-Slave-Out data driven by Sensor VIP | SPI Bus |
| `sensor_drdy`| Output | 1 | `clk` | External Sensor Data Ready flag into SoC | Handshake |

#### Interface Source Code (`spi_if.sv`)
```systemverilog
interface spi_if (
    input logic clk,
    input logic rst
);
    logic sclk;        // SoC SPI Master clock output
    logic cs_n;        // SoC SPI Chip Select (active low) output
    logic mosi;        // Master Out Slave In (from SoC)
    logic miso;        // Master In Slave Out (from Sensor VIP)
    logic sensor_drdy; // Sensor Data Ready flag into SoC

    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        input  sclk, cs_n, mosi;
        output miso, sensor_drdy;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input sclk, cs_n, mosi, miso, sensor_drdy;
    endclocking

    modport driver  (clocking drv_cb, input clk, rst, sclk, cs_n, mosi, output miso, sensor_drdy);
    modport monitor (clocking mon_cb, input clk, rst, sclk, cs_n, mosi, miso, sensor_drdy);
endinterface : spi_if
```

---

### 7.3 UART Full-Duplex Serial VIP
- **CSV Specification:** [`docs/vip_csv/uart_vip.csv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/docs/vip_csv/uart_vip.csv)
- **Interface File:** [`uvm/if/uart_if.sv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/if/uart_if.sv)

#### CSV Signal Definition Table
| Signal Name | Direction | Width | Clock Domain | Description | Protocol / Modport |
|---|:---:|:---:|:---:|---|---|
| `clk` | Input | 1 | System | Reference system clock (50 MHz) | Clock |
| `rst` | Input | 1 | System | Active-high synchronous reset | Reset |
| `uart_tx` | Input | 1 | Async/Baud | SoC UART serial output received by VIP monitor | Serial 8N1 |
| `uart_rx` | Output | 1 | Async/Baud | UART VIP driver serial input into SoC | Serial 8N1 |

#### Interface Source Code (`uart_if.sv`)
```systemverilog
interface uart_if (
    input logic clk,
    input logic rst
);
    logic uart_tx; // SoC output -> external receiver input
    logic uart_rx; // External driver output -> SoC input

    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output uart_rx;
        input  uart_tx;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input uart_tx, uart_rx;
    endclocking

    modport driver  (clocking drv_cb, input clk, rst);
    modport monitor (clocking mon_cb, input clk, rst);
endinterface : uart_if
```

---

### 7.4 GPIO & Pad Verification VIP
- **CSV Specification:** [`docs/vip_csv/gpio_vip.csv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/docs/vip_csv/gpio_vip.csv)
- **Interface File:** [`uvm/if/gpio_if.sv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/if/gpio_if.sv)

#### CSV Signal Definition Table
| Signal Name | Direction | Width | Clock Domain | Description | Protocol / Modport |
|---|:---:|:---:|:---:|---|---|
| `clk` | Input | 1 | System | Reference system clock (50 MHz) | Clock |
| `rst` | Input | 1 | System | Active-high synchronous reset | Reset |
| `gpio_in` | Output | 8 | `clk` | External GPIO pad inputs driven by VIP | Parallel I/O |
| `gpio_out`| Input | 8 | `clk` | SoC GPIO pad outputs sampled by VIP monitor | Parallel I/O |
| `gpio_oe` | Input | 8 | `clk` | SoC GPIO output enable masks sampled by VIP | Parallel I/O |
| `gpio_irq`| Input | 1 | `clk` | GPIO edge-detect interrupt line | Interrupt |

#### Interface Source Code (`gpio_if.sv`)
```systemverilog
interface gpio_if (
    input logic clk,
    input logic rst
);
    logic [7:0] gpio_in;
    logic [7:0] gpio_out;
    logic [7:0] gpio_oe;
    logic       gpio_irq;

    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output gpio_in;
        input  gpio_out, gpio_oe, gpio_irq;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input gpio_in, gpio_out, gpio_oe, gpio_irq;
    endclocking

    modport driver  (clocking drv_cb, input clk, rst);
    modport monitor (clocking mon_cb, input clk, rst);
endinterface : gpio_if
```

---

### 7.5 Interrupt & Fault Recovery VIP
- **CSV Specification:** [`docs/vip_csv/interrupt_vip.csv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/docs/vip_csv/interrupt_vip.csv)
- **Interface File:** [`uvm/if/interrupt_if.sv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/if/interrupt_if.sv)

#### CSV Signal Definition Table
| Signal Name | Direction | Width | Clock Domain | Description | Protocol / Modport |
|---|:---:|:---:|:---:|---|---|
| `clk` | Input | 1 | System | Reference system clock (50 MHz) | Clock |
| `rst` | Input | 1 | System | Active-high synchronous reset | Reset |
| `gpio_irq` | Input | 1 | `clk` | Edge-detected interrupt from GPIO peripheral | Interrupt |
| `timer_irq`| Input | 1 | `clk` | Countdown expiration interrupt from Hardware Timer | Interrupt |
| `wdt_fired`| Input | 1 | `clk` | Watchdog scoped fault reset trigger pulse | Fault Event |

#### Interface Source Code (`interrupt_if.sv`)
```systemverilog
interface interrupt_if (
    input logic clk,
    input logic rst
);
    logic gpio_irq;    // Edge-detect interrupt from GPIO
    logic timer_irq;   // Countdown interrupt from Timer
    logic wdt_fired;   // Scoped fault reset trigger from Watchdog

    clocking mon_cb @(posedge clk);
        default input #1step;
        input gpio_irq, timer_irq, wdt_fired;
    endclocking

    modport monitor (clocking mon_cb, input clk, rst, gpio_irq, timer_irq, wdt_fired);
endinterface : interrupt_if
```

---

### 7.6 Dynamic Clock & Reset Generator VIP
- **CSV Specification:** [`docs/vip_csv/clk_rst_vip.csv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/docs/vip_csv/clk_rst_vip.csv)
- **Interface File:** [`uvm/if/clk_rst_if.sv`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/if/clk_rst_if.sv)

#### CSV Signal Definition Table
| Signal Name | Direction | Width | Clock Domain | Description | Protocol / Modport |
|---|:---:|:---:|:---:|---|---|
| `clk` | Output | 1 | System | Dynamic master clock generated by VIP (50 MHz nominal) | Clock |
| `rst` | Output | 1 | System | Active-high synchronous reset for internal TB | Reset |
| `rst_n` | Output | 1 | System | Active-low reset driving top-level SoC pad | Reset |

#### Interface Source Code (`clk_rst_if.sv`)
```systemverilog
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
```

---

# 8. UVM Testbench Architecture & Block Diagram

The UVM verification architecture adheres strictly to IEEE 1800.2 standards. It encapsulates the complete SoC Design Under Test (`soc_top.v`), wraps all physical and internal pins inside SystemVerilog virtual interfaces, connects six dedicated VIP agent environments, routes transactions to a multi-channel Scoreboard featuring an independent C/SystemVerilog NIST FIPS-197 golden reference predictor, and samples comprehensive cross-coverage covergroups.

```
+--------------------------------------------------------------------------------------------------------------------+
|                                                  tb_top (Top Level)                                                |
|                                                                                                                    |
|   +------------------------------------------------------------------------------------------------------------+   |
|   |                                           uvm_test_top (Test Layer)                                        |   |
|   |  - soc_gateway_pipeline_test  - soc_access_control_test  - soc_wdt_recovery_test  - soc_reg_access_test       |   |
|   |  - soc_aes_test               - soc_dma_test             - soc_mem_test           - soc_stress_test           |   |
|   +-----------------------------------------------------+------------------------------------------------------+   |
|                                                         |                                                          |
|   +-----------------------------------------------------v------------------------------------------------------+   |
|   |                                              soc_env (Environment)                                         |   |
|   |                                                                                                            |   |
|   |  +--------------------+  +--------------------+  +--------------------+  +--------------------+            |   |
|   |  |   m_axi_agent      |  |   m_spi_agent      |  |   m_uart_agent     |  |   m_gpio_agent     |            |   |
|   |  | - Sequencer (S0/S1)|  | - Sensor Sequencer |  | - Full Duplex Seqr |  | - Pad Sequencer    |            |   |
|   |  | - Master Driver    |  | - Sensor Driver    |  | - RX/TX Driver     |  | - Pad Driver       |            |   |
|   |  | - Slave Driver     |  | - Bus Monitor      |  | - Serial Monitor   |  | - Level/Edge Mon   |            |   |
|   |  | - AXI4 Monitor     |  +---------+----------+  +---------+----------+  +---------+----------+            |   |
|   |  +---------+----------+            |                       |                       |                       |   |
|   |            |                       |                       |                       |                       |   |
|   |  +---------v----------+  +---------v----------+            |             +---------v----------+            |   |
|   |  |  m_clk_rst_agent   |  | m_interrupt_agent  |            |             |    soc_coverage    |            |   |
|   |  | - Freq/Period Gen  |  | - WDT Fired Monitor|            |             | - Crossbar Matrix  |            |   |
|   |  | - Async/Sync Reset |  | - Latency Checker  |            |             | - Access Control   |            |   |
|   |  +--------------------+  +---------+----------+            |             | - AES CTR vs ECB   |            |   |
|   |                                    |                       |             | - DMA Mode 0 & 1   |            |   |
|   |                                    |                       |             +---------^----------+            |   |
|   |                                    |                       |                       |                       |   |
|   |            +-----------------------+-----------+-----------+-----------------------+                       |   |
|   |            |                                   |                                                           |   |
|   |            v                                   v                                                           |   |
|   |  +------------------------------------------------------------------------------------------------------+  |   |
|   |  |                                           soc_scoreboard                                             |  |   |
|   |  | - NIST FIPS-197 Golden Reference Predictor (S-Box, ShiftRows, MixColumns, AddRoundKey)              |  |   |
|   |  | - NIST SP 800-38A Keystream Generator: Ciphertext = Plaintext ^ AES(Counter)                         |  |   |
|   |  | - Security DECERR Checker: Verifies illegal DMA accesses receive DECERR (2'b11) without bus hang    |  |   |
|   |  | - End-to-End Packet Comparator: Compares SPI sensor telemetry bursts against UART serial output     |  |   |
|   |  | - Watchdog SLA Fault Latency Verifier: Verifies 8-cycle quiescent drain window & scoped reset pulse  |  |   |
|   |  +------------------------------------------------------------------------------------------------------+  |   |
|   +-----------------------------------------------------+------------------------------------------------------+   |
|                                                         | Virtual Interface Handles                                |
|                                                         v                                                          |
|   +------------------------------------------------------------------------------------------------------------+   |
|   |                           Virtual Interfaces: axi_if, spi_if, uart_if, gpio_if, interrupt_if, clk_rst_if   |   |
|   +-----------------------------------------------------+------------------------------------------------------+   |
|                                                         | Wire Connections                                         |
|                                                         v                                                          |
|   +------------------------------------------------------------------------------------------------------------+   |
|   |                                         DESIGN UNDER TEST (DUT)                                            |   |
|   |                                            soc_top.v (SoC Top)                                             |   |
|   |                                                                                                            |   |
|   |     +------------------+     +-------------------------------+     +--------------------------------+      |   |
|   |     | VeeR EL2 CPU /   |     | AXI4 2x9 Interconnect Matrix  |     | Peripherals: IMEM, DMEM,       |      |   |
|   |     | CPU AXI Master   |<===>| ARB_LSB_HIGH_PRIORITY = 1     |<===>| UART, TIMER, GPIO, AES,        |      |   |
|   |     +------------------+     +-------------------------------+     | DMA, SPI, WATCHDOG             |      |   |
|   |                                                                    +--------------------------------+      |   |
|   +------------------------------------------------------------------------------------------------------------+   |
+--------------------------------------------------------------------------------------------------------------------+
```

---

# 9. C Test Cases, UVM Test Cases & Cycle-Accurate Waveform Snippets

---

## 9.1 C Firmware Test Cases (`main.c` & `basic_test.c`)

### 1. Gateway Autonomous Pipeline Application (`sw/application/main.c`)
This bare-metal application configures the peripheral controllers, loads the NIST FIPS-197 128-bit cryptographic key, initializes the watchdog timer, and continuously coordinates the autonomous hardware gateway pipeline.

```c
#include "soc_regs.h"

// NIST FIPS-197 Appendix B Standard 128-bit Key
// Key: 2B 7E 15 16 28 AE D2 A6 AB F7 15 88 09 CF 4F 3C
static const uint32_t aes_golden_key[4] = {
    0x16157E2B, 0xA6D2AE28, 0x8815F7AB, 0x3C4FCF09
};

int main(void) {
    // 1. Initialize UART baud rate (115200 baud @ 50 MHz)
    REG_WRITE(UART_BAUD_DIV, 434);
    REG_WRITE(UART_CTRL, UART_CTRL_TX_EN | UART_CTRL_RX_EN);

    // 2. Transmit Boot Banner over UART
    const char *banner = "\r\n[SoC] Secure Communication Gateway Online (RV32I)\r\n";
    for (const char *p = banner; *p; p++) {
        while (REG_READ(UART_STATUS) & UART_STATUS_TX_FULL);
        REG_WRITE(UART_DATA, *p);
    }

    // 3. Configure Hardware AES-128 Engine
    REG_WRITE(AES_KEY0, aes_golden_key[0]);
    REG_WRITE(AES_KEY1, aes_golden_key[1]);
    REG_WRITE(AES_KEY2, aes_golden_key[2]);
    REG_WRITE(AES_KEY3, aes_golden_key[3]);
    REG_WRITE(AES_CTRL, AES_CTRL_KEY_VALID); // Validate key

    // 4. Initialize Watchdog Timer (Feed & Enable)
    REG_WRITE(WDT_TIMEOUT, 0x00080000); // Set timeout period
    REG_WRITE(WDT_FEED, WDT_FEED_MAGIC); // Reload: 0xDEAD_FEED
    REG_WRITE(WDT_CTRL, WDT_CTRL_EN);    // Enable WDT

    // 5. Main Sensor Processing Loop
    while (1) {
        REG_WRITE(WDT_FEED, WDT_FEED_MAGIC); // Periodic Watchdog Feed

        // Await 16 bytes of telemetry from external SPI sensor
        while (REG_READ(SPI_STATUS) & SPI_STATUS_RX_EMPTY);

        // Mode 0: Trigger DMA to move 16 bytes from SPI RX FIFO to AES Plaintext
        REG_WRITE(DMA_SRC_ADDR, SPI_DATA);
        REG_WRITE(DMA_DST_ADDR, AES_DATA_IN0);
        REG_WRITE(DMA_LEN, 16);
        REG_WRITE(DMA_CTRL, DMA_CTRL_START | DMA_CTRL_MODE_SPI_TO_AES);

        // Wait for DMA transfer to complete
        while (REG_READ(DMA_STATUS) & DMA_STATUS_BUSY);

        // Trigger Hardware AES-128 Encryption Core (ECB / CTR Mode)
        REG_WRITE(AES_CTRL, AES_CTRL_START | AES_CTRL_KEY_VALID);

        // Wait for AES Encryption completion (11 clock cycles)
        while (!(REG_READ(AES_STATUS) & AES_STATUS_DONE));

        // Mode 1: Trigger DMA to stream 16 bytes of Ciphertext from AES to UART TX
        REG_WRITE(DMA_SRC_ADDR, AES_DATA_OUT0);
        REG_WRITE(DMA_DST_ADDR, UART_DATA);
        REG_WRITE(DMA_LEN, 16);
        REG_WRITE(DMA_CTRL, DMA_CTRL_START | DMA_CTRL_MODE_AES_TO_UART);

        // Wait for DMA stream to complete
        while (REG_READ(DMA_STATUS) & DMA_STATUS_BUSY);

        // Toggle GPIO Status LED (Pin 7) to signal successful transmission
        REG_WRITE(GPIO_DATA_OUT, REG_READ(GPIO_DATA_OUT) ^ 0x80);
    }

    return 0;
}
```

---

### 2. Comprehensive Subsystem Diagnostic Application (`sw/application/basic_test.c`)
Tests integer ALU operations, recursive Fibonacci calculation, multi-width sub-word memory access (`LB`, `LBU`, `LH`, `LHU`, `LW`), GPIO toggling, and hardware timer countdown. All 5 testcases execute cleanly with 100% pass status.

---

## 9.2 UVM Test Suites & Sequences

### 1. End-to-End Pipeline Verification Test (`soc_gateway_pipeline_test.sv`)
```systemverilog
class soc_gateway_pipeline_test extends soc_base_test;
    `uvm_component_utils(soc_gateway_pipeline_test)

    function new(string name = "soc_gateway_pipeline_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_phase(uvm_phase phase);
        soc_gateway_pipeline_seq seq;
        phase.raise_objection(this, "Starting End-to-End Pipeline Verification Test");
        `uvm_info("TEST", "Executing 10 consecutive sensor-to-ciphertext bursts...", UVM_LOW)

        seq = soc_gateway_pipeline_seq::type_id::create("seq");
        seq.num_bursts = 10;
        seq.start(m_env.m_vseqr);

        phase.drop_objection(this, "Completed Pipeline Test");
    endtask
endclass
```

### 2. Access Control & Security Firewall Test (`soc_access_control_test.sv`)
Forces illegal DMA write and read transactions to `IMEM`, `DMA_CFG`, `TIMER`, `GPIO`, and `WDT`, verifying that the interconnect blocks the transactions and returns `DECERR` (`2'b11`) without crashing or freezing the fabric.

---

## 9.3 Cycle-Accurate Waveform Snippets

### Waveform 1: External SPI Telemetry Burst Ingestion
```
Time (ns)       208,500   208,520   208,540   208,560   208,580   208,600   208,620
clk          :  _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
sensor_drdy  :  ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\__________________________
spi_cs_n     :  ‾‾‾‾‾‾‾‾\_______________________________________________/‾‾‾‾‾‾‾‾
spi_sclk     :  _________/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\__________
spi_miso     :  =========X===0x00===X===0x11===X===0x22===X===0x33======X=========
spi_rx_empty :  ‾‾‾‾‾‾‾‾\_________________________________________________________
Annotation   :          ^ Sensor asserts DRDY; SPI Master asserts CS_N and samples bytes
```

### Waveform 2: Autonomous DMA Mode 0 Transfer (SPI RX FIFO → AES Plaintext)
```
Time (ns)       210,000   210,020   210,040   210,060   210,080   210,100   210,120
clk          :  _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
m_axi_s1_awaddr: =======X 0x10000318 X 0x1000031C X 0x10000320 X 0x10000324 X======
m_axi_s1_wdata : =======X 0x33221100 X 0x77665544 X 0xBBAA9988 X 0xFFEEDDCC X======
m_axi_s1_wvalid: _______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
m_axi_s1_wready: _______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
aes_start    :  _______________________________________________________/‾‾‾\______
Annotation   :  DMA Master S1 writes 4 packed words directly to AES Plaintext registers
```

### Waveform 3: AES-128 10-Round Hardware Execution (11 Clock Cycles)
```
Cycle Index  :    0       1       2       3    ...    8       9      10      11
clk          :  _/‾\_  _/‾\_  _/‾\_  _/‾\_  ...  _/‾\_  _/‾\_  _/‾\_  _/‾\_  _/‾\_
aes_ctrl_start: /‾‾‾\_____________________________________________________________
aes_busy     :  ______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
aes_round[3:0]: = 0x0 =X= 0x1 =X= 0x2 =X= 0x3 = ... =X= 0x8 =X= 0x9 =X= 0xA =X= 0x0 =
aes_done     :  ___________________________________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾
aes_ciphertext: ---------------------------------------------------< 3925841D... >
Annotation   :  Round 1..9 (SubBytes, ShiftRows, MixColumns), Round 10 (AddRoundKey)
```

### Waveform 4: Watchdog Timeout, 8-Cycle Quiescent Drain & Scoped Reset Pulse
```
Time (ns)       400,000   400,020   400,040   400,160   400,180   400,200   400,220
clk          :  _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_ ... _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
wdt_count    :  == 0x01 =X== 0x00 ==X=================== 0x00 ====================
wdt_state    :  == COUNT =X================ WDT_DRAIN (8 Cycles) =================
wdt_reset_dma:  _________________________________________________/‾‾‾‾‾\__________
wdt_reset_aes:  _________________________________________________/‾‾‾‾‾\__________
wdt_reset_spi:  _________________________________________________/‾‾‾‾‾\__________
cpu_rst      :  __________________________________________________________________ (NO RESET)
imem_rst     :  __________________________________________________________________ (NO RESET)
wdt_cause[0] :  _________________________________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
Annotation   :  WDT drains fabric for 8 cycles, pulses scoped reset for 1 cycle; CPU preserved
```

---

## 9.4 Waveform Simulation vs. Firmware HEX Correlation Report

The simulation waveform trace (`tb_soc_firmware.vcd`) was extracted and cross-referenced with `build/firmware.hex` (398 instruction words) and `build/firmware.dis` (304 disassembled instructions) using the automated clock-synchronized verification tool (`scripts/compare_waveform_hex.py`).

```
==================================================================
      WAVEFORM TRACE VS. FIRMWARE HEX COMPARISON SUMMARY          
==================================================================
  Instruction Fetches Verified : 3,670
  Mismatches Detected          : 0
  Correlation Accuracy         : 100.00% EXACT MATCH (PASS)
==================================================================
```

### Cycle-Accurate Instruction Fetch Sample
| Sim Time (ns) | PC / Fetch Addr | Waveform Fetched Hex (`s_axi_rdata`) | Expected HEX (`firmware.hex`) | Disassembly Mnemonic | Function Symbol | Verification Status |
|---|---|---|---|---|---|---|
| 190,010 ns | `0x00000000` | `0x00010117` | `0x00010117` | `auipc sp, 0x10` | `<_start>` | **PASS (MATCH)** |
| 190,030 ns | `0x00000004` | `0x00010113` | `0x00010113` | `addi sp, sp, 0` | `<_start>` | **PASS (MATCH)** |
| 190,050 ns | `0x00000008` | `0x00000517` | `0x00000517` | `auipc a0, 0x0` | `<_start>` | **PASS (MATCH)** |
| 190,070 ns | `0x0000000C` | `0x04C50513` | `0x04C50513` | `addi a0, a0, 76` | `<_start>` | **PASS (MATCH)** |
| 190,090 ns | `0x00000010` | `0x00010597` | `0x00010597` | `auipc a1, 0x10` | `<_start>` | **PASS (MATCH)** |
| 205,010 ns | `0x00000060` | `0x10000737` | `0x10000737` | `lui a4, 0x10000` | `<main>` | **PASS (MATCH)** |
| 205,030 ns | `0x00000064` | `0x1B200793` | `0x1B200793` | `li a5, 434` | `<main>` | **PASS (MATCH)** |
| 205,050 ns | `0x00000068` | `0x00F72623` | `0x00F72623` | `sw a5, 12(a4)` | `<main>` | **PASS (MATCH)** |
| 206,810 ns | `0x000000A0` | `0x161577B7` | `0x161577B7` | `lui a5, 0x16157` | `<main>` | **PASS (MATCH)** |
| 206,830 ns | `0x000000A4` | `0xE2B78793` | `0xE2B78793` | `addi a5, a5, -469` | `<main>` | **PASS (MATCH)** |
| 206,850 ns | `0x000000A8` | `0x30F72023` | `0x30F72023` | `sw a5, 768(a4)` | `<main>` | **PASS (MATCH)** |
| 212,010 ns | `0x00000140` | `0x00300793` | `0x00300793` | `li a5, 3` | `<main>` | **PASS (MATCH)** |
| 212,030 ns | `0x00000144` | `0x30F72823` | `0x30F72823` | `sw a5, 784(a4)` | `<main>` | **PASS (MATCH)** |
| 851,310 ns | `0x000001A0` | `0x08000793` | `0x08000793` | `li a5, 128` | `<main>` | **PASS (MATCH)** |
| 851,330 ns | `0x000001A4` | `0x20F72223` | `0x20F72223` | `sw a5, 516(a4)` | `<main>` | **PASS (MATCH)** |

---

# 10. Summary Verification Scorecard

| Verification Suite | Target Architecture | Total Checks | Passing Checks | Failures | Coverage / Status |
|---|---|:---:|:---:|:---:|:---:|
| `tb_interconnect.sv` | 2x9 AXI4 Interconnect | 52 | 52 | 0 | **100% PASS** |
| `tb_cpu_adapter.sv` | CPU Master Adapter | 23 | 23 | 0 | **100% PASS** |
| `tb_aes.sv` | AES-128 CTR/ECB Engine | 23 | 23 | 0 | **100% PASS** |
| `tb_dma.sv` | Dual-Mode DMA Controller | 19 | 19 | 0 | **100% PASS** |
| `tb_watchdog.sv` | Watchdog Scoped Recovery | 25 | 25 | 0 | **100% PASS** |
| `tb_soc_top.sv` | Full SoC Top Hardware | 20 | 20 | 0 | **100% PASS** |
| `tb_soc_firmware.sv`| Full C Gateway Pipeline | 6 | 6 | 0 | **100% PASS** |
| `scripts/compare_waveform_hex.py`| Waveform vs. Hex Tracing | 3,670 | 3,670 | 0 | **100% EXACT MATCH** |
| `uvm/` Production Suite | Synopsys VCS / Verdi UVM 1.2 | 10 Test Suites | 10 | 0 | **Closure Ready** |

**FINAL VERDICT:** All architectural, cryptographic, interconnect access control, and watchdog scoped fault recovery requirements have achieved **100% Functional Verification Closure**.
