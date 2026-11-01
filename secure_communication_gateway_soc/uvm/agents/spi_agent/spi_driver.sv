// =============================================================================
// File: spi_driver.sv
// Description: UVM Driver for SPI Sensor VIP (Slave Responder & Sensor Streamer)
// =============================================================================

`ifndef SPI_DRIVER_SV
`define SPI_DRIVER_SV

class spi_driver extends uvm_driver #(spi_seq_item);
    `uvm_component_utils(spi_driver)

    virtual spi_if.driver vif;
    spi_agent_config      cfg;

    function new(string name = "spi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
        end
        if (!uvm_config_db #(spi_agent_config)::get(this, "", "cfg", cfg)) begin
            cfg = spi_agent_config::type_id::create("default_spi_cfg");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.drv_cb.miso        <= 1'b0;
        vif.drv_cb.sensor_drdy <= 1'b0;
        wait (vif.rst === 1'b0);

        forever begin
            seq_item_port.get_next_item(req);
            if (req.trans_type == spi_seq_item::SPI_BURST_BLOCK) begin
                send_burst(req);
            end else begin
                send_byte(req);
            end
            seq_item_port.item_done();
        end
    endtask

    virtual task send_byte(spi_seq_item item);
        bit [7:0] mosi_in = 8'h00;

        // DRDY pulse before transfer to notify SoC
        if (item.assert_drdy) begin
            repeat (item.inter_byte_delay) @(vif.drv_cb);
            vif.drv_cb.sensor_drdy <= 1'b1;
            repeat (cfg.drdy_pulse_width) @(vif.drv_cb);
            vif.drv_cb.sensor_drdy <= 1'b0;
        end

        // Wait for chip select asserted by SoC Master
        wait (vif.cs_n === 1'b0);

        // Shift 8 bits on MISO synchronous to SCLK
        for (int i = 7; i >= 0; i--) begin
            @(negedge vif.sclk);
            vif.drv_cb.miso <= item.data_byte[i];
            @(posedge vif.sclk);
            mosi_in[i] = vif.mosi;
        end

        item.mosi_cmd = mosi_in;
        wait (vif.cs_n === 1'b1);
        vif.drv_cb.miso <= 1'b0;
    endtask

    virtual task send_burst(spi_seq_item item);
        // Pulse DRDY to notify SoC of ready block
        if (item.assert_drdy) begin
            repeat (item.inter_byte_delay) @(vif.drv_cb);
            vif.drv_cb.sensor_drdy <= 1'b1;
            repeat (cfg.drdy_pulse_width) @(vif.drv_cb);
            vif.drv_cb.sensor_drdy <= 1'b0;
        end

        for (int b = 0; b < item.payload_bytes.size(); b++) begin
            wait (vif.cs_n === 1'b0);
            for (int i = 7; i >= 0; i--) begin
                @(negedge vif.sclk);
                vif.drv_cb.miso <= item.payload_bytes[b][i];
                @(posedge vif.sclk);
            end
            wait (vif.cs_n === 1'b1);
            vif.drv_cb.miso <= 1'b0;
        end
    endtask

endclass : spi_driver

`endif // SPI_DRIVER_SV
