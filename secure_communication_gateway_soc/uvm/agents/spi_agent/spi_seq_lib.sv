// =============================================================================
// File: spi_seq_lib.sv
// Description: UVM Sequence Library for SPI Sensor VIP
// =============================================================================

`ifndef SPI_SEQ_LIB_SV
`define SPI_SEQ_LIB_SV

class spi_base_seq extends uvm_sequence #(spi_seq_item);
    `uvm_object_utils(spi_base_seq)

    function new(string name = "spi_base_seq");
        super.new(name);
    endfunction

    virtual task send_sensor_byte(bit [7:0] val, bit drdy = 1'b1, int delay = 2);
        spi_seq_item item = spi_seq_item::type_id::create("spi_byte_item");
        start_item(item);
        item.trans_type       = spi_seq_item::SPI_SINGLE_BYTE;
        item.data_byte        = val;
        item.assert_drdy      = drdy;
        item.inter_byte_delay = delay;
        finish_item(item);
    endtask

    virtual task send_telemetry_frame(bit [7:0] bytes[]);
        spi_seq_item item = spi_seq_item::type_id::create("spi_burst_item");
        start_item(item);
        item.trans_type       = spi_seq_item::SPI_BURST_BLOCK;
        item.payload_bytes    = bytes;
        item.assert_drdy      = 1'b1;
        item.inter_byte_delay = 5;
        finish_item(item);
    endtask
endclass : spi_base_seq

// 16-Byte standard FIPS-197 plaintext vector injection
class spi_fips197_telemetry_seq extends spi_base_seq;
    `uvm_object_utils(spi_fips197_telemetry_seq)

    function new(string name = "spi_fips197_telemetry_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] fips_pt[16] = '{
            8'h00, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77,
            8'h88, 8'h99, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF
        };
        send_telemetry_frame(fips_pt);
    endtask
endclass : spi_fips197_telemetry_seq

`endif // SPI_SEQ_LIB_SV

