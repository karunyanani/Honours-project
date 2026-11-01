// =============================================================================
// cpu_axi_adapter.v  –  CPU-side AXI Adapter
//
// Spec refs:
//   - Section 2 req 7 : IFU and LSU interfaces integrated via this adapter
//   - Section 2 req 8 : Exposes ONE logical 32-bit AXI4 master to interconnect
//   - Section 2 req 9 : Data-width conversion, arbitration, ID translation,
//                       and response routing implemented here
//
// Function
// --------
//   VeeR EL2 has two 64-bit AXI masters:
//     IFU – instruction fetch  (read-only, never issues writes)
//     LSU – load/store unit    (reads and writes)
//
//   This adapter converts both to a single 32-bit AXI4 master for the
//   SoC interconnect (S0 port).
//
//   Data-width conversion (64 → 32 bits):
//     Reads:  A 64-bit read from VeeR is split into TWO 32-bit reads on the
//             interconnect.  The appropriate half is muxed back to VeeR based
//             on the low address bit.  For aligned 32-bit accesses (awsize=2)
//             only one beat is needed; for 64-bit accesses two beats are used.
//     Writes: A 64-bit write is split into two 32-bit writes; only the half
//             indicated by the byte-strobe (wstrb[7:4] vs wstrb[3:0]) with
//             non-zero strobes is forwarded.  For sub-word (≤32-bit) writes
//             a single transaction suffices.
//
//   Arbitration (IFU vs LSU):
//     Fixed priority: LSU wins over IFU when both request simultaneously.
//     IFU requests are served only when the LSU is idle.
//     Rationale: data-hazard stalls are more costly than I-fetch bubbles.
//
//   ID translation:
//     IFU IDs  (4-bit)  → 8-bit with bit[7]=0, bit[6:4]=3'b000 (IFU tag)
//     LSU IDs  (4-bit)  → 8-bit with bit[7]=0, bit[6:4]=3'b001 (LSU tag)
//     Response routing: bit[6:4] of returned BID/RID identifies the source.
//
//   Single-beat (AxLEN=0) transactions only, INCR burst type.
//
// RTL: Verilog-2001, synchronous active-high reset (rst).
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module cpu_axi_adapter #(
    parameter SOC_DATA_W  = 32,   // interconnect data width
    parameter SOC_ADDR_W  = 32,
    parameter SOC_ID_W    = 8,
    parameter CPU_DATA_W  = 64,   // VeeR EL2 AXI data width
    parameter CPU_BUS_TAG = 4     // VeeR EL2 ID width (LSU_BUS_TAG = IFU_BUS_TAG = 4)
) (
    input  wire        clk,
    input  wire        rst,    // synchronous active-high

    // =========================================================================
    // LSU AXI4 slave (64-bit, from veer_el2_wrapper)
    // =========================================================================
    input  wire                    lsu_axi_awvalid,
    output reg                     lsu_axi_awready,
    input  wire [CPU_BUS_TAG-1:0]  lsu_axi_awid,
    input  wire [SOC_ADDR_W-1:0]   lsu_axi_awaddr,
    input  wire [7:0]              lsu_axi_awlen,
    input  wire [2:0]              lsu_axi_awsize,
    input  wire [1:0]              lsu_axi_awburst,
    input  wire                    lsu_axi_awlock,
    input  wire [3:0]              lsu_axi_awcache,
    input  wire [2:0]              lsu_axi_awprot,
    input  wire [3:0]              lsu_axi_awqos,
    input  wire                    lsu_axi_wvalid,
    output reg                     lsu_axi_wready,
    input  wire [CPU_DATA_W-1:0]   lsu_axi_wdata,
    input  wire [CPU_DATA_W/8-1:0] lsu_axi_wstrb,
    input  wire                    lsu_axi_wlast,
    output reg                     lsu_axi_bvalid,
    input  wire                    lsu_axi_bready,
    output reg  [1:0]              lsu_axi_bresp,
    output reg  [CPU_BUS_TAG-1:0]  lsu_axi_bid,
    input  wire                    lsu_axi_arvalid,
    output reg                     lsu_axi_arready,
    input  wire [CPU_BUS_TAG-1:0]  lsu_axi_arid,
    input  wire [SOC_ADDR_W-1:0]   lsu_axi_araddr,
    input  wire [7:0]              lsu_axi_arlen,
    input  wire [2:0]              lsu_axi_arsize,
    input  wire [1:0]              lsu_axi_arburst,
    input  wire                    lsu_axi_arlock,
    input  wire [3:0]              lsu_axi_arcache,
    input  wire [2:0]              lsu_axi_arprot,
    input  wire [3:0]              lsu_axi_arqos,
    output reg                     lsu_axi_rvalid,
    input  wire                    lsu_axi_rready,
    output reg  [CPU_BUS_TAG-1:0]  lsu_axi_rid,
    output reg  [CPU_DATA_W-1:0]   lsu_axi_rdata,
    output reg  [1:0]              lsu_axi_rresp,
    output reg                     lsu_axi_rlast,

    // =========================================================================
    // IFU AXI4 slave (64-bit read-only, from veer_el2_wrapper)
    // =========================================================================
    input  wire                    ifu_axi_arvalid,
    output reg                     ifu_axi_arready,
    input  wire [CPU_BUS_TAG-1:0]  ifu_axi_arid,
    input  wire [SOC_ADDR_W-1:0]   ifu_axi_araddr,
    input  wire [7:0]              ifu_axi_arlen,
    input  wire [2:0]              ifu_axi_arsize,
    input  wire [1:0]              ifu_axi_arburst,
    input  wire                    ifu_axi_arlock,
    input  wire [3:0]              ifu_axi_arcache,
    input  wire [2:0]              ifu_axi_arprot,
    input  wire [3:0]              ifu_axi_arqos,
    output reg                     ifu_axi_rvalid,
    input  wire                    ifu_axi_rready,
    output reg  [CPU_BUS_TAG-1:0]  ifu_axi_rid,
    output reg  [CPU_DATA_W-1:0]   ifu_axi_rdata,
    output reg  [1:0]              ifu_axi_rresp,
    output reg                     ifu_axi_rlast,

    // =========================================================================
    // AXI4 master (32-bit, to SoC interconnect S0)
    // =========================================================================
    output reg  [SOC_ID_W-1:0]    m_axi_awid,
    output reg  [SOC_ADDR_W-1:0]  m_axi_awaddr,
    output reg  [7:0]             m_axi_awlen,
    output reg  [2:0]             m_axi_awsize,
    output reg  [1:0]             m_axi_awburst,
    output reg                    m_axi_awlock,
    output reg  [3:0]             m_axi_awcache,
    output reg  [2:0]             m_axi_awprot,
    output reg  [3:0]             m_axi_awqos,
    output reg                    m_axi_awvalid,
    input  wire                   m_axi_awready,
    output reg  [SOC_DATA_W-1:0]  m_axi_wdata,
    output reg  [SOC_DATA_W/8-1:0]m_axi_wstrb,
    output reg                    m_axi_wlast,
    output reg                    m_axi_wvalid,
    input  wire                   m_axi_wready,
    input  wire [SOC_ID_W-1:0]    m_axi_bid,
    input  wire [1:0]             m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output reg                    m_axi_bready,
    output reg  [SOC_ID_W-1:0]   m_axi_arid,
    output reg  [SOC_ADDR_W-1:0]  m_axi_araddr,
    output reg  [7:0]             m_axi_arlen,
    output reg  [2:0]             m_axi_arsize,
    output reg  [1:0]             m_axi_arburst,
    output reg                    m_axi_arlock,
    output reg  [3:0]             m_axi_arcache,
    output reg  [2:0]             m_axi_arprot,
    output reg  [3:0]             m_axi_arqos,
    output reg                    m_axi_arvalid,
    input  wire                   m_axi_arready,
    input  wire [SOC_ID_W-1:0]    m_axi_rid,
    input  wire [SOC_DATA_W-1:0]  m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output reg                    m_axi_rready
);

    // =========================================================================
    // ID tag encoding
    //   Outgoing 8-bit ID: {1'b0, 3'b_tag, 4'b_orig_id}
    //   IFU tag = 3'b000,  LSU tag = 3'b001
    // =========================================================================
    localparam [2:0] TAG_IFU = 3'b000;
    localparam [2:0] TAG_LSU = 3'b001;

    // =========================================================================
    // FSM states
    // =========================================================================
    localparam [3:0]
        S_IDLE       = 4'd0,
        // Write path (LSU only)
        S_WR_AW      = 4'd1,   // issue AW to interconnect
        S_WR_W       = 4'd2,   // issue W data
        S_WR_B       = 4'd3,   // wait for B response
        S_WR_B2      = 4'd4,   // second 32-bit beat (high word, if needed)
        S_WR_W2      = 4'd5,
        S_WR_AW2     = 4'd6,
        // Read path (IFU or LSU)
        S_RD_AR      = 4'd7,   // issue AR to interconnect
        S_RD_R       = 4'd8,   // wait for R data
        S_RD_AR2     = 4'd9,   // second 32-bit beat for 64-bit reads
        S_RD_R2      = 4'd10,
        S_RD_RESP    = 4'd11;  // deliver 64-bit response to CPU

    reg [3:0] state;

    // =========================================================================
    // Captured request fields
    // =========================================================================
    reg                    req_is_ifu;      // 1 = IFU request, 0 = LSU
    reg [CPU_BUS_TAG-1:0]  req_id;
    reg [SOC_ADDR_W-1:0]   req_addr;
    reg [2:0]              req_size;        // original AxSIZE from CPU
    reg [CPU_DATA_W-1:0]   req_wdata;
    reg [CPU_DATA_W/8-1:0] req_wstrb;
    reg                    req_is_64;       // 1 = 64-bit access (size=3)

    // Accumulated read data
    reg [SOC_DATA_W-1:0]   rd_lo;           // data from first  32-bit read (addr[2]=0)
    reg [SOC_DATA_W-1:0]   rd_hi;           // data from second 32-bit read (addr[2]=1)
    reg [1:0]              rd_resp_acc;     // accumulated worst-case response

    // =========================================================================
    // Determine which 32-bit half to present for a ≤32-bit access
    // For VeeR EL2: AXI data is little-endian, addr[2] selects upper/lower word
    // =========================================================================
    wire addr_hi_word = req_addr[2];   // 1 = high 32-bit word of 64-bit bus

    // =========================================================================
    // FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            state            <= S_IDLE;
            // De-assert all master outputs
            m_axi_awvalid    <= 1'b0;
            m_axi_wvalid     <= 1'b0;
            m_axi_bready     <= 1'b0;
            m_axi_arvalid    <= 1'b0;
            m_axi_rready     <= 1'b0;
            // De-assert all CPU-side ready/valid
            lsu_axi_awready  <= 1'b0;
            lsu_axi_wready   <= 1'b0;
            lsu_axi_bvalid   <= 1'b0;
            lsu_axi_arready  <= 1'b0;
            lsu_axi_rvalid   <= 1'b0;
            ifu_axi_arready  <= 1'b0;
            ifu_axi_rvalid   <= 1'b0;
            // Default AXI master fields (fixed for single-beat)
            m_axi_awlen      <= 8'd0;
            m_axi_awsize     <= 3'd2;   // 4 bytes
            m_axi_awburst    <= 2'b01;  // INCR
            m_axi_awlock     <= 1'b0;
            m_axi_awcache    <= 4'b0011;
            m_axi_awprot     <= 3'b000;
            m_axi_awqos      <= 4'd0;
            m_axi_arlen      <= 8'd0;
            m_axi_arsize     <= 3'd2;
            m_axi_arburst    <= 2'b01;
            m_axi_arlock     <= 1'b0;
            m_axi_arcache    <= 4'b0011;
            m_axi_arprot     <= 3'b000;
            m_axi_arqos      <= 4'd0;
            m_axi_wlast      <= 1'b1;
            rd_resp_acc      <= 2'b00;
        end else begin
            // Clear CPU response valids on handshake
            if (lsu_axi_bvalid && lsu_axi_bready) lsu_axi_bvalid <= 1'b0;
            if (lsu_axi_rvalid && lsu_axi_rready) lsu_axi_rvalid <= 1'b0;
            if (ifu_axi_rvalid && ifu_axi_rready) ifu_axi_rvalid <= 1'b0;

            case (state)

                // ==============================================================
                S_IDLE: begin
                    lsu_axi_awready <= 1'b0;
                    lsu_axi_wready  <= 1'b0;
                    lsu_axi_arready <= 1'b0;
                    ifu_axi_arready <= 1'b0;

                    // Arbitration: LSU write takes highest priority,
                    // then LSU read, then IFU read.
                    if (lsu_axi_awvalid && lsu_axi_wvalid) begin
                        // --- LSU WRITE ---
                        lsu_axi_awready <= 1'b1;
                        lsu_axi_wready  <= 1'b1;
                        req_id     <= lsu_axi_awid;
                        req_addr   <= lsu_axi_awaddr;
                        req_size   <= lsu_axi_awsize;
                        req_wdata  <= lsu_axi_wdata;
                        req_wstrb  <= lsu_axi_wstrb;
                        req_is_ifu <= 1'b0;
                        req_is_64  <= (lsu_axi_awsize == 3'd3); // 64-bit write
                        m_axi_awaddr  <= (lsu_axi_awsize == 3'd3) ? {lsu_axi_awaddr[SOC_ADDR_W-1:3], 3'b000} : lsu_axi_awaddr;
                        m_axi_awid    <= {1'b0, TAG_LSU, lsu_axi_awid};
                        m_axi_awsize  <= 3'd2;
                        m_axi_awvalid <= 1'b1;
                        state      <= S_WR_AW;
                    end else if (lsu_axi_arvalid) begin
                        // --- LSU READ ---
                        lsu_axi_arready <= 1'b1;
                        req_id     <= lsu_axi_arid;
                        req_addr   <= lsu_axi_araddr;
                        req_size   <= lsu_axi_arsize;
                        req_is_ifu <= 1'b0;
                        req_is_64  <= (lsu_axi_arsize == 3'd3);
                        rd_resp_acc<= 2'b00;
                        m_axi_araddr  <= (lsu_axi_arsize == 3'd3) ? {lsu_axi_araddr[SOC_ADDR_W-1:3], 3'b000} : lsu_axi_araddr;
                        m_axi_arid    <= {1'b0, TAG_LSU, lsu_axi_arid};
                        m_axi_arsize  <= 3'd2;
                        m_axi_arvalid <= 1'b1;
                        state      <= S_RD_AR;
                    end else if (ifu_axi_arvalid) begin
                        // --- IFU READ ---
                        ifu_axi_arready <= 1'b1;
                        req_id     <= ifu_axi_arid;
                        req_addr   <= ifu_axi_araddr;
                        req_size   <= ifu_axi_arsize;
                        req_is_ifu <= 1'b1;
                        req_is_64  <= (ifu_axi_arsize == 3'd3);
                        rd_resp_acc<= 2'b00;
                        m_axi_araddr  <= (ifu_axi_arsize == 3'd3) ? {ifu_axi_araddr[SOC_ADDR_W-1:3], 3'b000} : ifu_axi_araddr;
                        m_axi_arid    <= {1'b0, TAG_IFU, ifu_axi_arid};
                        m_axi_arsize  <= 3'd2;
                        m_axi_arvalid <= 1'b1;
                        state      <= S_RD_AR;
                    end
                end

                // ==============================================================
                // WRITE PATH
                // ==============================================================

                // Issue AW for lower 32-bit word (or only word for ≤32-bit writes)
                S_WR_AW: begin
                    lsu_axi_awready <= 1'b0;
                    lsu_axi_wready  <= 1'b0;
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata  <= (req_is_64 || (!req_addr[2] && (req_wstrb[7:4] == 4'b0)))
                                        ? req_wdata[31:0] : req_wdata[63:32];
                        m_axi_wstrb  <= (req_is_64 || (!req_addr[2] && (req_wstrb[7:4] == 4'b0)))
                                        ? req_wstrb[3:0]  : req_wstrb[7:4];
                        m_axi_wlast  <= 1'b1;
                        m_axi_wvalid <= 1'b1;
                        state <= S_WR_W;
                    end
                end

                S_WR_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state        <= S_WR_B;
                    end
                end

                S_WR_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        rd_resp_acc  <= m_axi_bresp;
                        if (req_is_64 && (req_wstrb[7:4] != 4'b0)) begin
                            // Issue second beat for upper 32 bits
                            m_axi_awaddr  <= {req_addr[SOC_ADDR_W-1:3], 3'b100};  // hi half
                            m_axi_awid    <= {1'b0, TAG_LSU, req_id};
                            m_axi_awsize  <= 3'd2;
                            m_axi_awvalid <= 1'b1;
                            state <= S_WR_AW2;
                        end else begin
                            // Single-beat write done – respond to LSU
                            lsu_axi_bid    <= req_id;
                            lsu_axi_bresp  <= m_axi_bresp;
                            lsu_axi_bvalid <= 1'b1;
                            state          <= S_IDLE;
                        end
                    end
                end

                S_WR_AW2: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata  <= req_wdata[63:32];
                        m_axi_wstrb  <= req_wstrb[7:4];
                        m_axi_wlast  <= 1'b1;
                        m_axi_wvalid <= 1'b1;
                        state <= S_WR_W2;
                    end
                end

                S_WR_W2: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state        <= S_WR_B2;
                    end
                end

                S_WR_B2: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready   <= 1'b0;
                        // Return worst-case response to LSU
                        lsu_axi_bid    <= req_id;
                        lsu_axi_bresp  <= (m_axi_bresp > rd_resp_acc) ? m_axi_bresp : rd_resp_acc;
                        lsu_axi_bvalid <= 1'b1;
                        state          <= S_IDLE;
                    end
                end

                // ==============================================================
                // READ PATH (shared by IFU and LSU)
                // ==============================================================

                S_RD_AR: begin
                    lsu_axi_arready <= 1'b0;
                    ifu_axi_arready <= 1'b0;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_RD_R;
                    end
                end

                S_RD_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        rd_lo        <= m_axi_rdata;
                        rd_resp_acc  <= m_axi_rresp;
                        if (req_is_64) begin
                            // Need upper 32-bit word too
                            m_axi_araddr  <= {req_addr[SOC_ADDR_W-1:3], 3'b100};
                            m_axi_arid    <= req_is_ifu ? {1'b0, TAG_IFU, req_id}
                                                        : {1'b0, TAG_LSU, req_id};
                            m_axi_arsize  <= 3'd2;
                            m_axi_arvalid <= 1'b1;
                            state <= S_RD_AR2;
                        end else begin
                            state <= S_RD_RESP;
                        end
                    end
                end

                S_RD_AR2: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= S_RD_R2;
                    end
                end

                S_RD_R2: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        m_axi_rready <= 1'b0;
                        rd_hi        <= m_axi_rdata;
                        rd_resp_acc  <= (m_axi_rresp > rd_resp_acc) ? m_axi_rresp : rd_resp_acc;
                        state        <= S_RD_RESP;
                    end
                end

                S_RD_RESP: begin
                    // Deliver read response to the requesting CPU interface
                    // For ≤32-bit accesses: replicate lower word into both halves of 64-bit bus
                    // For 64-bit accesses: assemble {rd_hi, rd_lo}
                    if (req_is_ifu) begin
                        ifu_axi_rid    <= req_id;
                        ifu_axi_rresp  <= rd_resp_acc;
                        ifu_axi_rlast  <= 1'b1;
                        ifu_axi_rdata  <= req_is_64 ? {rd_hi, rd_lo}
                                                    : {rd_lo, rd_lo};
                        ifu_axi_rvalid <= 1'b1;
                        state          <= S_IDLE;
                    end else begin
                        lsu_axi_rid    <= req_id;
                        lsu_axi_rresp  <= rd_resp_acc;
                        lsu_axi_rlast  <= 1'b1;
                        lsu_axi_rdata  <= req_is_64 ? {rd_hi, rd_lo}
                                                    : {rd_lo, rd_lo};
                        lsu_axi_rvalid <= 1'b1;
                        state          <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;

            endcase // state

            // Clear one-cycle accept pulses
            if (state != S_IDLE) begin
                lsu_axi_awready <= 1'b0;
                lsu_axi_wready  <= 1'b0;
                lsu_axi_arready <= 1'b0;
                ifu_axi_arready <= 1'b0;
            end
        end
    end

endmodule

`resetall
