# UVM Verification IP (VIP) Architecture & Integration Guide
# Secure Communication Gateway SoC

**Target Simulator:** Synopsys VCS / Verdi (UVM-1.2), QuestaSim / Xcelium Compatible  
**Project:** Honours Final-Year Engineering Project  
**Author:** Senior VLSI Verification Engineer  

---

## 1. Executive Summary & VIP Portfolio

To ensure 100% functional coverage, protocol compliance, and fault-tolerance verification of the **Secure Communication Gateway SoC**, an industry-standard suite of reusable **Universal Verification IPs (VIPs)** has been architected and integrated into the UVM-1.2 testbench environment.

### Verification IP Portfolio

| VIP Name | Package / Agent Path | Interface | Mode / Capabilities | Protocol Standard |
|---|---|---|---|---|
| **AXI4 VIP** | [`uvm/agents/axi_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/axi_agent) | `axi_if.sv` | **Master & Slave Responder**<br>- Configurable latency models<br>- 4KB boundary & strobe checkers<br>- SVA Protocol Assertions | AMBA AXI4 (32b Addr, 32b Data, 8b ID) |
| **SPI Sensor VIP** | [`uvm/agents/spi_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/spi_agent) | `spi_if.sv` | **Slave Sensor Model**<br>- Autonomous DRDY generation<br>- 16-byte burst telemetry streaming<br>- CPOL/CPHA mode configurability | Motorola SPI Mode 0 / Sensor Telemetry |
| **UART VIP** | [`uvm/agents/uart_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/uart_agent) | `uart_if.sv` | **Full-Duplex Serial VIP**<br>- RX bitstream injector driver<br>- TX baud/parity/stop monitor<br>- Framing/parity error injection | 8N1 RS-232 / UART (115200 Baud) |
| **GPIO & Pad VIP** | [`uvm/agents/gpio_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/gpio_agent) | `gpio_if.sv` | **Active / Passive Driver-Monitor**<br>- Pin level driving & masking<br>- Edge pulse generator for DRDY<br>- Output LED toggle tracking | 8-bit Bidirectional GPIO + Pad Controls |
| **Interrupt & Fault VIP** | [`uvm/agents/interrupt_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/interrupt_agent) | `interrupt_if.sv` | **Latency & Fault Recovery Monitor**<br>- High-precision event timestamping<br>- Timer, GPIO, and WDT fault detection<br>- SLA latency measurement | Asynchronous Interrupt & Reset Sidebands |
| **Clock & Reset VIP** | [`uvm/agents/clk_rst_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/clk_rst_agent) | `clk_rst_if.sv` | **Dynamic Stimulus Generator**<br>- Dynamic frequency scaling<br>- Power-on & warm reset pulsing<br>- Glitch & brownout recovery injection | System Clock & Active-Low/High Reset |

---

## 2. UVM Environment Architecture Diagram

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
|                                                                                                    |
|  [VeeR EL2 / S0 Master] <---> [AXI4 2x9 Interconnect] <---> [Peripherals, Security, Memories, DMA] |
|                                                                                                    |
|  Pads: uart_rx, uart_tx, spi_sck, spi_cs_n, spi_mosi, spi_miso, gpio_in, gpio_out, gpio_oe,       |
|        gpio_irq, timer_irq, wdt_fired, dbg_pc                                                      |
+----------------------------------------------------------------------------------------------------+
```

---

## 3. Deep-Dive Specification of Each VIP

### 3.1 AXI4 Verification IP (`axi_agent`)
- **Location:** [`uvm/agents/axi_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/axi_agent)
- **Role:** Dual-role VIP capable of operating as an **Active AXI4 Master** (driving transactions directly into Master port S0 of the 2×9 interconnect) or as an **AXI4 Slave Responder** (emulating external memories or coprocessor targets).
- **Key Components:**
  - `axi_agent_config.sv`: Configures Master vs. Slave role, active/passive mode, memory array sizes, and random wait-state delays for `awready`, `wready`, and `arready`.
  - `axi_driver.sv`: Clock-synchronized AXI4 master driving write address/data handshakes and read address handshakes with ID routing.
  - `axi_slave_driver.sv`: Associative memory array responding with configurable latency and OKAY/SLVERR/DECERR codes.
  - `axi_monitor.sv`: Passive monitor re-assembling complete AXI4 read and write transactions from pin transitions.
  - `axi_assertions.sv`: Protocol checker verifying handshake stability (Rule: `VALID` must remain asserted until `READY`), address alignment, and legal response encodings.
  - `axi_seq_lib.sv`: Library providing `axi_random_burst_seq` (burst read/write sanity) and `axi_security_violation_seq` (verifying DECERR generation on unauthorized master accesses).

### 3.2 SPI Industrial Sensor Verification IP (`spi_agent`)
- **Location:** [`uvm/agents/spi_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/spi_agent)
- **Role:** Emulates an industrial field-side vibration or SCADA telemetry sensor connected to the SoC's SPI Master interface.
- **Key Components:**
  - `spi_agent_config.sv`: Programmable CPOL, CPHA, word length, and DRDY pulse duration.
  - `spi_driver.sv`: Slave responder that asserts `sensor_drdy` to signal new telemetry availability, detects `cs_n` assertion from the SoC, and synchronously shifts out sensor data on `spi_miso` at each SCLK edge.
  - `spi_monitor.sv`: Bidirectional monitor sampling both outgoing sensor data (`miso`) and incoming configuration commands (`mosi`).
  - `spi_seq_lib.sv`: Provides `spi_fips197_telemetry_seq` to stream exact 16-byte raw data frames (`00 11 22 .. EE FF`) into the SoC datapath.

### 3.3 Full-Duplex UART Verification IP (`uart_agent`)
- **Location:** [`uvm/agents/uart_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/uart_agent)
- **Role:** Verifies serial communications by injecting commands onto `uart_rx` and validating ciphertext bitstreams emitted on `uart_tx`.
- **Key Components:**
  - `uart_agent_config.sv`: Configures baud rate (115200 baud standard), system clock frequency, data bits (8), stop bits (1 or 2), and optional parity.
  - `uart_driver.sv`: Serializes bytes into an 8N1 bitstream with start bit, 8 data bits (LSB first), parity, and stop bit, including frame error injection.
  - `uart_monitor.sv`: Oversamples `uart_tx` line at bit centers, validates framing, reconstructs bytes, and publishes to the scoreboard.
  - `uart_seq_lib.sv`: Provides `uart_rx_command_seq` for sending strings and packetized command sequences.

### 3.4 GPIO & Pad Verification IP (`gpio_agent`)
- **Location:** [`uvm/agents/gpio_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/gpio_agent)
- **Role:** Models external push buttons, sensors, and LED indicators connected to the SoC's 8-bit GPIO port.
- **Key Components:**
  - `gpio_agent_config.sv`: Defines pin directions, pull-ups, and active/passive roles.
  - `gpio_driver.sv`: Dynamically drives level transitions and pulses on individual `gpio_in` pins.
  - `gpio_monitor.sv`: Passively detects pin state changes on `gpio_out`, `gpio_oe`, and `gpio_irq`.
  - `gpio_seq_lib.sv`: Includes `gpio_walking_ones_seq` and `gpio_sensor_drdy_pulse_seq`.

### 3.5 Interrupt & Fault Recovery Verification IP (`interrupt_agent`)
- **Location:** [`uvm/agents/interrupt_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/interrupt_agent)
- **Role:** Monitors asynchronous system events (`gpio_irq`, `timer_irq`, `wdt_fired`) to track interrupt latency and watchdog recovery.
- **Key Components:**
  - `interrupt_agent_config.sv`: Programmable maximum SLA latency thresholds.
  - `interrupt_monitor.sv`: Timestamped cycle-accurate tracking of assertion and deassertion edges across all interrupt and fault signals.
  - `interrupt_seq_lib.sv`: Base sequence for interrupt timeout verification.

### 3.6 Clock & Reset Generation VIP (`clk_rst_agent`)
- **Location:** [`uvm/agents/clk_rst_agent`](file:///c:/Users/KARUNYA/Downloads/honours_project/secure_communication_gateway_soc/uvm/agents/clk_rst_agent)
- **Role:** Generates controllable system clock oscillations and coordinates power-on reset, warm reset, and brownout glitch events.
- **Key Components:**
  - `clk_rst_agent_config.sv`: Configures nominal clock period (e.g., 20ns for 50 MHz), duty cycle, and initial reset hold duration.
  - `clk_rst_driver.sv`: Continuous background clock generation with runtime sequence-controlled frequency scaling and reset assertions.
  - `clk_rst_seq_lib.sv`: Power-on reset (`clk_rst_power_on_seq`) and warm reset (`clk_rst_warm_reset_seq`).

---

## 4. How to Compile and Run the UVM Verification Suite

### Compiling and Running in Synopsys VCS
```bash
# Make sure the script is executable
chmod +x scripts/run_vcs_uvm.sh

# Run the Register Access Sanity Test
./scripts/run_vcs_uvm.sh soc_reg_access_test

# Run the Access Control Security Violation Test
./scripts/run_vcs_uvm.sh soc_access_control_test

# Run the End-to-End Gateway Pipeline Test
./scripts/run_vcs_uvm.sh soc_gateway_pipeline_test

# Run the Watchdog Fault Recovery Test
./scripts/run_vcs_uvm.sh soc_wdt_recovery_test
```

### Viewing Waveforms in Synopsys Verdi
```bash
# Launch Verdi with the generated FSDB database
make verdi
# or directly:
./scripts/run_verdi.sh soc_uvm.fsdb
```

