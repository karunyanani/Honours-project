// =============================================================================
// gpio.v  –  General-Purpose I/O with DRDY synchronizer, edge detect, and IRQ
//
// Spec refs:
//   - Section 4 : M4, base 0x10000200, 256 B
//   - Section 5 : CPU only (DMA denied in interconnect)
//   - Section 8 : Asynchronous DRDY passes through 2-FF synchronizer;
//                 registered edge detector generates IRQ-pending flag;
//                 CPU clears pending via register write.
//
// Register map (byte offsets):
//   0x00  GPIO_DATA_OUT  RW  : output data register (8 GPIO outputs)
//   0x04  GPIO_DATA_IN   R   : sampled input data register
//   0x08  GPIO_DIR       RW  : direction per pin (1=output, 0=input)
//   0x0C  GPIO_IRQ_EN    RW  : interrupt enable per pin
//   0x10  GPIO_IRQ_PEND  R/W1C : pending interrupt flags
//   0x14  GPIO_IRQ_EDGE  RW  : edge select per pin (0=falling, 1=rising)
//
// GPIO port is 8 bits wide.  DRDY is expected on gpio_in[0].
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module gpio #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter GPIO_WIDTH  = 8
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

    // GPIO pads
    input  wire [GPIO_WIDTH-1:0]   gpio_in,      // async inputs (DRDY on [0])
    output wire [GPIO_WIDTH-1:0]   gpio_out,     // registered outputs
    output wire [GPIO_WIDTH-1:0]   gpio_oe,      // output enable (1=drive)

    // Interrupt
    output wire                    gpio_irq
);

    // =========================================================================
    // Registers
    // =========================================================================
    reg [GPIO_WIDTH-1:0] data_out_r;
    reg [GPIO_WIDTH-1:0] dir_r;       // 1 = output
    reg [GPIO_WIDTH-1:0] irq_en_r;
    reg [GPIO_WIDTH-1:0] irq_pend_r;
    reg [GPIO_WIDTH-1:0] irq_edge_r;  // 0=falling 1=rising

    assign gpio_out = data_out_r;
    assign gpio_oe  = dir_r;
    assign gpio_irq = |(irq_pend_r & irq_en_r);

    // =========================================================================
    // 2-FF synchronizer for all async inputs
    // =========================================================================
    reg [GPIO_WIDTH-1:0] sync_ff1;
    reg [GPIO_WIDTH-1:0] sync_ff2;
    reg [GPIO_WIDTH-1:0] sync_prev;   // previous cycle, for edge detect

    always @(posedge clk) begin
        if (rst) begin
            sync_ff1  <= {GPIO_WIDTH{1'b0}};
            sync_ff2  <= {GPIO_WIDTH{1'b0}};
            sync_prev <= {GPIO_WIDTH{1'b0}};
        end else begin
            sync_ff1  <= gpio_in;
            sync_ff2  <= sync_ff1;
            sync_prev <= sync_ff2;
        end
    end

    // =========================================================================
    // Edge detector  (registered, fires one cycle after edge)
    // =========================================================================
    wire [GPIO_WIDTH-1:0] rising_edge  =  sync_ff2 & ~sync_prev;
    wire [GPIO_WIDTH-1:0] falling_edge = ~sync_ff2 &  sync_prev;

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

    wire irq_pend_clr = wr_fire && (cur_wr_off == 8'h10) && cur_wstrb[0];

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            irq_pend_r <= {GPIO_WIDTH{1'b0}};
        end else begin
            for (i = 0; i < GPIO_WIDTH; i = i + 1) begin
                if (irq_edge_r[i] ? rising_edge[i] : falling_edge[i])
                    irq_pend_r[i] <= 1'b1;
                else if (irq_pend_clr && cur_wdata[i])
                    irq_pend_r[i] <= 1'b0;
            end
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
            data_out_r    <= {GPIO_WIDTH{1'b0}};
            dir_r         <= {GPIO_WIDTH{1'b0}};
            irq_en_r      <= {GPIO_WIDTH{1'b0}};
            irq_edge_r    <= {GPIO_WIDTH{1'b0}};
        end else begin
            if (aw_fire && w_fire) begin
                case (cur_wr_off)
                    8'h00: if (cur_wstrb[0]) data_out_r <= cur_wdata[GPIO_WIDTH-1:0];
                    8'h08: if (cur_wstrb[0]) dir_r      <= cur_wdata[GPIO_WIDTH-1:0];
                    8'h0C: if (cur_wstrb[0]) irq_en_r   <= cur_wdata[GPIO_WIDTH-1:0];
                    8'h10: ;  // Handled in irq_pend_r block
                    8'h14: if (cur_wstrb[0]) irq_edge_r <= cur_wdata[GPIO_WIDTH-1:0];
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
                    8'h00: if (cur_wstrb[0]) data_out_r <= cur_wdata[GPIO_WIDTH-1:0];
                    8'h08: if (cur_wstrb[0]) dir_r      <= cur_wdata[GPIO_WIDTH-1:0];
                    8'h0C: if (cur_wstrb[0]) irq_en_r   <= cur_wdata[GPIO_WIDTH-1:0];
                    8'h10: ;  // Handled in irq_pend_r block
                    8'h14: if (cur_wstrb[0]) irq_edge_r <= cur_wdata[GPIO_WIDTH-1:0];
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
                    8'h00: s_axi_rdata <= {{(32-GPIO_WIDTH){1'b0}}, data_out_r};
                    8'h04: s_axi_rdata <= {{(32-GPIO_WIDTH){1'b0}}, sync_ff2};
                    8'h08: s_axi_rdata <= {{(32-GPIO_WIDTH){1'b0}}, dir_r};
                    8'h0C: s_axi_rdata <= {{(32-GPIO_WIDTH){1'b0}}, irq_en_r};
                    8'h10: s_axi_rdata <= {{(32-GPIO_WIDTH){1'b0}}, irq_pend_r};
                    8'h14: s_axi_rdata <= {{(32-GPIO_WIDTH){1'b0}}, irq_edge_r};
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
