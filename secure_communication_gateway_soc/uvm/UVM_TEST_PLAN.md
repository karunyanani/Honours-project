# COMPREHENSIVE UVM VERIFICATION TEST PLAN
# Secure Communication Gateway SoC with Hardware AES-128 & Watchdog Scoped Fault Recovery

**Document Version:** 2.0  
**Project:** Honours Final-Year Engineering Project  
**Author:** Senior VLSI Verification Engineer  
**Standard:** IEEE 1800.2 (UVM 1.2) / IEEE 1800-2017 (SystemVerilog)  
**Target Simulators:** Synopsys VCS / Verdi (UVM-1.2), QuestaSim, Cadence Xcelium, Icarus Verilog  
**Master Document Location:** [`docs/UVM_TEST_PLAN.md`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/docs/UVM_TEST_PLAN.md)

---

## 1. Executive Summary & Verification Scope

The **Secure Communication Gateway SoC** is a mission-critical, high-reliability embedded system designed to capture sensor telemetry over SPI, perform real-time cryptographic encryption via a dedicated hardware **AES-128 CTR Engine**, offload high-throughput transfers through an autonomous **Direct Memory Access (DMA) Controller**, and transmit encrypted ciphertext over a full-duplex **UART 8N1** interface. System integrity is safeguarded by an on-chip **Watchdog Timer (WDT)** providing **scoped fault recovery**, and an **AXI4 2-Master × 9-Slave Interconnect** with hardware-enforced access control and `DECERR` generation.

This document establishes the **Comprehensive UVM Verification Test Plan**, defining:
- All functional, protocol, performance, and fault-recovery requirements.
- The UVM Verification IP (VIP) testbench architecture and stimulus strategy.
- Complete catalog of test cases categorized across all operating conditions, corner cases, negative testing, and security violations.
- SystemVerilog Assertions (SVA) protocol checkers.
- Functional coverage models (covergroups, coverpoints, cross-coverage bins).
- Traceability Matrix mapping design requirements to verification closure.

---

## 2. Design Under Test (DUT) Feature Matrix & Interfaces

### 2.1 SoC Memory Map & Master-Slave Interconnect Topology

| Port | Block Name | Base Address | End Address | Size | Master Access Permissions |
|---|---|---|---|---|---|
| **M0** | Instruction Memory (IMEM) | `0x0000_0000` | `0x0000_FFFF` | 64 KB | **CPU (S0) Only**. DMA access strictly prohibited (`DECERR`). |
| **M1** | Data Memory (DMEM) | `0x0001_0000` | `0x0001_FFFF` | 64 KB | **CPU (S0) & DMA (S1)** Read/Write. |
| **M2** | UART Controller | `0x1000_0000` | `0x1000_00FF` | 256 B | **CPU (S0) & DMA (S1)** Read/Write. |
| **M3** | Hardware Timer | `0x1000_0100` | `0x1000_01FF` | 256 B | **CPU (S0) Only**. DMA access strictly prohibited (`DECERR`). |
| **M4** | GPIO Controller | `0x1000_0200` | `0x1000_02FF` | 256 B | **CPU (S0) Only**. DMA access strictly prohibited (`DECERR`). |
| **M5** | AES-128 CTR Engine | `0x1000_0300` | `0x1000_03FF` | 256 B | **CPU (S0) & DMA (S1)** Read/Write. |
| **M6** | DMA Configuration | `0x1000_0400` | `0x1000_04FF` | 256 B | **CPU (S0) Only**. DMA access strictly prohibited (`DECERR`). |
| **M7** | SPI Master Controller | `0x1000_0500` | `0x1000_05FF` | 256 B | **CPU (S0) & DMA (S1)** Read/Write. |
| **M8** | Watchdog Timer (WDT) | `0x1000_0600` | `0x1000_06FF` | 256 B | **CPU (S0) Only**. DMA access strictly prohibited (`DECERR`). |
| **--** | Unmapped Address Space | `0x2000_0000` | `0xFFFF_FFFF` | ~3.5 GB | All masters -> **DECERR Response**. |

### 2.2 Top-Level Pin Interface List

```
                    +------------------------------------+
                    |        DUT: soc_top.v              |
                    |                                    |
  clk ------------->| Clock (50 MHz nominal)             |
  rst_n ----------->| Active-Low Asynchronous/Sync Reset |
                    |                                    |
  uart_rx --------->| UART Serial RX Input               |
  uart_tx <---------| UART Serial TX Output              |
                    |                                    |
  spi_sck <---------| SPI Serial Clock Output            |
  spi_mosi <--------| SPI Master Out Slave In            |
  spi_miso -------->| SPI Master In Slave Out            |
  spi_cs_n <--------| SPI Active-Low Chip Select         |
                    |                                    |
  gpio_in[7:0] ---->| 8-bit GPIO Inputs (Sensors/Pads)   |
  gpio_out[7:0] <---| 8-bit GPIO Outputs (LEDs/Signals)  |
  gpio_oe[7:0] <----| 8-bit GPIO Output Enable Masks     |
                    |                                    |
  gpio_irq <--------| GPIO Edge/Level Interrupt Output   |
  timer_irq <-------| Timer Expiration Interrupt Output  |
  wdt_fired <-------| Watchdog Fault Reset Indicator     |
  dbg_pc[31:0] <----| Core Instruction Debug PC Vector   |
                    +------------------------------------+
```

---

## 3. UVM Verification Architecture & Testbench Topology

The testbench is structured according to the standard **UVM-1.2** modular methodology:

```
+----------------------------------------------------------------------------------------------------+
|                                              soc_env                                               |
|                                                                                                    |
|  +---------------------+   +---------------------+   +---------------------+   +----------------+  |
|  |     m_axi_agent     |   |     m_spi_agent     |   |    m_uart_agent     |   |  m_gpio_agent  |  |
|  |  (Master S0 / Slv)  |   | (Sensor Responder)  |   |    (Full Duplex)    |   | (Pads & IRQ)   |  |
|  |  [Seqr | Drv | Mon] |   | [Seqr | Drv | Mon]  |   | [Seqr | Drv | Mon]  |   | [Seqr|Drv|Mon] |  |
|  +----------+----------+   +----------+----------+   +----------+----------+   +-------+--------+  |
|             |                         |                         |                      |           |
|  +----------v----------+   +----------v----------+              |          +-----------v--------+  |
|  |   m_clk_rst_agent   |   |  m_interrupt_agent  |              |          |    soc_coverage    |  |
|  | (Dynamic Clock/Rst) |   | (Latency/Fault Mon) |              |          | (Interconnect, RW, |  |
|  | [Sequencer | Driver]|   |      [Monitor]      |              |          |  DECERR, Pipeline) |  |
|  +----------+----------+   +----------+----------+              |          +-----------^--------+  |
|             |                         |                         |                      |           |
|             +-------------------------+------------+------------+----------------------+           |
|                                                    |                                               |
|                                         +----------v-----------+                                   |
|                                         |    soc_scoreboard    |                                   |
|                                         |  - FIPS-197 Predict  |                                   |
|                                         |  - Interconnect Sec  |                                   |
|                                         |  - Memory Tracking   |                                   |
|                                         |  - Fault SLA Checks  |                                   |
|                                         +----------------------+                                   |
+----------------------------------------------------+-----------------------------------------------+
                                                     | Virtual Interfaces (axi_if, spi_if, uart_if,
                                                     |                     gpio_if, interrupt_if, clk_rst_if)
                                                     v
+----------------------------------------------------------------------------------------------------+
|                                          DUT: soc_top.v                                            |
+----------------------------------------------------------------------------------------------------+
```

### 3.1 Verification IPs (VIPs) Employed

1. **AXI4 VIP (`m_axi_agent`):** Emulates Master S0 / S1 transactions, verifies protocol handshakes, measures transfer latencies, checks byte strobes and DECERR generations.
2. **SPI Sensor VIP (`m_spi_agent`):** Models field sensor responder, generates autonomous DRDY pulses, handles CPOL/CPHA modes, and validates 16-byte telemetry bursts.
3. **UART VIP (`m_uart_agent`):** Full-duplex bitstream serializer and oversampling monitor with parity, framing, and baud jitter error injection.
4. **GPIO VIP (`m_gpio_agent`):** Bidirectional pin driver/monitor for push-buttons, sensor triggers, status LEDs, and interrupt lines.
5. **Interrupt & Fault VIP (`m_interrupt_agent`):** High-precision cycle-accurate event monitor tracking SLA latencies and watchdog recovery pulses.
6. **Clock & Reset VIP (`m_clk_rst_agent`):** Synchronous/asynchronous reset generator, power-on sequencing, and dynamic frequency scaling.

---

## 4. Comprehensive Test Case Catalog

```
                               TEST PLAN TAXONOMY
┌─────────────────────────────────────────────────────────────────────────────────┐
│ [1] RST  - Reset & Power-On Sequencing Tests                                   │
│ [2] REG  - Register Access Sanity & Reset Value Tests                           │
│ [3] AXI  - AXI4 Interconnect Protocol & Arbitration Tests                       │
│ [4] SEC  - Security Firewall & Access Control Violation Tests                  │
│ [5] MEM  - Instruction & Data Memory Hazard & Boundary Tests                    │
│ [6] AES  - Hardware AES-128 Encryption & Counter Mode Tests                     │
│ [7] SPI  - Industrial Sensor SPI Master Interface Tests                         │
│ [8] UART - Serial Communication, Baud Divisors & Error Injection Tests         │
│ [9] DMA  - Autonomous Datapath & Backpressure Tests                            │
│ [10] WDT - Watchdog Countdown, Feeding & Scoped Fault Recovery Tests            │
│ [11] SYS - Full System End-to-End Pipeline & Throughput Tests                  │
│ [12] COR - Stress, Concurrency & Extreme Corner Case Tests                      │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

### Category 1: Reset & Power-On Sequencing Tests (`TC_RST_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_RST_01` | Power-On Reset Cold Boot | Assert `rst_n = 0` for 20 clock cycles, then deassert synchronously. | Core PC initializes to `0x0000_0000`. UART TX idles HIGH (`1'b1`). SPI CS_N idles HIGH (`1'b1`). GPIO outputs initialize to `0x00`. | **P0** |
| `TC_RST_02` | Asynchronous Reset Assertion | Assert `rst_n = 0` asynchronously in the middle of active clock phase. | All bus handshakes immediately abort. Internal state machines return to IDLE within 1 clock cycle. | **P1** |
| `TC_RST_03` | Runt Reset Pulse Immunity | Apply a reset pulse narrower than 0.5 clock cycles. | Verify filter logic ignores glitches shorter than minimum threshold, or handles cleanly without meta-stability. | **P2** |
| `TC_RST_04` | Warm Reset Mid-Transaction | Assert reset while Master S0 has active `AWVALID` and `WVALID` pending handshake. | Interconnect cleanly releases all grants, aborts transaction without bus deadlock, and recovers upon reset deassertion. | **P1** |
| `TC_RST_05` | Reset Recovery Sequencing | Deassert reset and immediately issue back-to-back read requests on cycle 1. | DUT correctly accepts transaction without setup/hold timing violations. | **P1** |

---

### Category 2: Register Access Sanity & Reset Values (`TC_REG_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_REG_01` | Default Power-On Values | Read all configuration registers across all 9 slaves immediately post-reset. | All registers return exact documented default values (e.g., UART Divisor = 434, WDT = default, GPIO OE = 0x00). | **P0** |
| `TC_REG_02` | R/W Register Bit Walk (0x55/0xAA) | Write alternating bit patterns `0x5555_5555` and `0xAAAA_AAAA` to writable registers, then read back. | Readback data strictly matches written data with 0 bit errors. | **P0** |
| `TC_REG_03` | Read-Only Register Protection | Attempt writes to status registers (e.g., AES Status, WDT Status, UART RX Status). | Values remain unchanged; no internal state corruption occurs. | **P1** |
| `TC_REG_04` | Write-1-to-Clear (W1C) Attributes | Trigger status flags (e.g., WDT Reset Cause, Timer Done), then write `1'b1` to clear. | Flags clear to `0` upon write of `1`, and remain `1` if written with `0`. | **P1** |
| `TC_REG_05` | Reserved Bits Read Zero | Read registers with reserved upper bits (`[31:8]` or `[31:1]`). | Reserved bits strictly return `0` on reads and ignore written values. | **P2** |

---

### Category 3: AXI4 Interconnect Protocol & Arbitration (`TC_AXI_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_AXI_01` | Basic Single-Beat Read/Write | Perform 32-bit single-beat writes and reads across IMEM, DMEM, and peripherals. | Handshakes complete with `BRESP = OKAY` (`2'b00`) and `RRESP = OKAY` (`2'b00`). | **P0** |
| `TC_AXI_02` | Sub-Word Byte Strobes (`WSTRB`) | Write byte (`WSTRB=0001, 0010, 0100, 1000`) and halfword (`0011, 1100`) patterns into DMEM. | Only targeted byte lanes are modified in memory; neighboring bytes remain intact. | **P0** |
| `TC_AXI_03` | Simultaneous Master Contention | Master 0 (CPU) and Master 1 (DMA) simultaneously target DMEM address space. | Interconnect executes round-robin arbitration; both masters receive grants without starvation or deadlock. | **P0** |
| `TC_AXI_04` | Slave Zero-Wait State Handshake | Responder asserts `AWREADY`, `WREADY`, and `ARREADY` in the same cycle as `VALID`. | Transactions complete in single clock cycle with maximum throughput. | **P1** |
| `TC_AXI_05` | Slave Extended Backpressure | Responder delays `READY` by 1 to 50 randomized clock cycles. | Master holds `VALID`, `ADDR`, and `DATA` completely stable until handshake completes (SVA rule check). | **P0** |
| `TC_AXI_06` | Interleaved Read/Write Hazards | Execute Read-After-Write (RAW), Write-After-Read (WAR), and Write-After-Write (WAW) to identical addresses. | Data coherency preserved; RAW reads return freshly updated data. | **P0** |
| `TC_AXI_07` | 4KB Boundary Crossing Attempt | Issue burst transaction crossing `0x1000` address boundary. | Protocol checker detects boundary crossing and flags violation. | **P1** |
| `TC_AXI_08` | Back-to-Back Pipelined Requests | Issue continuous stream of write and read requests without idle cycles. | Interconnect channels process requests at 100% bus utilization. | **P1** |

---

### Category 4: Security Firewall & Access Control Violations (`TC_SEC_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_SEC_01` | Unmapped Space Access | Issue Read and Write transactions to `0x2000_0000`, `0x5000_0000`, and `0xFFFF_0000`. | Interconnect returns `DECERR` (`2'b11`) within 2 clock cycles; write is dropped. | **P0** |
| `TC_SEC_02` | DMA Illegal Access to IMEM | Master 1 (DMA) attempts write/read to IMEM (`0x0000_0000` - `0x0000_FFFF`). | Interconnect returns `DECERR`; write blocked; CPU instruction memory unaltered. | **P0** |
| `TC_SEC_03` | DMA Illegal Access to Timer | Master 1 (DMA) attempts write to Timer (`0x1000_0100`). | Interconnect returns `DECERR`; Timer configuration unchanged. | **P0** |
| `TC_SEC_04` | DMA Illegal Access to GPIO | Master 1 (DMA) attempts write to GPIO (`0x1000_0200`). | Interconnect returns `DECERR`; GPIO pins unaffected. | **P0** |
| `TC_SEC_05` | DMA Self-Tamper Violation | Master 1 (DMA) attempts write to DMA Configuration registers (`0x1000_0400`). | Interconnect returns `DECERR`; DMA cannot reconfigure its own control registers. | **P0** |
| `TC_SEC_06` | DMA Illegal Access to Watchdog | Master 1 (DMA) attempts write to WDT (`0x1000_0600`) to feed or disable it. | Interconnect returns `DECERR`; Watchdog feeding blocked. | **P0** |
| `TC_SEC_07` | Authorized DMA Access Sanity | Master 1 (DMA) reads/writes DMEM (`0x0001_0000`), AES (`0x1000_0300`), SPI (`0x1000_0500`), UART (`0x1000_0000`). | Interconnect grants access with `OKAY` (`2'b00`) response; data transfers successfully. | **P0** |
| `TC_SEC_08` | Security Violation Logging | Cause repeated illegal DMA accesses. | Interconnect firewall raises security alert flag and records offending master ID and address. | **P1** |

---

### Category 5: Instruction & Data Memory Hazard & Boundary Tests (`TC_MEM_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_MEM_01` | IMEM Boundary Verification | Read first word (`0x0000_0000`) and last word (`0x0000_FFFC`) of 64 KB IMEM. | Data read matches compiled binary hex. Address `0x0001_0000` routes to DMEM. | **P0** |
| `TC_MEM_02` | DMEM Boundary Verification | Write and read first word (`0x0001_0000`) and last word (`0x0001_FFFC`) of 64 KB DMEM. | Readback matches written data without wrap-around or corruption. | **P0** |
| `TC_MEM_03` | Unaligned Store / Load Handling | Issue unaligned word accesses (offsets +1, +2, +3 bytes). | Core adapter accurately maps byte lanes and performs proper sign/zero extension. | **P1** |
| `TC_MEM_04` | Dense Walking Bit Pattern in RAM | Fill 1 KB block of DMEM with walking 1s and 0s (`0x00000001`, `0x00000002`, ... `0x80000000`). | All words verified upon readback; no adjacent cell coupling or address line shorts. | **P1** |
| `TC_MEM_05` | Dual-Port Memory Contention | CPU executes load from DMEM at same cycle DMA executes store to neighboring word. | Both operations succeed; arbiter maintains integrity without data loss. | **P0** |

---

### Category 6: Hardware AES-128 Encryption & CTR Mode (`TC_AES_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_AES_01` | NIST FIPS-197 Known Answer Test (KAT) | Load NIST standard Key (`2b7e1516...`) and Plaintext (`6bc1bee2...`). Trigger start. | Ciphertext matches standard NIST KAT vector within exact clock cycle tolerance. | **P0** |
| `TC_AES_02` | NIST SP 800-38A CTR Mode Validation | Load 128-bit Key and Nonce/IV. Encrypt consecutive 16-byte blocks. | Ciphertext strictly matches Golden Reference Model: `39 25 84 1D 02 DC 09 FB DC 11 85 97 19 6A 0B 32`. | **P0** |
| `TC_AES_03` | Counter Rollover & Increment | Set initial counter to `0xFFFF_FFFF_FFFF_FFFF`. Encrypt block. | Counter increments and rolls over correctly without stalling the engine. | **P1** |
| `TC_AES_04` | Key Tamper Protection During Active Run | Attempt to write new Key into `KEY0-KEY3` while `STATUS[0] (busy) == 1`. | Write ignored; current encryption completes with original key. | **P1** |
| `TC_AES_05` | Plaintext Overwrite Protection | Attempt write to `PT0-PT3` registers while encryption is in progress. | Write ignored; engine processes original plaintext. | **P1** |
| `TC_AES_06` | Back-to-Back Block Encryption | Immediately load next plaintext block upon `done` assertion and restart. | Zero dead cycles between computations; maximum encryption throughput achieved. | **P1** |
| `TC_AES_07` | All-Zeros and All-Ones Key/Data | Test edge-case keys (`0x0000_0000` and `0xFFFF_FFFF`) and data patterns. | Verified against reference model; S-Box and shift rows compute accurately. | **P2** |

---

### Category 7: Industrial Sensor SPI Master Interface (`TC_SPI_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_SPI_01` | SPI Mode 0 Transmission Sanity | Configure CPOL=0, CPHA=0. Transfer single byte from master to VIP sensor. | MOSI data shifts out on falling edge of SCLK; MISO sampled on rising edge. | **P0** |
| `TC_SPI_02` | 16-Byte Burst Telemetry Read | Sensor VIP asserts DRDY. SoC initiates 16-byte burst read from sensor. | All 16 bytes successfully transferred into SPI RX FIFO without bit shifts or drops. | **P0** |
| `TC_SPI_03` | CS_N Setup & Hold Timing Verification | Monitor timing between `cs_n` assertion and first `sclk` pulse, and last pulse to deassertion. | Setup and hold times conform strictly to Motorola SPI standard ($\ge 0.5 \times T_{\text{sclk}}$). | **P1** |
| `TC_SPI_04` | SPI RX FIFO Full & Overflow | Sensor VIP streams bytes into FIFO while CPU does not read. | Overflow status flag sets; existing FIFO data is preserved without corruption. | **P1** |
| `TC_SPI_05` | Sensor Telemetry Corruption / Disconnect | Disconnect MISO line (pull HIGH or LOW) mid-transfer. | Timeout detection occurs; system raises telemetry error flag. | **P2** |
| `TC_SPI_06` | Variable Clock Divisor Validation | Program SPI Clock Divisor from minimum (div=2) to maximum (div=256). | SCLK period accurately scales to programmed value; data transfers remain error-free. | **P1** |

---

### Category 8: UART Serial Communications & Error Injection (`TC_UART_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_UART_01` | Standard 115200 Baud 8N1 Transmission | Transmit ASCII string from SoC UART TX to UART VIP. | 8N1 framing verified (1 start bit, 8 data bits LSB-first, 1 stop bit) at 115200 baud ($\pm 1.5\%$ tolerance). | **P0** |
| `TC_UART_02` | Full-Duplex Simultaneous TX/RX | Transmit command sequence on `uart_rx` while SoC continuously transmits ciphertext on `uart_tx`. | Both data streams decode with 0 bit errors and zero cross-channel interference. | **P0** |
| `TC_UART_03` | Framing Error Injection | Inject corrupted stop bit (`0'b0` instead of `1'b1`) on `uart_rx`. | UART controller asserts Framing Error (FE) status bit; rejects bad frame. | **P1** |
| `TC_UART_04` | RX FIFO Overrun Error | Inject 32 bytes continuously into 16-byte RX FIFO without read. | Overrun Error (OE) bit asserts; oldest data preserved or flagged per specification. | **P1** |
| `TC_UART_05` | Baud Rate Divisor Dynamic Scaling | Reconfigure baud divisor register from simulation fast (div=4) to 115200 baud (div=434). | Bit duration matches expected clock cycle count; reception remains locked. | **P1** |
| `TC_UART_06` | Break Condition Detection | Hold `uart_rx` LOW for longer than a complete frame duration (> 10 bit times). | Break condition detected; controller raises break interrupt flag. | **P2** |

---

### Category 9: Autonomous DMA Datapath & Backpressure (`TC_DMA_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_DMA_01` | Mode 0 Autonomous Transfer (SPI $\to$ AES) | Configure DMA Mode 0 (`SRC=SPI_RX_FIFO`, `DST=AES_PT`, `LEN=16`). Trigger start. | 16 bytes autonomously read from SPI and written to AES registers; DMA asserts completion interrupt. | **P0** |
| `TC_DMA_02` | Mode 1 Autonomous Transfer (AES $\to$ UART) | Configure DMA Mode 1 (`SRC=AES_CT`, `DST=UART_TX_FIFO`, `LEN=16`). Trigger start. | 16 encrypted ciphertext bytes streamed into UART TX FIFO; UART transmits serial stream. | **P0** |
| `TC_DMA_03` | Source FIFO Empty Backpressure | Trigger DMA Mode 0 when SPI RX FIFO has only 4 bytes available. | DMA transfers 4 bytes, stalls gracefully waiting for data, and resumes when sensor provides remaining bytes. | **P0** |
| `TC_DMA_04` | Destination FIFO Full Backpressure | Trigger DMA Mode 1 when UART TX FIFO is completely full. | DMA holds transfer, asserts no invalid handshakes, and writes next word the cycle UART FIFO frees space. | **P0** |
| `TC_DMA_05` | Transfer Abort Request Mid-Flight | Assert `DMA_ABORT` register bit while transfer is actively running. | DMA finishes current atomic beat, cleanly releases bus, and sets ABORTED status flag. | **P1** |
| `TC_DMA_06` | Zero-Length & Out-of-Bounds Length | Program DMA with length = 0 and length > 64 KB. | Zero length returns immediate DONE; excessive length capped or flagged with parameter error. | **P2** |

---

### Category 10: Watchdog Countdown, Feeding & Scoped Fault Recovery (`TC_WDT_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_WDT_01` | Normal Countdown & Expiration | Program timeout to 10,000 cycles. Allow timer to expire without feeding. | `wdt_fired` signal asserts on exact expiration cycle; scoped reset pulse generated. | **P0** |
| `TC_WDT_02` | Regular Periodic Watchdog Feeding | Firmware writes feed key (`0x55AA_FEED`) every 5,000 cycles. | Counter resets to threshold on every feed; `wdt_fired` never asserts; system runs continuously. | **P0** |
| `TC_WDT_03` | Scoped Reset Datapath Isolation | Trigger watchdog expiration. Inspect internal reset domains. | **Reset Asserted To:** DMA, AES processing pipeline, SPI FIFO.<br>**Reset NOT Asserted To:** CPU state, IMEM, DMEM, AES Keys, DMA configuration registers. | **P0** |
| `TC_WDT_04` | W1C Reset Cause Flag & Post-Recovery Boot | After scoped reset, CPU reads `WDT_RESET_CAUSE` register, verifies flag = 1, writes 1 to clear. | Flag reads 1 on boot, clears to 0 upon write-1, allowing firmware to distinguish warm recovery from cold boot. | **P0** |
| `TC_WDT_05` | Watchdog Feed Invalidation on Wrong Key | Write incorrect key (`0xDEAD_BEEF`) to feed register. | Feed rejected; counter continues decrementing without reset. | **P1** |
| `TC_WDT_06` | Back-to-Back Repeated Watchdog Faults | Allow watchdog to expire multiple times in succession. | Scoped reset asserts cleanly each time; system recovers repeatedly without latch-up. | **P1** |

---

### Category 11: Full System End-to-End Pipeline & Throughput (`TC_SYS_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_SYS_01` | Golden Gateway Pipeline Test | Full firmware execution: Sensor VIP streams 16 raw bytes $\to$ SPI $\to$ DMA Mode 0 $\to$ AES CTR $\to$ DMA Mode 1 $\to$ UART $\to$ VIP. | Ciphertext received over UART exactly matches NIST FIPS-197 standard. `gpio_out` pin 7 toggles high. Status = PASS. | **P0** |
| `TC_SYS_02` | Sustained Multi-Block Throughput | Stream 100 consecutive 16-byte sensor blocks through pipeline without pause. | All 100 blocks successfully encrypted and transmitted. Scoreboard reports 0 byte drops, 0 mismatches. | **P0** |
| `TC_SYS_03` | Pipeline Stalling & Flow Control | Artificially inject severe backpressure on UART TX while continuous sensor data arrives. | System throttles gracefully; FIFOs hold data; once backpressure clears, all data resumes with zero corruption. | **P1** |
| `TC_SYS_04` | Bare-Metal C Application Comprehensive Run | Load compiled `basic_test.c` hex into IMEM and release reset. | Executes all 5 sub-tests (ALU, recursion/stack, DMEM access, GPIO, Timer); UART displays test banner; GPIO out = `0xFF`. | **P0** |

---

### Category 12: Stress, Concurrency & Extreme Corner Cases (`TC_COR_xx`)

| Test ID | Test Name | Stimulus Description | Pass/Fail Criteria | Priority |
|---|---|---|---|:---:|
| `TC_COR_01` | Full Fabric Concurrency Stress | CPU executes compute loop in DMEM, DMA runs continuous block transfers, SPI streams data, and UART transmits. | Interconnect arbitrates all requests fairly; 0 bus deadlocks; all peripherals operate concurrently. | **P0** |
| `TC_COR_02` | Watchdog Scoped Reset Mid-DMA Burst | Force watchdog expiration precisely while DMA is executing active write beat to AES. | Scoped reset cleanly terminates DMA transfer; interconnect does not lock up; CPU regains control. | **P0** |
| `TC_COR_03` | Random Clock Jitter & Frequency Scaling | Vary clock period dynamically by $\pm 10\%$ cycle-to-cycle using `clk_rst_agent`. | Synchronous circuits maintain proper setup/hold timing; digital logic functions correctly. | **P1** |
| `TC_COR_04` | High-Rate Interrupt Coincidence | Trigger `gpio_irq`, `timer_irq`, and `wdt_fired` in the exact same clock cycle. | Interrupt controller arbitrates according to configured priority vector; all interrupts serviced without drop. | **P1** |

---

## 5. SystemVerilog Assertions (SVA) & Protocol Checkers

To guarantee protocol compliance and catch timing defects at the cycle level, the following SVA properties are integrated into VIP interfaces and RTL wrappers:

### 5.1 AXI4 Interconnect Protocol Assertions (`axi_assertions.sv`)

1. **`SVA_AXI_VAL_STABLE` (Handshake Stability Rule):**
   When `VALID` is asserted, `VALID` and all associated payload signals (`ADDR`, `DATA`, `STRB`, `PROT`, `BURST`) must remain completely stable until `READY` is asserted.
   $$\forall t: (\text{VALID} \land \neg \text{READY}) \implies \bigcirc (\text{VALID} \land \text{ADDR} = \text{past}(\text{ADDR}))$$

2. **`SVA_AXI_RESP_LEGAL` (Response Encoding Check):**
   Response signals `BRESP` and `RRESP` must strictly match legal 2-bit encodings (`2'b00`: OKAY, `2'b01`: EXOKAY, `2'b10`: SLVERR, `2'b11`: DECERR).

3. **`SVA_AXI_DECERR_UNMAPPED` (Firewall Rule):**
   Any access where `AxADDR[31:28] \ge 4'h2` must result in `xRESP == 2'b11` (`DECERR`) within a maximum of 4 clock cycles.

4. **`SVA_AXI_DMA_IMEM_PROHIBITED` (Security Firewall Rule):**
   Any access from Master 1 (DMA) with `AxADDR` within `[0x0000_0000 : 0x0000_FFFF]` must be denied with `DECERR`.

### 5.2 UART Protocol Assertions (`uart_if.sv`)

1. **`SVA_UART_START_BIT`:**
   Start bit must remain LOW for exactly 1 full bit period ($\pm 2\%$ tolerance).
2. **`SVA_UART_STOP_BIT`:**
   Stop bit must be asserted HIGH for $\ge 1$ full bit period at the conclusion of every frame.

### 5.3 Watchdog Scoped Reset Assertions (`tb_top.sv`)

1. **`SVA_WDT_SCOPED_RESET_ISOLATION`:**
   When `wdt_fired` asserts, `dma_rst` and `aes_rst` must assert, while `cpu_rst_n`, `imem_rst_n`, and `dmem_rst_n` must remain completely deasserted (`1'b1`).

---

## 6. Comprehensive Functional Coverage Plan

The verification suite requires **100% functional coverage** across all architectural specifications.

### 6.1 Covergroups & Coverpoints Definition

```systemverilog
covergroup soc_comprehensive_cg;
    option.per_instance = 1;
    option.comment = "SoC Top-Level Comprehensive Functional Coverage";

    // 1. Interconnect Master Coverpoint
    cp_master: coverpoint master_id {
        bins CPU = {4'h0};
        bins DMA = {4'h1};
    }

    // 2. Read/Write Transaction Type
    cp_rw: coverpoint rw_type {
        bins READ  = {1'b0};
        bins WRITE = {1'b1};
    }

    // 3. Slave Address Range
    cp_slave_space: coverpoint addr {
        bins IMEM     = {[32'h0000_0000 : 32'h0000_FFFF]};
        bins DMEM     = {[32'h0001_0000 : 32'h0001_FFFF]};
        bins UART     = {[32'h1000_0000 : 32'h1000_00FF]};
        bins TIMER    = {[32'h1000_0100 : 32'h1000_01FF]};
        bins GPIO     = {[32'h1000_0200 : 32'h1000_02FF]};
        bins AES      = {[32'h1000_0300 : 32'h1000_03FF]};
        bins DMA_CFG  = {[32'h1000_0400 : 32'h1000_04FF]};
        bins SPI      = {[32'h1000_0500 : 32'h1000_05FF]};
        bins WDT      = {[32'h1000_0600 : 32'h1000_06FF]};
        bins UNMAPPED = {[32'h2000_0000 : 32'hFFFF_FFFF]};
    }

    // 4. AXI Response Types
    cp_resp: coverpoint resp_code {
        bins OKAY   = {2'b00};
        bins DECERR = {2'b11};
    }

    // 5. Byte Strobe Patterns
    cp_wstrb: coverpoint wstrb {
        bins BYTE_0  = {4'b0001};
        bins BYTE_1  = {4'b0010};
        bins BYTE_2  = {4'b0100};
        bins BYTE_3  = {4'b1000};
        bins HALF_LO = {4'b0011};
        bins HALF_HI = {4'b1100};
        bins WORD    = {4'b1111};
    }

    // 6. DMA Operating Modes
    cp_dma_mode: coverpoint dma_mode {
        bins MODE_0_SPI_TO_AES   = {2'b00};
        bins MODE_1_AES_TO_UART  = {2'b01};
        bins MODE_2_MEM_TO_MEM   = {2'b10};
    }

    // 7. Watchdog States & Events
    cp_wdt_events: coverpoint wdt_event {
        bins NORMAL_FEED   = {2'b00};
        bins TIMEOUT_FAULT = {2'b01};
        bins SCOPED_RESET  = {2'b10};
        bins W1C_CLEARED   = {2'b11};
    }

    // 8. Cross Coverage: Master x Slave Space x R/W Type
    cross_master_slave_rw: cross cp_master, cp_slave_space, cp_rw;

    // 9. Cross Coverage: Master x Slave Space x Response (Verifies DECERR enforcement)
    cross_security_firewall: cross cp_master, cp_slave_space, cp_resp;

endgroup
```

### 6.2 Coverage Closure Goals

| Coverage Category | Metric / Target | Closure Criteria |
|---|---|---|
| **Functional Coverage** | **100% Target** | All bins and illegal-access security crosses covered at least 10 times. |
| **Statement / Line Coverage** | **> 95% Target** | Every synthesizable line executed during simulation. |
| **Branch / Decision Coverage** | **> 90% Target** | True and False paths executed for all conditional logic and FSM transitions. |
| **Condition Coverage** | **> 90% Target** | All multi-term boolean sub-expressions evaluated independently. |
| **FSM State & Transition Coverage** | **100% Target** | All states visited; all legal state transitions exercised; recovery transitions tested. |
| **SystemVerilog Assertions (SVA)**| **100% PASS** | Zero assertion failures allowed across all regression runs. |

---

## 7. Verification Traceability Matrix (VTM)

| Feature / Requirement | RTL Module | UVM Test ID(s) | Verification VIP | Target Coverage Bin | SVA Property |
|---|---|---|---|---|---|
| Reset Sequencing & Cold Boot | `soc_top.v` | `TC_RST_01`, `TC_RST_05` | `clk_rst_agent` | `cp_wdt_events` | `SVA_RESET_TIMING` |
| 2×9 Interconnect Routing | `axi_interconnect.v` | `TC_AXI_01`, `TC_AXI_08` | `axi_agent` | `cross_master_slave_rw` | `SVA_AXI_VAL_STABLE` |
| Interconnect Arbitration | `arbiter.v` | `TC_AXI_03`, `TC_COR_01` | `axi_agent` | `cross_master_slave_rw` | `SVA_ARB_NO_STARVATION`|
| Security Access Control Matrix | `soc_interconnect_wrap.v`| `TC_SEC_01` - `TC_SEC_08`| `axi_agent` | `cross_security_firewall`| `SVA_AXI_DECERR_UNMAPPED`|
| Sub-Word Byte Strobes | `cpu_axi_master.v` | `TC_AXI_02`, `TC_MEM_03` | `axi_agent` | `cp_wstrb` | `SVA_AXI_WSTRB_LEGAL` |
| AES-128 FIPS-197 KAT | `aes_top.v` | `TC_AES_01`, `TC_AES_02` | `axi_agent`, Scoreboard | `soc_coverage` | `SVA_AES_LATENCY` |
| AES Key Protection During Run | `aes_top.v` | `TC_AES_04`, `TC_AES_05` | `axi_agent` | `soc_coverage` | `SVA_AES_WRITE_PROTECT`|
| SPI Mode 0 Sensor Telemetry | `spi_master.v` | `TC_SPI_01` - `TC_SPI_03`| `spi_agent` | `soc_coverage` | `SVA_SPI_TIMING` |
| UART 8N1 Serial Protocol | `uart_top.v` | `TC_UART_01`, `TC_UART_02`| `uart_agent` | `soc_coverage` | `SVA_UART_START_BIT` |
| UART Error Detection | `uart_rx.v` | `TC_UART_03`, `TC_UART_04`| `uart_agent` | `soc_coverage` | `SVA_UART_FRAME_ERR` |
| DMA Autonomous Modes 0 & 1 | `dma_controller.v` | `TC_DMA_01`, `TC_DMA_02` | `axi_agent`, Scoreboard | `cp_dma_mode` | `SVA_DMA_HANDSHAKE` |
| DMA Flow Control & Stalls | `dma_controller.v` | `TC_DMA_03`, `TC_DMA_04` | `axi_agent`, `uart_agent`| `cp_dma_mode` | `SVA_DMA_STALL_NO_DROP`|
| Watchdog Scoped Fault Recovery | `watchdog_timer.v` | `TC_WDT_01` - `TC_WDT_04`| `interrupt_agent` | `cp_wdt_events` | `SVA_WDT_SCOPED_RESET` |
| Full End-to-End Gateway Flow | Full SoC | `TC_SYS_01`, `TC_SYS_02` | All VIPs, Scoreboard | Full Cross Model | System Assertion Suite |

---

## 8. Regression Execution & Simulation Workflow

### 8.1 Automated Regression Commands (Synopsys VCS)

```bash
# Set environment variables for Synopsys VCS & UVM 1.2
export VCS_HOME=/tools/synopsys/vcs/latest
export UVM_HOME=/tools/synopsys/uvm-1.2

# 1. Run Complete Sanity Smoke Suite
./scripts/run_vcs_uvm.sh soc_reg_access_test

# 2. Run Access Control & Security Firewall Regression
./scripts/run_vcs_uvm.sh soc_access_control_test

# 3. Run End-to-End Gateway Pipeline Regression
./scripts/run_vcs_uvm.sh soc_gateway_pipeline_test

# 4. Run Watchdog Scoped Fault Recovery Regression
./scripts/run_vcs_uvm.sh soc_wdt_recovery_test

# 5. Execute Full Multi-Seed Regression Suite with Functional Coverage
./scripts/run_regression.sh -seed_count 50 -cov -verdi
```

### 8.2 Interactive Debugging with Synopsys Verdi

```bash
# Launch Verdi with recorded FSDB transaction database
verdi -ssf build/soc_uvm.fsdb &
```

---

## 9. Conclusion

This **UVM Verification Test Plan** provides an exhaustive blueprint covering every conceivable architectural, protocol, security, boundary, and fault condition of the Secure Communication Gateway SoC. Execution against this plan guarantees complete functional verification closure, zero bus deadlocks, robust cryptographic isolation, and 100% adherence to all academic honours and industrial VLSI standards.

