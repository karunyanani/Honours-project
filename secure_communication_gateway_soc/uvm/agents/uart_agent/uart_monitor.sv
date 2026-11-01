// =============================================================================
// File: uart_monitor.sv
// Description: UVM Monitor for UART Serial Output
// =============================================================================

`ifndef UART_MONITOR_SV
`define UART_MONITOR_SV

class uart_monitor extends uvm_monitor;
    `uvm_component_utils(uart_monitor)

    virtual uart_if.monitor vif;
    uart_agent_config       cfg;
    uvm_analysis_port #(uart_seq_item) ap;

    function new(string name = "uart_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
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
        uart_seq_item item;
        bit [7:0] rx_byte;

        forever begin
            // Wait for start bit (falling edge on uart_tx)
            @(negedge vif.mon_cb.uart_tx);

            // Sample at center of start bit
            repeat (cfg.clks_per_bit / 2) @(vif.mon_cb);
            if (vif.mon_cb.uart_tx !== 1'b0) continue; // Glitch filter / false start

            // Sample data bits (LSB first)
            for (int i = 0; i < cfg.data_bits; i++) begin
                repeat (cfg.clks_per_bit) @(vif.mon_cb);
                rx_byte[i] = vif.mon_cb.uart_tx;
            end

            // Sample stop bit
            repeat (cfg.clks_per_bit) @(vif.mon_cb);

            item = uart_seq_item::type_id::create("uart_mon_item");
            item.direction   = uart_seq_item::UART_TX;
            item.data_byte   = rx_byte;
            item.frame_error = (vif.mon_cb.uart_tx !== 1'b1);

            ap.write(item);
        end
    endtask

endclass : uart_monitor

`endif // UART_MONITOR_SV
