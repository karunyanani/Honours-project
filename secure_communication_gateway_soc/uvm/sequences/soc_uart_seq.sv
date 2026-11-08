// =============================================================================
// File: soc_uart_seq.sv
// Description: UVM Sequence validating Full-Duplex UART 8N1 Interface
// =============================================================================

`ifndef SOC_UART_SEQ_SV
`define SOC_UART_SEQ_SV

class soc_uart_seq extends soc_base_seq;
    `uvm_object_utils(soc_uart_seq)

    function new(string name = "soc_uart_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] rdata;
        bit [1:0]  resp;

        `uvm_info("UART_SEQ", "Starting UART Controller Verification Sequence...", UVM_LOW)

        // 1. Program UART Baud Divisor (div=4 for fast simulation)
        axi_write(32'h1000_000C, 32'd4);
        axi_read (32'h1000_000C, rdata, resp);
        if (rdata[15:0] !== 16'd4)
            `uvm_error("UART_SEQ", $sformatf("UART BAUD_DIV mismatch: exp=4 act=%0d", rdata[15:0]))

        // 2. Enable UART TX and RX (CTRL: TX_EN=1, RX_EN=1 -> 0x03)
        axi_write(32'h1000_0010, 32'h0000_0003);
        axi_read (32'h1000_0010, rdata, resp);
        if ((rdata & 32'h0000_0003) !== 32'h0000_0003)
            `uvm_error("UART_SEQ", $sformatf("UART CTRL mismatch: act=0x%08h", rdata))

        // 3. Verify Status: TX_FULL must be 0, TX_DMA_REQ must be 1
        axi_read(32'h1000_0008, rdata, resp);
        if (rdata[0] !== 1'b0) // TX_FULL
            `uvm_error("UART_SEQ", "UART TX_FULL unexpectedly set on empty FIFO")
        if (rdata[2] !== 1'b1) // TX_DMA_REQ
            `uvm_error("UART_SEQ", "UART TX_DMA_REQ not asserted when FIFO has free space")

        // 4. Stream 4 bytes into UART TX Data FIFO
        axi_write(32'h1000_0000, 32'h0000_0055); // 'U'
        axi_write(32'h1000_0000, 32'h0000_0041); // 'A'
        axi_write(32'h1000_0000, 32'h0000_0052); // 'R'
        axi_write(32'h1000_0000, 32'h0000_0054); // 'T'

        // 5. Read back status post-write
        axi_read(32'h1000_0008, rdata, resp);
        `uvm_info("UART_SEQ", $sformatf("UART Status post-transmit write: 0x%08h", rdata), UVM_HIGH)

        `uvm_info("UART_SEQ", "UART Controller Verification Sequence completed successfully!", UVM_LOW)
    endtask

endclass : soc_uart_seq

`endif // SOC_UART_SEQ_SV

