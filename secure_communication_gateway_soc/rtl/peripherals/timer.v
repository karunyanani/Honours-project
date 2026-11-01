// =============================================================================
// timer.v  –  Configurable countdown timer with auto-reload and interrupt
//
// Spec refs:
//   - Section 4 : M3, base 0x10000100, 256 B
//   - Section 5 : CPU only (DMA denied in interconnect)
//
// Register map (byte offsets):
//   0x00  TIMER_COUNT  R   : current counter value (counts down to 0)
//   0x04  TIMER_LOAD   RW  : reload value
//   0x08  TIMER_CTRL   RW  : [0]=EN  [1]=AUTO_RELOAD  [2]=IRQ_EN
//   0x0C  TIMER_STATUS RW1C: [0]=EXPIRED  (write 1 to clear)
//
// Behaviour:
//   - When EN=1 the counter decrements by 1 each clock cycle.
//   - When the counter reaches 0 and AUTO_RELOAD=1 it reloads from TIMER_LOAD
//     and sets EXPIRED.
//   - When AUTO_RELOAD=0 the counter stops at 0 and sets EXPIRED.
//   - EXPIRED is cleared by writing 1 to STATUS[0].
//   - timer_irq is asserted while EXPIRED && IRQ_EN.
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module timer #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
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

    // Interrupt output
    output wire                    timer_irq
);

    // =========================================================================
    // Registers
    // =========================================================================
    reg [31:0] count_r;
    reg [31:0] load_r;
    reg        en_r;
    reg        auto_reload_r;
    reg        irq_en_r;
    reg        expired_r;

    assign timer_irq = expired_r & irq_en_r;

    // =========================================================================
    // Counter logic
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            count_r   <= 32'd0;
            expired_r <= 1'b0;
        end else begin
            if (en_r) begin
                if (count_r == 32'd0) begin
                    expired_r <= 1'b1;
                    if (auto_reload_r)
                        count_r <= load_r;
                    // else stays at 0 and timer stalls
                end else begin
                    count_r <= count_r - 1'b1;
                end
            end
            // expired_r cleared by AXI write (handled in write path below)
        end
    end

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

    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            aw_pend       <= 1'b0;
            aw_addr_lat   <= {ADDR_WIDTH{1'b0}};
            load_r        <= 32'hFFFF_FFFF;
            en_r          <= 1'b0;
            auto_reload_r <= 1'b0;
            irq_en_r      <= 1'b0;
        end else begin
            if (aw_fire && w_fire) begin
                case (cur_wr_off)
                    8'h04: begin  // TIMER_LOAD
                        if (cur_wstrb[0]) load_r[ 7: 0] <= cur_wdata[ 7: 0];
                        if (cur_wstrb[1]) load_r[15: 8] <= cur_wdata[15: 8];
                        if (cur_wstrb[2]) load_r[23:16] <= cur_wdata[23:16];
                        if (cur_wstrb[3]) load_r[31:24] <= cur_wdata[31:24];
                        count_r <= cur_wdata;
                    end
                    8'h08: begin  // TIMER_CTRL
                        if (cur_wstrb[0]) begin
                            en_r          <= cur_wdata[0];
                            auto_reload_r <= cur_wdata[1];
                            irq_en_r      <= cur_wdata[2];
                        end
                    end
                    8'h0C: begin  // TIMER_STATUS – W1C
                        if (cur_wstrb[0] && cur_wdata[0])
                            expired_r <= 1'b0;
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
                    8'h04: begin  // TIMER_LOAD
                        if (cur_wstrb[0]) load_r[ 7: 0] <= cur_wdata[ 7: 0];
                        if (cur_wstrb[1]) load_r[15: 8] <= cur_wdata[15: 8];
                        if (cur_wstrb[2]) load_r[23:16] <= cur_wdata[23:16];
                        if (cur_wstrb[3]) load_r[31:24] <= cur_wdata[31:24];
                        count_r <= cur_wdata;
                    end
                    8'h08: begin  // TIMER_CTRL
                        if (cur_wstrb[0]) begin
                            en_r          <= cur_wdata[0];
                            auto_reload_r <= cur_wdata[1];
                            irq_en_r      <= cur_wdata[2];
                        end
                    end
                    8'h0C: begin  // TIMER_STATUS – W1C
                        if (cur_wstrb[0] && cur_wdata[0])
                            expired_r <= 1'b0;
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

    // =========================================================================
    // AXI4-Lite slave – read path
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                case (s_axi_araddr[7:0])
                    8'h00: s_axi_rdata <= count_r;
                    8'h04: s_axi_rdata <= load_r;
                    8'h08: s_axi_rdata <= {29'd0, irq_en_r, auto_reload_r, en_r};
                    8'h0C: s_axi_rdata <= {31'd0, expired_r};
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
