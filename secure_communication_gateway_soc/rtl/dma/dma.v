// =============================================================================
// dma.v  –  DMA Controller  (AXI4 master + AXI4-Lite slave config port)
//
// Spec refs:
//   - Section 4  : M6, base 0x10000400, 256 B  (config registers, CPU only)
//   - Section 5  : DMA is master S1 on interconnect; can access DMEM/UART/AES/SPI
//   - Section 10 : Two transfer modes:
//                    MODE 0  SPI → AES  : read bytes from SPI_RX_DATA, write
//                                          to AES_DATA_IN0..3, then trigger START
//                    MODE 1  AES → UART : read AES_DATA_OUT0..3, write
//                                          to UART_TX_DATA (byte-by-byte from
//                                          the 4×32-bit words = 16 bytes total)
//   - Section 12 : wdt_rst_i clears datapath FSM, preserves config registers
//
// Config register map (byte offsets from DMA_BASE = 0x10000400):
//   0x00  DMA_SRC_ADDR  RW  : source AXI address (used in MODE 0: SPI_RX_DATA)
//   0x04  DMA_DST_ADDR  RW  : destination AXI address
//   0x08  DMA_LEN       RW  : transfer length in bytes (max 255 for peripherals)
//   0x0C  DMA_CTRL      RW  : [0]=START  [1]=MODE (0=SPI→AES, 1=AES→UART)
//   0x10  DMA_STATUS    R   : [0]=DONE   [1]=BUSY  [2]=ERR
//
// AXI4 master interface:
//   - Issues single-beat (INCR, LEN=0) AXI transactions.
//   - Handles read-data and write-response handshakes.
//   - Issues one transaction per byte/word as required by mode.
//
// DMA sideband inputs (from peripherals):
//   spi_rx_dma_req   – SPI RX FIFO has data (used as trigger in MODE 0)
//   uart_tx_dma_req  – UART TX FIFO has space (used as back-pressure in MODE 1)
//
// Operation overview:
//   MODE 0 (SPI → AES):
//     1. Wait for spi_rx_dma_req.
//     2. Read DMA_LEN bytes from SRC_ADDR (SPI_RX_DATA) one word at a time,
//        assembling into plaintext buffer.
//     3. Write to AES_DATA_IN0..3.
//     4. Write AES_CTRL = START | KEY_VALID.
//     5. Assert DONE.
//
//   MODE 1 (AES → UART):
//     1. Read AES_DATA_OUT0..3 (4 × 32-bit words = 16 bytes ciphertext).
//     2. Write each byte to UART_TX_DATA, gated by uart_tx_dma_req.
//     3. Assert DONE.
//
// Scoped watchdog reset (wdt_rst_i):
//   Resets the FSM and datapath registers but does NOT clear the config
//   registers (SRC_ADDR, DST_ADDR, LEN, CTRL, STATUS).
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module dma #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 8,
    // Fixed peripheral addresses (mirrored from soc_defines.vh)
    parameter [ADDR_WIDTH-1:0] SPI_RX_DATA_ADDR  = 32'h1000_0504,  // SPI_BASE + 0x04
    parameter [ADDR_WIDTH-1:0] AES_DATA_IN0_ADDR  = 32'h1000_0318,  // AES_BASE + 0x18
    parameter [ADDR_WIDTH-1:0] AES_CTRL_ADDR      = 32'h1000_0310,  // AES_BASE + 0x10
    parameter [ADDR_WIDTH-1:0] AES_DATA_OUT0_ADDR = 32'h1000_0328,  // AES_BASE + 0x28
    parameter [ADDR_WIDTH-1:0] UART_TX_DATA_ADDR  = 32'h1000_0000   // UART_BASE + 0x00
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    wdt_rst,   // scoped watchdog reset

    // =========================================================================
    // AXI4-Lite slave: config registers (CPU drives this)
    // =========================================================================
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

    // =========================================================================
    // AXI4 master: DMA data transfers (connects to interconnect S1)
    // =========================================================================
    // Write address channel
    output reg  [ID_WIDTH-1:0]     m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output reg  [7:0]              m_axi_awlen,
    output reg  [2:0]              m_axi_awsize,
    output reg  [1:0]              m_axi_awburst,
    output reg                     m_axi_awlock,
    output reg  [3:0]              m_axi_awcache,
    output reg  [2:0]              m_axi_awprot,
    output reg  [3:0]              m_axi_awqos,
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,

    // Write data channel
    output reg  [DATA_WIDTH-1:0]   m_axi_wdata,
    output reg  [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                     m_axi_wlast,
    output reg                     m_axi_wvalid,
    input  wire                    m_axi_wready,

    // Write response channel
    input  wire [ID_WIDTH-1:0]     m_axi_bid,
    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready,

    // Read address channel
    output reg  [ID_WIDTH-1:0]     m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]   m_axi_araddr,
    output reg  [7:0]              m_axi_arlen,
    output reg  [2:0]              m_axi_arsize,
    output reg  [1:0]              m_axi_arburst,
    output reg                     m_axi_arlock,
    output reg  [3:0]              m_axi_arcache,
    output reg  [2:0]              m_axi_arprot,
    output reg  [3:0]              m_axi_arqos,
    output reg                     m_axi_arvalid,
    input  wire                    m_axi_arready,

    // Read data channel
    input  wire [ID_WIDTH-1:0]     m_axi_rid,
    input  wire [DATA_WIDTH-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output reg                     m_axi_rready,

    // =========================================================================
    // Sideband request lines from peripherals
    // =========================================================================
    input  wire                    spi_rx_dma_req,   // SPI RX FIFO non-empty
    input  wire                    uart_tx_dma_req    // UART TX FIFO has space
);

    // =========================================================================
    // Config registers (retained across wdt_rst)
    // =========================================================================
    reg [ADDR_WIDTH-1:0] src_addr_r;
    reg [ADDR_WIDTH-1:0] dst_addr_r;
    reg [DATA_WIDTH-1:0] len_r;       // transfer length in bytes
    reg                  mode_r;      // 0=SPI→AES, 1=AES→UART
    reg                  start_r;     // one-shot START pulse

    reg                  done_r;
    reg                  busy_r;
    reg                  err_r;

    // =========================================================================
    // FSM
    // =========================================================================
    localparam [3:0]
        S_IDLE         = 4'd0,
        // MODE 0: SPI → AES
        S_SPI_WAIT     = 4'd1,   // wait for spi_rx_dma_req
        S_SPI_READ_AR  = 4'd2,   // issue AR to SPI_RX_DATA
        S_SPI_READ_R   = 4'd3,   // wait for R data
        S_AES_WRITE_AW = 4'd4,   // issue AW to AES_DATA_IN
        S_AES_WRITE_W  = 4'd5,   // issue W data
        S_AES_WRITE_B  = 4'd6,   // wait for B response
        S_AES_TRIG_AW  = 4'd7,   // write AES_CTRL = START|KEY_VALID
        S_AES_TRIG_W   = 4'd8,
        S_AES_TRIG_B   = 4'd9,
        // MODE 1: AES → UART
        S_AESOUT_AR    = 4'd10,  // issue AR to AES_DATA_OUT[n]
        S_AESOUT_R     = 4'd11,  // wait for R data
        S_UART_WAIT    = 4'd12,  // wait for uart_tx_dma_req
        S_UART_WRITE_AW= 4'd13,
        S_UART_WRITE_W = 4'd14,
        S_UART_WRITE_B = 4'd15;
    // Extra states encoded as {1'b1, 3'd...} – repurpose IDLE
    // For simplicity fit all states in the 4-bit field above.
    // S_DONE is handled by returning to IDLE after setting done_r.

    reg [3:0]  state;
    reg [4:0]  word_cnt;    // 0..3 for 4 AES words; 0..15 for 16 bytes
    reg [7:0]  byte_idx;    // byte index within current word (0..3)

    // Accumulated read data buffer (for reassembly from SPI bytes or AES words)
    reg [127:0] data_buf;

    // AES output word pointer
    reg [31:0]  aes_word_buf;   // holds one 32-bit read from AES_DATA_OUT
    reg [1:0]   byte_of_word;   // which byte of current word to transmit next

    wire do_rst = rst | wdt_rst;

    always @(posedge clk) begin
        if (do_rst) begin
            state        <= S_IDLE;
            word_cnt     <= 5'd0;
            byte_idx     <= 8'd0;
            byte_of_word <= 2'd0;
            data_buf     <= 128'd0;
            aes_word_buf <= 32'd0;
            // AXI master defaults
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axi_awid    <= {ID_WIDTH{1'b0}};
            m_axi_awlen   <= 8'd0;
            m_axi_awsize  <= 3'd2;   // 4 bytes
            m_axi_awburst <= 2'b01;  // INCR
            m_axi_awlock  <= 1'b0;
            m_axi_awcache <= 4'b0011;
            m_axi_awprot  <= 3'b000;
            m_axi_awqos   <= 4'd0;
            m_axi_wlast   <= 1'b1;
            m_axi_arid    <= {ID_WIDTH{1'b0}};
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'd2;
            m_axi_arburst <= 2'b01;
            m_axi_arlock  <= 1'b0;
            m_axi_arcache <= 4'b0011;
            m_axi_arprot  <= 3'b000;
            m_axi_arqos   <= 4'd0;
            // Clear busy when datapath reset to IDLE; retain config regs on wdt_rst
            busy_r <= 1'b0;
            if (rst) begin
                done_r  <= 1'b0;
                err_r   <= 1'b0;
            end
        end else begin

            case (state)
                // ------------------------------------------------------------------
                S_IDLE: begin
                    if (start_r) begin
                        busy_r   <= 1'b1;
                        done_r   <= 1'b0;
                        err_r    <= 1'b0;
                        word_cnt <= 5'd0;
                        byte_idx <= 8'd0;
                        if (!mode_r) begin
                            state <= S_SPI_WAIT;
                        end else begin
                            m_axi_araddr  <= AES_DATA_OUT0_ADDR;
                            m_axi_arvalid <= 1'b1;
                            byte_of_word  <= 2'd0;
                            state         <= S_AESOUT_AR;
                        end
                    end
                end

                // ==================================================================
                //  MODE 0: SPI → AES
                // ==================================================================
                S_SPI_WAIT: begin
                    if (spi_rx_dma_req) begin
                        m_axi_araddr  <= SPI_RX_DATA_ADDR;
                        m_axi_arvalid <= 1'b1;
                        state         <= S_SPI_READ_AR;
                    end
                end

                S_SPI_READ_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_SPI_READ_R;
                    end
                end

                S_SPI_READ_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        // Accumulate bytes into data_buf
                        // Each SPI read returns 1 byte in [7:0]
                        // Pack into data_buf MSB-first
                        data_buf <= {data_buf[119:0], m_axi_rdata[7:0]};
                        byte_idx <= byte_idx + 1'b1;
                        if (byte_idx == 8'd15) begin
                            // 16 bytes read – write to AES
                            byte_idx      <= 8'd0;
                            word_cnt      <= 5'd0;
                            m_axi_awaddr  <= AES_DATA_IN0_ADDR;
                            m_axi_awvalid <= 1'b1;
                            state         <= S_AES_WRITE_AW;
                        end else if (!spi_rx_dma_req) begin
                            // More bytes to come but none ready yet
                            state <= S_SPI_WAIT;
                        end else begin
                            m_axi_araddr  <= SPI_RX_DATA_ADDR;
                            m_axi_arvalid <= 1'b1;
                            state         <= S_SPI_READ_AR;
                        end
                    end
                end

                S_AES_WRITE_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        // Select the right 32-bit word from data_buf
                        case (word_cnt[1:0])
                            2'd0: m_axi_wdata <= data_buf[127:96];
                            2'd1: m_axi_wdata <= data_buf[ 95:64];
                            2'd2: m_axi_wdata <= data_buf[ 63:32];
                            2'd3: m_axi_wdata <= data_buf[ 31: 0];
                        endcase
                        m_axi_wstrb  <= 4'hF;
                        m_axi_wlast  <= 1'b1;
                        m_axi_wvalid <= 1'b1;
                        state        <= S_AES_WRITE_W;
                    end
                end

                S_AES_WRITE_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state        <= S_AES_WRITE_B;
                    end
                end

                S_AES_WRITE_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        if (m_axi_bresp != 2'b00)
                            err_r <= 1'b1;
                        word_cnt <= word_cnt + 1'b1;
                        if (word_cnt == 5'd3) begin
                            // All 4 words written – trigger AES
                            word_cnt      <= 5'd0;
                            m_axi_awaddr  <= AES_CTRL_ADDR;
                            m_axi_awvalid <= 1'b1;
                            state         <= S_AES_TRIG_AW;
                        end else begin
                            m_axi_awaddr  <= AES_DATA_IN0_ADDR + {word_cnt[1:0] + 2'd1, 2'b00};
                            m_axi_awvalid <= 1'b1;
                            state         <= S_AES_WRITE_AW;
                        end
                    end
                end

                S_AES_TRIG_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata  <= 32'h0000_0003;  // START=1, KEY_VALID=1
                        m_axi_wstrb  <= 4'h1;
                        m_axi_wlast  <= 1'b1;
                        m_axi_wvalid <= 1'b1;
                        state        <= S_AES_TRIG_W;
                    end
                end

                S_AES_TRIG_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state        <= S_AES_TRIG_B;
                    end
                end

                S_AES_TRIG_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        // Transfer complete – set DONE and return to IDLE
                        done_r  <= 1'b1;
                        busy_r  <= 1'b0;
                        state   <= S_IDLE;
                    end
                end

                // ==================================================================
                //  MODE 1: AES → UART
                // ==================================================================
                S_AESOUT_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_AESOUT_R;
                    end
                end

                S_AESOUT_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        aes_word_buf <= m_axi_rdata;
                        state        <= S_UART_WAIT;
                    end
                end

                S_UART_WAIT: begin
                    if (uart_tx_dma_req) begin
                        m_axi_awaddr  <= UART_TX_DATA_ADDR;
                        m_axi_awvalid <= 1'b1;
                        state         <= S_UART_WRITE_AW;
                    end
                end

                S_UART_WRITE_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        // Extract byte_of_word from aes_word_buf (MSB first)
                        case (byte_of_word)
                            2'd0: m_axi_wdata <= {24'h0, aes_word_buf[31:24]};
                            2'd1: m_axi_wdata <= {24'h0, aes_word_buf[23:16]};
                            2'd2: m_axi_wdata <= {24'h0, aes_word_buf[15: 8]};
                            2'd3: m_axi_wdata <= {24'h0, aes_word_buf[ 7: 0]};
                        endcase
                        m_axi_wstrb  <= 4'h1;
                        m_axi_wlast  <= 1'b1;
                        m_axi_wvalid <= 1'b1;
                        state        <= S_UART_WRITE_W;
                    end
                end

                S_UART_WRITE_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state        <= S_UART_WRITE_B;
                    end
                end

                S_UART_WRITE_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        if (m_axi_bresp != 2'b00)
                            err_r <= 1'b1;
                        byte_of_word <= byte_of_word + 1'b1;
                        if (byte_of_word == 2'd3) begin
                            // Finished 4 bytes of this word
                            word_cnt <= word_cnt + 1'b1;
                            if (word_cnt == 5'd3) begin
                                // All 16 bytes sent
                                done_r <= 1'b1;
                                busy_r <= 1'b0;
                                state  <= S_IDLE;
                            end else begin
                                m_axi_araddr  <= AES_DATA_OUT0_ADDR + {word_cnt[1:0] + 2'd1, 2'b00};
                                m_axi_arvalid <= 1'b1;
                                byte_of_word  <= 2'd0;
                                state         <= S_AESOUT_AR;
                            end
                        end else begin
                            // More bytes from same word
                            state <= S_UART_WAIT;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // AXI4-Lite slave: config register write path
    // =========================================================================
    reg [ADDR_WIDTH-1:0] cfg_aw_lat;
    reg                  cfg_aw_pend;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire [7:0] cur_wr_off = cfg_aw_pend ? cfg_aw_lat[7:0] : s_axi_awaddr[7:0];
    wire [DATA_WIDTH-1:0] cur_wdata = s_axi_wdata;
    wire [DATA_WIDTH/8-1:0] cur_wstrb = s_axi_wstrb;

    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            cfg_aw_pend   <= 1'b0;
            cfg_aw_lat    <= {ADDR_WIDTH{1'b0}};
            src_addr_r    <= {ADDR_WIDTH{1'b0}};
            dst_addr_r    <= {ADDR_WIDTH{1'b0}};
            len_r         <= {DATA_WIDTH{1'b0}};
            mode_r        <= 1'b0;
            start_r       <= 1'b0;
        end else begin
            start_r <= 1'b0;   // Single-cycle pulse default

            if (aw_fire && w_fire) begin
                case (cur_wr_off)
                    8'h00: src_addr_r <= cur_wdata;
                    8'h04: dst_addr_r <= cur_wdata;
                    8'h08: len_r      <= cur_wdata;
                    8'h0C: begin
                               if (cur_wstrb[0]) begin
                                   start_r <= cur_wdata[0] & !busy_r;
                                   mode_r  <= cur_wdata[1];
                               end
                           end
                    default: ;
                endcase
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
                cfg_aw_pend   <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end else if (aw_fire) begin
                cfg_aw_lat    <= s_axi_awaddr;
                cfg_aw_pend   <= 1'b1;
                s_axi_awready <= 1'b0;
            end else if (cfg_aw_pend && w_fire) begin
                case (cur_wr_off)
                    8'h00: src_addr_r <= cur_wdata;
                    8'h04: dst_addr_r <= cur_wdata;
                    8'h08: len_r      <= cur_wdata;
                    8'h0C: begin
                               if (cur_wstrb[0]) begin
                                   start_r <= cur_wdata[0] & !busy_r;
                                   mode_r  <= cur_wdata[1];
                               end
                           end
                    default: ;
                endcase
                s_axi_wready  <= 1'b0;
                cfg_aw_pend   <= 1'b0;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite slave: config register read path
    // =========================================================================
    wire [7:0] ar_off = s_axi_araddr[7:0];

    always @(posedge clk) begin
        if (rst) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                case (ar_off)
                    8'h00: s_axi_rdata <= src_addr_r;
                    8'h04: s_axi_rdata <= dst_addr_r;
                    8'h08: s_axi_rdata <= len_r;
                    8'h0C: s_axi_rdata <= {30'd0, mode_r, 1'b0};  // START is pulse
                    8'h10: s_axi_rdata <= {29'd0, err_r, busy_r, done_r};
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
