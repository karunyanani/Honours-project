// =============================================================================
// File: soc_uvm_pkg.sv
// Description: UVM Verification Package for Secure Communication Gateway SoC
// Includes:
//   - AXI4 Verification IP (Master & Slave)
//   - SPI Sensor Verification IP (Master & Sensor Slave Responder)
//   - Full-Duplex UART Verification IP (TX Monitor & RX Driver)
//   - GPIO & Pad Verification IP (Driver, Monitor, Edge Detect)
//   - Interrupt & Fault Recovery VIP (Latency Tracker, WDT Fault Monitor)
//   - Clock & Reset Generation VIP (Dynamic Frequency, Reset Sequences)
//   - Scoreboard, Coverage Collector, Virtual Sequences, and Tests
// =============================================================================

`ifndef SOC_UVM_PKG_SV
`define SOC_UVM_PKG_SV

package soc_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Forward declarations / Sequence base
    `include "../sequences/soc_base_seq.sv"

    // 1. AXI4 Verification IP
    `include "../agents/axi_agent/axi_agent_config.sv"
    `include "../agents/axi_agent/axi_seq_item.sv"
    `include "../agents/axi_agent/axi_driver.sv"
    `include "../agents/axi_agent/axi_slave_driver.sv"
    `include "../agents/axi_agent/axi_monitor.sv"
    `include "../agents/axi_agent/axi_sequencer.sv"
    `include "../agents/axi_agent/axi_agent.sv"
    `include "../agents/axi_agent/axi_seq_lib.sv"

    // 2. SPI Sensor Verification IP
    `include "../agents/spi_agent/spi_agent_config.sv"
    `include "../agents/spi_agent/spi_seq_item.sv"
    `include "../agents/spi_agent/spi_driver.sv"
    `include "../agents/spi_agent/spi_monitor.sv"
    `include "../agents/spi_agent/spi_sequencer.sv"
    `include "../agents/spi_agent/spi_agent.sv"
    `include "../agents/spi_agent/spi_seq_lib.sv"

    // 3. UART Verification IP
    `include "../agents/uart_agent/uart_agent_config.sv"
    `include "../agents/uart_agent/uart_seq_item.sv"
    `include "../agents/uart_agent/uart_driver.sv"
    `include "../agents/uart_agent/uart_monitor.sv"
    `include "../agents/uart_agent/uart_sequencer.sv"
    `include "../agents/uart_agent/uart_agent.sv"
    `include "../agents/uart_agent/uart_seq_lib.sv"

    // 4. GPIO Verification IP
    `include "../agents/gpio_agent/gpio_agent_config.sv"
    `include "../agents/gpio_agent/gpio_seq_item.sv"
    `include "../agents/gpio_agent/gpio_driver.sv"
    `include "../agents/gpio_agent/gpio_monitor.sv"
    `include "../agents/gpio_agent/gpio_sequencer.sv"
    `include "../agents/gpio_agent/gpio_agent.sv"
    `include "../agents/gpio_agent/gpio_seq_lib.sv"

    // 5. Interrupt & Fault Recovery VIP
    `include "../agents/interrupt_agent/interrupt_agent_config.sv"
    `include "../agents/interrupt_agent/interrupt_seq_item.sv"
    `include "../agents/interrupt_agent/interrupt_monitor.sv"
    `include "../agents/interrupt_agent/interrupt_agent.sv"
    `include "../agents/interrupt_agent/interrupt_seq_lib.sv"

    // 6. Clock and Reset Generation VIP
    `include "../agents/clk_rst_agent/clk_rst_agent_config.sv"
    `include "../agents/clk_rst_agent/clk_rst_seq_item.sv"
    `include "../agents/clk_rst_agent/clk_rst_driver.sv"
    `include "../agents/clk_rst_agent/clk_rst_sequencer.sv"
    `include "../agents/clk_rst_agent/clk_rst_agent.sv"
    `include "../agents/clk_rst_agent/clk_rst_seq_lib.sv"

    // Scoreboard & Functional Coverage
    `include "../scoreboard/soc_scoreboard.sv"
    `include "../coverage/soc_coverage.sv"

    // Verification Environment
    `include "../env/soc_env.sv"

    // Virtual Sequences
    `include "../sequences/soc_reg_access_seq.sv"
    `include "../sequences/soc_access_control_seq.sv"
    `include "../sequences/soc_gateway_pipeline_seq.sv"
    `include "../sequences/soc_wdt_recovery_seq.sv"
    `include "../sequences/soc_aes_seq.sv"
    `include "../sequences/soc_dma_seq.sv"
    `include "../sequences/soc_mem_seq.sv"
    `include "../sequences/soc_stress_seq.sv"
    `include "../sequences/soc_spi_seq.sv"
    `include "../sequences/soc_uart_seq.sv"

    // Tests
    `include "../tests/soc_base_test.sv"
    `include "../tests/soc_reg_access_test.sv"
    `include "../tests/soc_access_control_test.sv"
    `include "../tests/soc_gateway_pipeline_test.sv"
    `include "../tests/soc_wdt_recovery_test.sv"
    `include "../tests/soc_aes_test.sv"
    `include "../tests/soc_dma_test.sv"
    `include "../tests/soc_mem_test.sv"
    `include "../tests/soc_stress_test.sv"
    `include "../tests/soc_spi_test.sv"
    `include "../tests/soc_uart_test.sv"

endpackage : soc_uvm_pkg

`endif // SOC_UVM_PKG_SV
