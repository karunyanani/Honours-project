# Third-Party IP Versions and Integration Specifications

## 1. CHIPS Alliance VeeR EL2 (RISC-V Processor)

| Specification | Value / Detail |
|---|---|
| **Repository** | https://github.com/chipsalliance/Cores-VeeR-EL2.git |
| **Commit Hash** | `fa00c8aadc4a077d78b277129c1badf90d881255` |
| **Local Path** | `rtl/third_party/Cores-VeeR-EL2` |
| **Submodules** | `third_party/picolibc` (`0694a78fc08b3300c7db79602c46ba0a64428c8e`)<br>`third_party/riscv-dv` (`da33551ab102c7530d7dadb803abf4c245ba08e0`) |
| **ISA Target** | RV32IMC, ILP32 ABI |
| **Native Data Width** | 64-bit LSU (Load/Store Unit) and 64-bit IFU (Instruction Fetch Unit) |
| **Native Address Width**| 32-bit byte address space |
| **Bus ID Width** | 4-bit (`pt.LSU_BUS_TAG = 4`, `pt.IFU_BUS_TAG = 4`) |
| **Interface Standard** | Dual AXI4 Master: LSU (Read/Write) and IFU (Read-Only) |
| **Compilation Macro** | `+define+RV_BUILD_AXI4` |
| **Original RTL Policy** | Preserved unmodified in `rtl/third_party/Cores-VeeR-EL2/` |
| **Integration Method** | `rtl/cpu/veer_el2_wrapper.v` (wraps core and ties off debug/dma slave) and `rtl/cpu/cpu_axi_adapter.v` (64-to-32 bit down-conversion and IFU/LSU arbitration) |

### Key Processor Interface Signals
- **LSU Master (64-bit)**:
  - Write Address: `lsu_axi_awvalid`, `lsu_axi_awready`, `lsu_axi_awid[3:0]`, `lsu_axi_awaddr[31:0]`, `lsu_axi_awlen[7:0]`, `lsu_axi_awsize[2:0]`, `lsu_axi_awburst[1:0]`, `lsu_axi_awlock`, `lsu_axi_awcache[3:0]`, `lsu_axi_awprot[2:0]`, `lsu_axi_awqos[3:0]`
  - Write Data: `lsu_axi_wvalid`, `lsu_axi_wready`, `lsu_axi_wdata[63:0]`, `lsu_axi_wstrb[7:0]`, `lsu_axi_wlast`
  - Write Response: `lsu_axi_bvalid`, `lsu_axi_bready`, `lsu_axi_bresp[1:0]`, `lsu_axi_bid[3:0]`
  - Read Address: `lsu_axi_arvalid`, `lsu_axi_arready`, `lsu_axi_arid[3:0]`, `lsu_axi_araddr[31:0]`, `lsu_axi_arlen[7:0]`, `lsu_axi_arsize[2:0]`, `lsu_axi_arburst[1:0]`, `lsu_axi_arlock`, `lsu_axi_arcache[3:0]`, `lsu_axi_arprot[2:0]`, `lsu_axi_arqos[3:0]`
  - Read Data: `lsu_axi_rvalid`, `lsu_axi_rready`, `lsu_axi_rid[3:0]`, `lsu_axi_rdata[63:0]`, `lsu_axi_rresp[1:0]`, `lsu_axi_rlast`
- **IFU Master (64-bit read-only)**:
  - Read Address: `ifu_axi_arvalid`, `ifu_axi_arready`, `ifu_axi_arid[3:0]`, `ifu_axi_araddr[31:0]`, `ifu_axi_arlen[7:0]`, `ifu_axi_arsize[2:0]`, `ifu_axi_arburst[1:0]`, `ifu_axi_arlock`, `ifu_axi_arcache[3:0]`, `ifu_axi_arprot[2:0]`, `ifu_axi_arqos[3:0]`
  - Read Data: `ifu_axi_rvalid`, `ifu_axi_rready`, `ifu_axi_rid[3:0]`, `ifu_axi_rdata[63:0]`, `ifu_axi_rresp[1:0]`, `ifu_axi_rlast`

---

## 2. Alex Forencich verilog-axi Interconnect Library

| Specification | Value / Detail |
|---|---|
| **Repository** | https://github.com/alexforencich/verilog-axi.git |
| **Commit Hash** | `516bd5dadc3365b7f9e225d2af8fe0b8d804fe53` |
| **Local Path** | `rtl/third_party/verilog-axi` |
| **License** | MIT License (`COPYING` preserved) |
| **Core Files Used** | `rtl/axi_interconnect.v`<br>`rtl/arbiter.v`<br>`rtl/priority_encoder.v` |
| **Wrapper Generator** | `rtl/axi_interconnect_wrap.py` and project script `scripts/gen_interconnect_wrap.py` |

### Interconnect Architecture and Parameters
- **Masters (S-side)**: 2 (`S_COUNT = 2`)
  - S0: RISC-V CPU subsystem via CPU-side AXI adapter
  - S1: External DMA Controller
- **Slaves (M-side)**: 9 (`M_COUNT = 9`)
  - M0: Instruction Memory (`0x00000000`, 64 KB, `aw = 16`, Mask = `2'b01`)
  - M1: Data Memory (`0x00010000`, 64 KB, `aw = 16`, Mask = `2'b11`)
  - M2: UART (`0x10000000`, 256 B, `aw = 8`, Mask = `2'b11`)
  - M3: Timer (`0x10000100`, 256 B, `aw = 8`, Mask = `2'b01`)
  - M4: GPIO (`0x10000200`, 256 B, `aw = 8`, Mask = `2'b01`)
  - M5: AES Engine (`0x10000300`, 256 B, `aw = 8`, Mask = `2'b11`)
  - M6: DMA Registers (`0x10000400`, 256 B, `aw = 8`, Mask = `2'b01`)
  - M7: SPI Controller (`0x10000500`, 256 B, `aw = 8`, Mask = `2'b11`)
  - M8: Watchdog Timer (`0x10000600`, 256 B, `aw = 8`, Mask = `2'b01`)

### Arbitration Behavior (from source inspection)
- In `axi_interconnect.v`:
  - Instantiates `arbiter` with `PORTS = S_COUNT * 2 = 4` (channel 0: S0-AW, channel 1: S0-AR, channel 2: S1-AW, channel 3: S1-AR).
  - `ARB_TYPE_ROUND_ROBIN = 1`: Performs round-robin arbitration between competing transaction streams.
  - `ARB_LSB_HIGH_PRIORITY = 1`: In tie conditions, lower channel index (S0 / CPU) wins.
  - `ARB_BLOCK = 1` and `ARB_BLOCK_ACK = 1`: A granted transaction blocks arbitration until completion (handshake acknowledged), guaranteeing transaction atomicity without corrupting or interleaving bursts.

---

## 3. Toolchain and EDA Environment

| Tool | Recommended / Required Spec |
|---|---|
| **Simulation** | Synopsys VCS (`-full64 -sverilog -timescale=1ns/1ps`) / Icarus Verilog >= 11.0 |
| **Waveform Viewer** | Synopsys Verdi (FSDB) / GTKWave (VCD) |
| **RISC-V Compiler** | `riscv64-unknown-elf-gcc` (GCC 12.2.0, RV32IMC, ILP32 ABI) |
| **Python** | Python 3.10+ (PyYAML optional for address map generator) |
