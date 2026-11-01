// =============================================================================
// spi.v  –  SPI Controller (master mode, configurable CPOL/CPHA, RX FIFO)
//
// Spec refs:
//   - Section 4 : M7, base 0x10000500, 256 B
//   - Section 5 : CPU and DMA accessible
//   - Section 8 : Configurable CPOL/CPHA; RX FIFO; spi_rx_dma_req when data
//                 is available; overflow status.
//
// Register map (byte offsets):
//   0x00  SPI_TX_DATA  W   : byte to transmit
//   0x04  SPI_RX_DATA  R   : pop one byte from RX FIFO
//   0x08  SPI_STATUS   R   : [0]=TX_FULL [1]=RX_EMPTY [2]=BUSY [3]=RX_DMA_REQ
//                            [4]=RX_OVF (overflow)
//   0x0C  SPI_CTRL     RW  : [0]=EN [1]=CPOL [2]=CPHA [3]=CS_AUTO
//   0x10  SPI_CLK_DIV  RW  : clock divider (SCK = clk / (2*(CLK_DIV+1)))
//
// TX FIFO: 8 bytes, RX FIFO: 16 bytes.
// DMA request (spi_rx_dma_req) asserted when RX FIFO is NOT empty.
//
// SPI mode table:
//   CPOL=0, CPHA=0 (Mode 0): SCK idles low, data captured on rising edge
//   CPOL=0, CPHA=1 (Mode 1): SCK idles low, data captured on falling edge
//   CPOL=1, CPHA=0 (Mode 2): SCK idles high, data captured on falling edge
//   CPOL=1, CPHA=1 (Mode 3): SCK idles high, data captured on rising edge
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module spi #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter TX_FIFO_DEPTH = 8,
    parameter RX_FIFO_DEPTH = 16,
    parameter DEFAULT_DIV   = 8'd24    // 50 MHz / (2*25) = 1 MHz SCK
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

    // SPI physical interface
    output wire                    spi_sck,
    output wire                    spi_mosi,
    input  wire                    spi_miso,
    output reg                     spi_cs_n,   // active-low chip select

    // DMA sideband
    output wire                    spi_rx_dma_req   // 1 when RX FIFO not empty
);

    // =========================================================================
    // Control registers
    // =========================================================================
    reg        en_r;
    reg        cpol_r;
    reg        cpha_r;
    reg        cs_auto_r;
    reg [7:0]  clk_div_r;

    initial begin
        en_r      = 1'b0;
        cpol_r    = 1'b0;
        cpha_r    = 1'b0;
        cs_auto_r = 1'b0;
        clk_div_r = DEFAULT_DIV;
    end

    // =========================================================================
    // TX FIFO
    // =========================================================================
    localparam TX_PTR_W = $clog2(TX_FIFO_DEPTH);

    reg [7:0]          tx_fifo [0:TX_FIFO_DEPTH-1];
    reg [TX_PTR_W:0]   tx_wptr;
    reg [TX_PTR_W:0]   tx_rptr;

    wire tx_full  = (tx_wptr[TX_PTR_W]   != tx_rptr[TX_PTR_W]) &&
                    (tx_wptr[TX_PTR_W-1:0] == tx_rptr[TX_PTR_W-1:0]);
    wire tx_empty = (tx_wptr == tx_rptr);

    // =========================================================================
    // RX FIFO
    // =========================================================================
    localparam RX_PTR_W = $clog2(RX_FIFO_DEPTH);

    reg [7:0]          rx_fifo [0:RX_FIFO_DEPTH-1];
    reg [RX_PTR_W:0]   rx_wptr;
    reg [RX_PTR_W:0]   rx_rptr;

    wire rx_full  = (rx_wptr[RX_PTR_W]   != rx_rptr[RX_PTR_W]) &&
                    (rx_wptr[RX_PTR_W-1:0] == rx_rptr[RX_PTR_W-1:0]);
    wire rx_empty = (rx_wptr == rx_rptr);
    reg  rx_ovf_r;

    assign spi_rx_dma_req = !rx_empty & en_r;

    // =========================================================================
    // SCK generator
    // =========================================================================
    reg [7:0] sck_cnt;
    reg       sck_r;           // current SCK value
    reg       sck_tick;        // toggle tick

    always @(posedge clk) begin
        if (rst) begin
            sck_cnt  <= 8'd0;
            sck_r    <= 1'b0;
            sck_tick <= 1'b0;
        end else if (en_r) begin
            if (sck_cnt == 8'd0) begin
                sck_cnt  <= clk_div_r;
                sck_r    <= ~sck_r;
                sck_tick <= 1'b1;
            end else begin
                sck_cnt  <= sck_cnt - 1'b1;
                sck_tick <= 1'b0;
            end
        end else begin
            sck_r    <= cpol_r;   // idle level
            sck_tick <= 1'b0;
        end
    end

    assign spi_sck = sck_r;

    // =========================================================================
    // SPI shift engine
    // =========================================================================
    localparam SPI_IDLE  = 2'd0;
    localparam SPI_CS    = 2'd1;   // assert CS, load shift reg
    localparam SPI_SHIFT = 2'd2;   // 8 bit-clocks
    localparam SPI_DONE  = 2'd3;   // deassert CS, push RX byte

    reg [1:0]  spi_state;
    reg [7:0]  shift_tx;
    reg [7:0]  shift_rx;
    reg [2:0]  bit_cnt;
    reg        mosi_r;

    always @(posedge clk) begin
        if (rst) begin
            spi_state <= SPI_IDLE;
            spi_cs_n  <= 1'b1;
            mosi_r    <= 1'b0;
            bit_cnt   <= 3'd0;
            tx_rptr   <= 0;
            rx_wptr   <= 0;
            rx_ovf_r  <= 1'b0;
        end else begin
            case (spi_state)
                SPI_IDLE: begin
                    spi_cs_n <= 1'b1;
                    if (en_r && !tx_empty && sck_tick) begin
                        shift_tx  <= tx_fifo[tx_rptr[TX_PTR_W-1:0]];
                        tx_rptr   <= tx_rptr + 1'b1;
                        bit_cnt   <= 3'd0;
                        spi_state <= cs_auto_r ? SPI_CS : SPI_SHIFT;
                    end
                end
                SPI_CS: begin
                    spi_cs_n  <= 1'b0;
                    spi_state <= SPI_SHIFT;
                end
                SPI_SHIFT: begin
                    spi_cs_n <= 1'b0;
                    if (sck_tick) begin
                        // Sample MISO on capture edge
                        if (!cpol_r ^ !cpha_r ? (sck_r == 1'b0) : (sck_r == 1'b1)) begin
                            // leading edge: shift out
                            mosi_r   <= shift_tx[7];
                            shift_tx <= {shift_tx[6:0], 1'b0};
                        end else begin
                            // trailing edge: sample in
                            shift_rx  <= {shift_rx[6:0], spi_miso};
                            bit_cnt   <= bit_cnt + 1'b1;
                            if (bit_cnt == 3'd7)
                                spi_state <= SPI_DONE;
                        end
                    end
                end
                SPI_DONE: begin
                    spi_cs_n <= 1'b1;
                    if (!rx_full) begin
                        rx_fifo[rx_wptr[RX_PTR_W-1:0]] <= shift_rx;
                        rx_wptr   <= rx_wptr + 1'b1;
                    end else begin
                        rx_ovf_r <= 1'b1;   // overflow
                    end
                    spi_state <= SPI_IDLE;
                end
                default: spi_state <= SPI_IDLE;
            endcase
        end
    end

    assign spi_mosi = mosi_r;

    wire spi_busy = (spi_state != SPI_IDLE);

    // =========================================================================
    // AXI4-Lite slave – write path
    // =========================================================================
    reg  [ADDR_WIDTH-1:0] aw_addr_lat;
    reg                   aw_pend;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire [7:0] cur_wr_off = aw_pend ? aw_addr_lat[7:0] : s_axi_awaddr[7:0];
    wire [DATA_WIDTH-1:0] cur_wdata = s_axi_wdata;
    wire [DATA_WIDTH/8-1:0] cur_wstrb = s_axi_wstrb;
    wire wr_fire = (aw_fire && w_fire) || (aw_pend && w_fire);

    wire tx_fifo_wen = wr_fire && (cur_wr_off == 8'h00) && !tx_full;

    always @(posedge clk) begin
        if (rst) begin
            tx_wptr <= 0;
        end else if (tx_fifo_wen) begin
            tx_fifo[tx_wptr[TX_PTR_W-1:0]] <= cur_wdata[7:0];
            tx_wptr <= tx_wptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_pend       <= 1'b0;
            aw_addr_lat   <= {ADDR_WIDTH{1'b0}};
            en_r          <= 1'b0;
            cpol_r        <= 1'b0;
            cpha_r        <= 1'b0;
            cs_auto_r     <= 1'b0;
            clk_div_r     <= DEFAULT_DIV;
        end else begin
            if (aw_fire && w_fire) begin
                case (cur_wr_off)
                    8'h00: ;  // Handled by tx_fifo_wen
                    8'h0C: begin  // SPI_CTRL
                        if (cur_wstrb[0]) begin
                            en_r      <= cur_wdata[0];
                            cpol_r    <= cur_wdata[1];
                            cpha_r    <= cur_wdata[2];
                            cs_auto_r <= cur_wdata[3];
                        end
                    end
                    8'h10: begin  // SPI_CLK_DIV
                        if (cur_wstrb[0]) clk_div_r <= cur_wdata[7:0];
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
                    8'h00: ;  // Handled by tx_fifo_wen
                    8'h0C: begin  // SPI_CTRL
                        if (cur_wstrb[0]) begin
                            en_r      <= cur_wdata[0];
                            cpol_r    <= cur_wdata[1];
                            cpha_r    <= cur_wdata[2];
                            cs_auto_r <= cur_wdata[3];
                        end
                    end
                    8'h10: begin  // SPI_CLK_DIV
                        if (cur_wstrb[0]) clk_div_r <= cur_wdata[7:0];
                    end
                    default: ;
                endcase
                s_axi_wready  <= 1'b0;
                aw_pend       <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end
            // B
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite slave – read path (RX FIFO pop on SPI_RX_DATA read)
    // =========================================================================
    reg rx_pop;
    always @(posedge clk) begin
        if (rst) begin
            rx_rptr <= 0;
        end else if (rx_pop && !rx_empty) begin
            rx_rptr <= rx_rptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        rx_pop <= 1'b0;
        if (rst) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                case (s_axi_araddr[7:0])
                    8'h04: begin  // SPI_RX_DATA – destructive read
                        s_axi_rdata <= {{24{1'b0}}, rx_fifo[rx_rptr[RX_PTR_W-1:0]]};
                        rx_pop      <= !rx_empty;
                    end
                    8'h08: s_axi_rdata <= {27'd0, rx_ovf_r, spi_rx_dma_req, spi_busy, rx_empty, tx_full};
                    8'h0C: s_axi_rdata <= {28'd0, cs_auto_r, cpha_r, cpol_r, en_r};
                    8'h10: s_axi_rdata <= {24'd0, clk_div_r};
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
