// =============================================================================
// File: spi_agent_config.sv
// Description: Configuration Object for SPI Sensor Verification IP
// =============================================================================

`ifndef SPI_AGENT_CONFIG_SV
`define SPI_AGENT_CONFIG_SV

class spi_agent_config extends uvm_object;
    `uvm_object_utils(spi_agent_config)

    uvm_active_passive_enum is_active = UVM_ACTIVE;

    bit cpol = 1'b0; // Clock polarity (0 = idle low, 1 = idle high)
    bit cpha = 1'b0; // Clock phase (0 = sample on leading edge, 1 = trailing)
    int word_len = 8; // Bits per transfer

    // Industrial sensor telemetry options
    bit auto_drdy_pulse  = 1'b1;
    int drdy_pulse_width = 2; // clock cycles
    int default_telemetry_len = 16; // 16-byte telemetry frame for AES-128 block

    function new(string name = "spi_agent_config");
        super.new(name);
    endfunction

endclass : spi_agent_config

`endif // SPI_AGENT_CONFIG_SV

