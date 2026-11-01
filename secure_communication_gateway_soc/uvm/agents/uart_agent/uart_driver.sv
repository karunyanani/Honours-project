// =============================================================================
// File: uart_driver.sv
// Description: UVM Driver for UART VIP – Transmits Serial 8N1 Bitstream
// =============================================================================

`ifndef UART_DRIVER_SV
`define UART_DRIVER_SV

class uart_driver extends uvm_driver #(uart_seq_item);
    `uvm_component_utils(uart_driver)

    virtual uart_if.driver vif;
    uart_agent_config      cfg;

    function new(string name = "uart_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual uart_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        if (!uvm_config_db #(uart_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = uart_agent_config::type_id::create("default_uart_cfg");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.drv_cb.uart_rx <= 1'b1; // Idle high
        wait (vif.rst === 1'b0);

        forever begin
            seq_item_port.get_next_item(req);
            transmit_byte(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task transmit_byte(uart_seq_item item);
        bit parity_bit;

        // Inter-byte delay
        if (item.inter_byte_delay > 0) begin
            repeat (item.inter_byte_delay * cfg.clks_per_bit) @(vif.drv_cb);
        end

        // 1. Start bit (Low)
        vif.drv_cb.uart_rx <= 1'b0;
        repeat (cfg.clks_per_bit) @(vif.drv_cb);

        // 2. Data bits (LSB first)
        for (int i = 0; i < cfg.data_bits; i++) begin
            vif.drv_cb.uart_rx <= item.data_byte[i];
            repeat (cfg.clks_per_bit) @(vif.drv_cb);
        end

        // 3. Optional Parity bit
        if (cfg.parity_enable) begin
            parity_bit = ^item.data_byte; // Even parity
            if (cfg.parity_odd) parity_bit = ~parity_bit; // Odd parity
            if (item.inject_parity_error) parity_bit = ~parity_bit;

            vif.drv_cb.uart_rx <= parity_bit;
            repeat (cfg.clks_per_bit) @(vif.drv_cb);
        end

        // 4. Stop bit(s) (High unless injected frame error)
        vif.drv_cb.uart_rx <= item.inject_frame_error ? 1'b0 : 1'b1;
        repeat (cfg.stop_bits * cfg.clks_per_bit) @(vif.drv_cb);

        // Return to idle
        vif.drv_cb.uart_rx <= 1'b1;
    endtask

endclass : uart_driver

`endif // UART_DRIVER_SV

