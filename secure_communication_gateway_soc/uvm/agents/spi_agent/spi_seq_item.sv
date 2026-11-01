// =============================================================================
// File: spi_seq_item.sv
// Description: UVM Sequence Item for SPI Sensor Transactions & Telemetry Frames
// =============================================================================

`ifndef SPI_SEQ_ITEM_SV
`define SPI_SEQ_ITEM_SV

class spi_seq_item extends uvm_sequence_item;
    `uvm_object_utils(spi_seq_item)

    typedef enum bit {
        SPI_SINGLE_BYTE = 1'b0,
        SPI_BURST_BLOCK = 1'b1
    } spi_trans_e;

    rand spi_trans_e trans_type;
    rand bit [7:0]   data_byte;
    rand bit [7:0]   payload_bytes[];
    rand int         inter_byte_delay;
    rand bit         assert_drdy;

    // Captured from MOSI during transfer
    bit [7:0]        mosi_cmd;

    constraint c_delay {
        inter_byte_delay inside {[1:15]};
    }

    constraint c_payload {
        payload_bytes.size() inside {1, 2, 4, 8, 16};
    }

    function new(string name = "spi_seq_item");
        super.new(name);
        trans_type       = SPI_SINGLE_BYTE;
        data_byte        = 8'h00;
        inter_byte_delay = 2;
        assert_drdy      = 1'b1;
    endfunction

    virtual function string convert2string();
        if (trans_type == SPI_SINGLE_BYTE)
            return $sformatf("SPI_ITEM: [SINGLE] MISO=0x%02h MOSI=0x%02h DRDY=%0b",
                data_byte, mosi_cmd, assert_drdy);
        else
            return $sformatf("SPI_ITEM: [BURST_%0d] DRDY=%0b", payload_bytes.size(), assert_drdy);
    endfunction

    virtual function void do_copy(uvm_object rhs);
        spi_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return;
        super.do_copy(rhs);
        this.trans_type       = rhs_.trans_type;
        this.data_byte        = rhs_.data_byte;
        this.payload_bytes    = rhs_.payload_bytes;
        this.inter_byte_delay = rhs_.inter_byte_delay;
        this.assert_drdy      = rhs_.assert_drdy;
        this.mosi_cmd         = rhs_.mosi_cmd;
    endfunction

endclass : spi_seq_item

`endif // SPI_SEQ_ITEM_SV
