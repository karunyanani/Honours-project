// =============================================================================
// File: axi_assertions.sv
// Description: Protocol Assertions Checker for AXI4 Bus Compliance
// Compatible with both Synopsys VCS SVA and Open-Source Simulators (Icarus / Verilator)
// Checks:
//   1. Handshake Stability (VALID cannot drop until READY)
//   2. Legal BRESP / RRESP response encoding (OKAY, EXOKAY, SLVERR, DECERR)
// =============================================================================

`ifndef AXI_ASSERTIONS_SV
`define AXI_ASSERTIONS_SV

module axi_assertions (
    input wire clk,
    input wire rst,

    // AW
    input wire [31:0] awaddr,
    input wire        awvalid,
    input wire        awready,

    // W
    input wire [31:0] wdata,
    input wire [3:0]  wstrb,
    input wire        wvalid,
    input wire        wready,

    // B
    input wire [1:0]  bresp,
    input wire        bvalid,
    input wire        bready,

    // AR
    input wire [31:0] araddr,
    input wire        arvalid,
    input wire        arready,

    // R
    input wire [31:0] rdata,
    input wire [1:0]  rresp,
    input wire        rvalid,
    input wire        rready
);

    // Procedural Protocol Checkers (Universally supported across all tools)
    reg prev_awvalid, prev_wvalid, prev_arvalid;

    always @(posedge clk) begin
        if (!rst) begin
            // Handshake hold checks
            if (prev_awvalid && !awready && !awvalid) begin
                $error("[AXI_ASSERT_ERR] AWVALID dropped before AWREADY handshake!");
            end
            if (prev_wvalid && !wready && !wvalid) begin
                $error("[AXI_ASSERT_ERR] WVALID dropped before WREADY handshake!");
            end
            if (prev_arvalid && !arready && !arvalid) begin
                $error("[AXI_ASSERT_ERR] ARVALID dropped before ARREADY handshake!");
            end

            // Response code legality
            if (bvalid && (bresp !== 2'b00 && bresp !== 2'b01 && bresp !== 2'b10 && bresp !== 2'b11)) begin
                $error("[AXI_ASSERT_ERR] Illegal BRESP value observed!");
            end
            if (rvalid && (rresp !== 2'b00 && rresp !== 2'b01 && rresp !== 2'b10 && rresp !== 2'b11)) begin
                $error("[AXI_ASSERT_ERR] Illegal RRESP value observed!");
            end

            prev_awvalid <= awvalid;
            prev_wvalid  <= wvalid;
            prev_arvalid <= arvalid;
        end else begin
            prev_awvalid <= 1'b0;
            prev_wvalid  <= 1'b0;
            prev_arvalid <= 1'b0;
        end
    end

`ifdef VCS
    // Concurrent SVA Properties for Synopsys VCS & Formal Verification
    property p_awvalid_stable;
        @(posedge clk) disable iff (rst)
        awvalid && !awready |=> awvalid;
    endproperty
    assert_awvalid_stable: assert property (p_awvalid_stable);

    property p_wvalid_stable;
        @(posedge clk) disable iff (rst)
        wvalid && !wready |=> wvalid;
    endproperty
    assert_wvalid_stable: assert property (p_wvalid_stable);

    property p_arvalid_stable;
        @(posedge clk) disable iff (rst)
        arvalid && !arready |=> arvalid;
    endproperty
    assert_arvalid_stable: assert property (p_arvalid_stable);
`endif

endmodule : axi_assertions

`endif // AXI_ASSERTIONS_SV
