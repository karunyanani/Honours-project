// =============================================================================
// File: soc_env.sv
// Description: UVM Top-Level Verification Environment for Gateway SoC
// Instantiates VIPs:
//   - AXI4 Master / Slave Verification IP (axi_agent)
//   - SPI Industrial Sensor Verification IP (spi_agent)
//   - Full-Duplex UART Verification IP (uart_agent)
//   - GPIO & Pad Verification IP (gpio_agent)
//   - Interrupt & Fault Recovery Verification IP (interrupt_agent)
//   - Clock & Dynamic Reset Generation VIP (clk_rst_agent)
//   - Scoreboard & Functional Coverage Collectors
// =============================================================================

`ifndef SOC_ENV_SV
`define SOC_ENV_SV

class soc_env extends uvm_env;
    `uvm_component_utils(soc_env)

    axi_agent        m_axi_agent;
    spi_agent        m_spi_agent;
    uart_agent       m_uart_agent;
    gpio_agent       m_gpio_agent;
    interrupt_agent  m_interrupt_agent;
    clk_rst_agent    m_clk_rst_agent;

    soc_scoreboard   m_scoreboard;
    soc_coverage     m_coverage;

    function new(string name = "soc_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        m_axi_agent       = axi_agent::type_id::create("m_axi_agent", this);
        m_spi_agent       = spi_agent::type_id::create("m_spi_agent", this);
        m_uart_agent      = uart_agent::type_id::create("m_uart_agent", this);
        m_gpio_agent      = gpio_agent::type_id::create("m_gpio_agent", this);
        m_interrupt_agent = interrupt_agent::type_id::create("m_interrupt_agent", this);
        m_clk_rst_agent   = clk_rst_agent::type_id::create("m_clk_rst_agent", this);

        m_scoreboard      = soc_scoreboard::type_id::create("m_scoreboard", this);
        m_coverage        = soc_coverage::type_id::create("m_coverage", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // AXI VIP -> Scoreboard & Coverage
        m_axi_agent.ap.connect(m_scoreboard.axi_export);
        m_axi_agent.ap.connect(m_coverage.analysis_export);

        // SPI Sensor VIP -> Scoreboard
        m_spi_agent.ap.connect(m_scoreboard.spi_export);

        // UART VIP -> Scoreboard
        m_uart_agent.ap.connect(m_scoreboard.uart_export);

        // GPIO VIP -> Scoreboard
        m_gpio_agent.ap.connect(m_scoreboard.gpio_export);

        // Interrupt & Fault VIP -> Scoreboard
        m_interrupt_agent.ap.connect(m_scoreboard.irq_export);
    endfunction

endclass : soc_env

`endif // SOC_ENV_SV
