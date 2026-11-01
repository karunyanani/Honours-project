// =============================================================================
// uart.v  –  UART peripheral with TX FIFO, baud divider, DMA request
//
// Spec refs:
//   - Section 4  : M2, base 0x10000000, 256 B
//   - Section 11 : 8N1, configurable baud, TX FIFO, DMA req when TX space avail
//   - Section 5  : CPU and DMA accessible
//   - soc_defines.vh register map
//
// Register map (byte offsets from base address):
//   0x00  UART_TX_DATA  W   : byte to transmit (lower 8 bits)
//   0x04  UART_RX_DATA  R   : received byte (loopback / stub)
//   0x08  UART_STATUS   R   : [0]=TX_FULL [1]=RX_EMPTY [2]=TX_DMA_REQ
//   0x0C  UART_BAUD_DIV RW  : clock divider for baud rate
//   0x10  UART_CTRL     RW  : [0]=TX_EN [1]=RX_EN
//
// TX FIFO depth: 16 bytes.
// DMA request asserted when FIFO is not full (space available).
// Serial output: 8 data bits, no parity, 1 stop bit, LSB first.
//
// AXI4-Lite slave, single-beat transactions.
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module uart #(
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter FIFO_DEPTH   = 16,          // TX FIFO depth in bytes
    parameter DEFAULT_BAUD = 16'd2604     // 50 MHz / 19200 baud ≈ 2604
) (
    input  wire                    clk,
    input  wire                    rst,

    // AXI4-Lite slave
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,

    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,

    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,

    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    // Serial output
    output wire                    uart_tx,

    // DMA sideband
    output wire                    uart_tx_dma_req   // 1 when TX FIFO not full
);

    // =========================================================================
    // Registers
    // =========================================================================
    reg [15:0] baud_div_r;    // UART_BAUD_DIV
    reg        tx_en_r;       // UART_CTRL[0]
    reg        rx_en_r;       // UART_CTRL[1]

    initial begin
        baud_div_r = DEFAULT_BAUD;
        tx_en_r    = 1'b0;
        rx_en_r    = 1'b0;
    end

    // =========================================================================
    // TX FIFO  (16-byte circular buffer)
    // =========================================================================
    localparam FIFO_PTR_W = $clog2(FIFO_DEPTH);

    reg [7:0]          fifo_mem  [0:FIFO_DEPTH-1];
    reg [FIFO_PTR_W:0] fifo_wptr;   // extra bit for full/empty detection
    reg [FIFO_PTR_W:0] fifo_rptr;

    wire fifo_full  = (fifo_wptr[FIFO_PTR_W]   != fifo_rptr[FIFO_PTR_W]) &&
                      (fifo_wptr[FIFO_PTR_W-1:0] == fifo_rptr[FIFO_PTR_W-1:0]);
    wire fifo_empty = (fifo_wptr == fifo_rptr);

    // FIFO write (from AXI or DMA write to TX_DATA)
    wire fifo_wen;
    wire [7:0] fifo_wdata;

    always @(posedge clk) begin
        if (rst) begin
            fifo_wptr <= 0;
        end else if (fifo_wen && !fifo_full) begin
            fifo_mem[fifo_wptr[FIFO_PTR_W-1:0]] <= fifo_wdata;
            fifo_wptr <= fifo_wptr + 1'b1;
        end
    end

    // =========================================================================
    // Baud-rate generator  →  bit_tick every (baud_div) clocks
    // =========================================================================
    reg [15:0] baud_cnt;
    reg        bit_tick;

    always @(posedge clk) begin
        if (rst) begin
            baud_cnt <= 16'd0;
            bit_tick <= 1'b0;
        end else begin
            if (baud_cnt == 16'd0) begin
                baud_cnt <= baud_div_r - 1'b1;
                bit_tick <= 1'b1;
            end else begin
                baud_cnt <= baud_cnt - 1'b1;
                bit_tick <= 1'b0;
            end
        end
    end

    // =========================================================================
    // TX shift register  –  8N1, LSB first
    // FSM states
    // =========================================================================
    localparam TX_IDLE  = 2'd0;
    localparam TX_START = 2'd1;
    localparam TX_DATA  = 2'd2;
    localparam TX_STOP  = 2'd3;

    reg [1:0] tx_state;
    reg [7:0] tx_shift;
    reg [2:0] tx_bit_cnt;
    reg       tx_out;

    always @(posedge clk) begin
        if (rst) begin
            tx_state   <= TX_IDLE;
            tx_out     <= 1'b1;
            tx_bit_cnt <= 3'd0;
            fifo_rptr  <= 0;
        end else if (bit_tick && tx_en_r) begin
            case (tx_state)
                TX_IDLE: begin
                    tx_out <= 1'b1;
                    if (!fifo_empty) begin
                        tx_shift  <= fifo_mem[fifo_rptr[FIFO_PTR_W-1:0]];
                        fifo_rptr <= fifo_rptr + 1'b1;
                        tx_out    <= 1'b0;   // start bit
                        tx_state  <= TX_DATA;
                        tx_bit_cnt<= 3'd0;
                    end
                end
                TX_DATA: begin
                    tx_out     <= tx_shift[0];
                    tx_shift   <= {1'b0, tx_shift[7:1]};
                    tx_bit_cnt <= tx_bit_cnt + 1'b1;
                    if (tx_bit_cnt == 3'd7)
                        tx_state <= TX_STOP;
                end
                TX_STOP: begin
                    tx_out   <= 1'b1;   // stop bit
                    tx_state <= TX_IDLE;
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    assign uart_tx        = tx_out;
    assign uart_tx_dma_req = !fifo_full && tx_en_r;

    // =========================================================================
    // AXI4-Lite slave logic
    // =========================================================================
    // Decode 8-bit offset from full address
    wire [7:0] ar_off = s_axi_araddr[7:0];

    // ---- Write path ----------------------------------------------------------
    reg  [ADDR_WIDTH-1:0] aw_addr_lat;
    reg                   aw_pend;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire [7:0] cur_wr_off = aw_pend ? aw_addr_lat[7:0] : s_axi_awaddr[7:0];
    wire [DATA_WIDTH-1:0] cur_wdata = s_axi_wdata;
    wire [DATA_WIDTH/8-1:0] cur_wstrb = s_axi_wstrb;
    wire wr_fire = (aw_fire && w_fire) || (aw_pend && w_fire);

    assign fifo_wen   = wr_fire && (cur_wr_off == 8'h00) && !fifo_full;
    assign fifo_wdata = cur_wdata[7:0];

    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_pend       <= 1'b0;
            aw_addr_lat   <= {ADDR_WIDTH{1'b0}};
            baud_div_r    <= DEFAULT_BAUD;
            tx_en_r       <= 1'b0;
            rx_en_r       <= 1'b0;
        end else begin
            if (aw_fire && w_fire) begin
                case (cur_wr_off)
                    8'h00: ;  // TX_DATA handled via FIFO
                    8'h0C: begin
                        if (cur_wstrb[1]) baud_div_r[15:8] <= cur_wdata[15:8];
                        if (cur_wstrb[0]) baud_div_r[ 7:0] <= cur_wdata[ 7:0];
                    end
                    8'h10: begin
                        if (cur_wstrb[0]) tx_en_r <= cur_wdata[0];
                        if (cur_wstrb[0]) rx_en_r <= cur_wdata[1];
                    end
                    default: ;
                endcase
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
                aw_pend       <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end else if (aw_fire) begin
                aw_addr_lat   <= s_axi_awaddr;
                aw_pend       <= 1'b1;
                s_axi_awready <= 1'b0;
            end else if (aw_pend && w_fire) begin
                case (cur_wr_off)
                    8'h00: ;  // TX_DATA handled via FIFO
                    8'h0C: begin
                        if (cur_wstrb[1]) baud_div_r[15:8] <= cur_wdata[15:8];
                        if (cur_wstrb[0]) baud_div_r[ 7:0] <= cur_wdata[ 7:0];
                    end
                    8'h10: begin
                        if (cur_wstrb[0]) tx_en_r <= cur_wdata[0];
                        if (cur_wstrb[0]) rx_en_r <= cur_wdata[1];
                    end
                    default: ;
                endcase
                s_axi_wready  <= 1'b0;
                aw_pend       <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end

            // B handshake
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end
        end
    end

    // ---- Read path -----------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                case (ar_off)
                    8'h00: s_axi_rdata <= 32'd0;           // TX_DATA (write-only)
                    8'h04: s_axi_rdata <= 32'd0;           // RX_DATA stub
                    8'h08: s_axi_rdata <= {29'd0, uart_tx_dma_req, 1'b1 /*RX_EMPTY stub*/, fifo_full};
                    8'h0C: s_axi_rdata <= {16'd0, baud_div_r};
                    8'h10: s_axi_rdata <= {30'd0, rx_en_r, tx_en_r};
                    default: s_axi_rdata <= 32'd0;
                endcase
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

endmodule

`resetall
