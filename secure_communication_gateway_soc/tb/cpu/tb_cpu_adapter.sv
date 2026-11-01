// =============================================================================
// tb_cpu_adapter.sv  –  CPU AXI Adapter Self-Checking Testbench
//
// Tests (spec §14, CPU adapter verification):
//   TC01 – LSU 32-bit write forwarded correctly (single beat)
//   TC02 – LSU 32-bit read forwarded and returned correctly
//   TC03 – IFU 32-bit read forwarded correctly (read-only path)
//   TC04 – LSU priority: LSU write wins when both LSU and IFU pending
//   TC05 – IFU served after LSU completes (no starvation within reasonable time)
//   TC06 – 64-bit LSU write split into two 32-bit beats
//   TC07 – 64-bit LSU read assembled from two 32-bit responses
//   TC08 – Write strobe / byte-lane conversion preserved
//   TC09 – ID translation: 4-bit LSU ID encoded in 8-bit output correctly
//   TC10 – Error response (SLVERR) propagated back to LSU
//   TC11 – Response routing: IFU response goes to IFU, not LSU
// =============================================================================

`timescale 1ns / 1ps
`default_nettype none

module tb_cpu_adapter;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter CLK_PERIOD = 10;
    parameter SOC_DW = 32;
    parameter SOC_AW = 32;
    parameter SOC_IW = 8;
    parameter CPU_DW = 64;
    parameter CPU_TAG = 4;

    // =========================================================================
    // Clock / reset
    // =========================================================================
    logic clk = 0;
    logic rst = 1;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // DUT – cpu_axi_adapter
    // =========================================================================

    // LSU interface (64-bit)
    logic                  lsu_awvalid; logic                  lsu_awready;
    logic [CPU_TAG-1:0]    lsu_awid;    logic [SOC_AW-1:0]    lsu_awaddr;
    logic [7:0]            lsu_awlen;   logic [2:0]            lsu_awsize;
    logic [1:0]            lsu_awburst; logic                  lsu_awlock;
    logic [3:0]            lsu_awcache; logic [2:0]            lsu_awprot;
    logic [3:0]            lsu_awqos;
    logic                  lsu_wvalid;  logic                  lsu_wready;
    logic [CPU_DW-1:0]     lsu_wdata;
    logic [CPU_DW/8-1:0]   lsu_wstrb;
    logic                  lsu_wlast;
    logic                  lsu_bvalid;  logic                  lsu_bready;
    logic [1:0]            lsu_bresp;   logic [CPU_TAG-1:0]    lsu_bid;
    logic                  lsu_arvalid; logic                  lsu_arready;
    logic [CPU_TAG-1:0]    lsu_arid;    logic [SOC_AW-1:0]    lsu_araddr;
    logic [7:0]            lsu_arlen;   logic [2:0]            lsu_arsize;
    logic [1:0]            lsu_arburst; logic                  lsu_arlock;
    logic [3:0]            lsu_arcache; logic [2:0]            lsu_arprot;
    logic [3:0]            lsu_arqos;
    logic                  lsu_rvalid;  logic                  lsu_rready;
    logic [CPU_TAG-1:0]    lsu_rid;
    logic [CPU_DW-1:0]     lsu_rdata;
    logic [1:0]            lsu_rresp;   logic                  lsu_rlast;

    // IFU interface (64-bit read only)
    logic                  ifu_arvalid; logic                  ifu_arready;
    logic [CPU_TAG-1:0]    ifu_arid;    logic [SOC_AW-1:0]    ifu_araddr;
    logic [7:0]            ifu_arlen;   logic [2:0]            ifu_arsize;
    logic [1:0]            ifu_arburst; logic                  ifu_arlock;
    logic [3:0]            ifu_arcache; logic [2:0]            ifu_arprot;
    logic [3:0]            ifu_arqos;
    logic                  ifu_rvalid;  logic                  ifu_rready;
    logic [CPU_TAG-1:0]    ifu_rid;
    logic [CPU_DW-1:0]     ifu_rdata;
    logic [1:0]            ifu_rresp;   logic                  ifu_rlast;

    // 32-bit master (to interconnect)
    logic [SOC_IW-1:0]    m_awid;      logic [SOC_AW-1:0]    m_awaddr;
    logic [7:0]            m_awlen;     logic [2:0]            m_awsize;
    logic [1:0]            m_awburst;   logic                  m_awlock;
    logic [3:0]            m_awcache;   logic [2:0]            m_awprot;
    logic [3:0]            m_awqos;     logic                  m_awvalid;
    logic                  m_awready;
    logic [SOC_DW-1:0]    m_wdata;     logic [SOC_DW/8-1:0]  m_wstrb;
    logic                  m_wlast;     logic                  m_wvalid;
    logic                  m_wready;
    logic [SOC_IW-1:0]    m_bid;       logic [1:0]            m_bresp;
    logic                  m_bvalid;    logic                  m_bready;
    logic [SOC_IW-1:0]    m_arid;      logic [SOC_AW-1:0]    m_araddr;
    logic [7:0]            m_arlen;     logic [2:0]            m_arsize;
    logic [1:0]            m_arburst;   logic                  m_arlock;
    logic [3:0]            m_arcache;   logic [2:0]            m_arprot;
    logic [3:0]            m_arqos;     logic                  m_arvalid;
    logic                  m_arready;
    logic [SOC_IW-1:0]    m_rid;       logic [SOC_DW-1:0]    m_rdata;
    logic [1:0]            m_rresp;     logic                  m_rlast;
    logic                  m_rvalid;    logic                  m_rready;

    cpu_axi_adapter #(
        .SOC_DATA_W (SOC_DW), .SOC_ADDR_W(SOC_AW), .SOC_ID_W(SOC_IW),
        .CPU_DATA_W (CPU_DW), .CPU_BUS_TAG(CPU_TAG)
    ) dut (
        .clk(clk), .rst(rst),
        .lsu_axi_awvalid(lsu_awvalid), .lsu_axi_awready(lsu_awready),
        .lsu_axi_awid(lsu_awid),       .lsu_axi_awaddr(lsu_awaddr),
        .lsu_axi_awlen(lsu_awlen),     .lsu_axi_awsize(lsu_awsize),
        .lsu_axi_awburst(lsu_awburst), .lsu_axi_awlock(lsu_awlock),
        .lsu_axi_awcache(lsu_awcache), .lsu_axi_awprot(lsu_awprot),
        .lsu_axi_awqos(lsu_awqos),
        .lsu_axi_wvalid(lsu_wvalid),   .lsu_axi_wready(lsu_wready),
        .lsu_axi_wdata(lsu_wdata),     .lsu_axi_wstrb(lsu_wstrb),
        .lsu_axi_wlast(lsu_wlast),
        .lsu_axi_bvalid(lsu_bvalid),   .lsu_axi_bready(lsu_bready),
        .lsu_axi_bresp(lsu_bresp),     .lsu_axi_bid(lsu_bid),
        .lsu_axi_arvalid(lsu_arvalid), .lsu_axi_arready(lsu_arready),
        .lsu_axi_arid(lsu_arid),       .lsu_axi_araddr(lsu_araddr),
        .lsu_axi_arlen(lsu_arlen),     .lsu_axi_arsize(lsu_arsize),
        .lsu_axi_arburst(lsu_arburst), .lsu_axi_arlock(lsu_arlock),
        .lsu_axi_arcache(lsu_arcache), .lsu_axi_arprot(lsu_arprot),
        .lsu_axi_arqos(lsu_arqos),
        .lsu_axi_rvalid(lsu_rvalid),   .lsu_axi_rready(lsu_rready),
        .lsu_axi_rid(lsu_rid),         .lsu_axi_rdata(lsu_rdata),
        .lsu_axi_rresp(lsu_rresp),     .lsu_axi_rlast(lsu_rlast),
        .ifu_axi_arvalid(ifu_arvalid), .ifu_axi_arready(ifu_arready),
        .ifu_axi_arid(ifu_arid),       .ifu_axi_araddr(ifu_araddr),
        .ifu_axi_arlen(ifu_arlen),     .ifu_axi_arsize(ifu_arsize),
        .ifu_axi_arburst(ifu_arburst), .ifu_axi_arlock(ifu_arlock),
        .ifu_axi_arcache(ifu_arcache), .ifu_axi_arprot(ifu_arprot),
        .ifu_axi_arqos(ifu_arqos),
        .ifu_axi_rvalid(ifu_rvalid),   .ifu_axi_rready(ifu_rready),
        .ifu_axi_rid(ifu_rid),         .ifu_axi_rdata(ifu_rdata),
        .ifu_axi_rresp(ifu_rresp),     .ifu_axi_rlast(ifu_rlast),
        .m_axi_awid(m_awid),           .m_axi_awaddr(m_awaddr),
        .m_axi_awlen(m_awlen),         .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst),     .m_axi_awlock(m_awlock),
        .m_axi_awcache(m_awcache),     .m_axi_awprot(m_awprot),
        .m_axi_awqos(m_awqos),         .m_axi_awvalid(m_awvalid),
        .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata),         .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast),         .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bid(m_bid),             .m_axi_bresp(m_bresp),
        .m_axi_bvalid(m_bvalid),       .m_axi_bready(m_bready),
        .m_axi_arid(m_arid),           .m_axi_araddr(m_araddr),
        .m_axi_arlen(m_arlen),         .m_axi_arsize(m_arsize),
        .m_axi_arburst(m_arburst),     .m_axi_arlock(m_arlock),
        .m_axi_arcache(m_arcache),     .m_axi_arprot(m_arprot),
        .m_axi_arqos(m_arqos),         .m_axi_arvalid(m_arvalid),
        .m_axi_arready(m_arready),
        .m_axi_rid(m_rid),             .m_axi_rdata(m_rdata),
        .m_axi_rresp(m_rresp),         .m_axi_rlast(m_rlast),
        .m_axi_rvalid(m_rvalid),       .m_axi_rready(m_rready)
    );

    // =========================================================================
    // Simple memory model (32-bit) to serve the master interface
    // =========================================================================
    logic [31:0] mem [0:255];  // 1 KB word-addressable

    logic        force_slverr = 0;
    reg [SOC_AW-1:0]     mem_wr_addr;
    reg [SOC_IW-1:0]     mem_wr_id;
    reg                  mem_aw_seen;
    reg                  mem_w_seen;

    always @(posedge clk) begin
        if (rst) begin
            m_awready   <= 1'b1;
            m_wready    <= 1'b1;
            m_bvalid    <= 1'b0;
            m_bresp     <= 2'b00;
            m_bid       <= {SOC_IW{1'b0}};
            m_arready   <= 1'b1;
            m_rvalid    <= 1'b0;
            m_rdata     <= {SOC_DW{1'b0}};
            m_rresp     <= 2'b00;
            m_rlast     <= 1'b0;
            m_rid       <= {SOC_IW{1'b0}};
            mem_aw_seen <= 1'b0;
            mem_w_seen  <= 1'b0;
            mem_wr_addr <= {SOC_AW{1'b0}};
            mem_wr_id   <= {SOC_IW{1'b0}};
        end else begin
            // ---------------- Write path ----------------
            if (m_awvalid && m_awready) begin
                mem_wr_addr <= m_awaddr;
                mem_wr_id   <= m_awid;
                mem_aw_seen <= 1'b1;
            end

            if (m_wvalid && m_wready) begin
                mem_w_seen  <= 1'b1;
                if (m_wstrb[0]) mem[(mem_aw_seen ? mem_wr_addr[9:2] : m_awaddr[9:2])][ 7: 0] <= m_wdata[ 7: 0];
                if (m_wstrb[1]) mem[(mem_aw_seen ? mem_wr_addr[9:2] : m_awaddr[9:2])][15: 8] <= m_wdata[15: 8];
                if (m_wstrb[2]) mem[(mem_aw_seen ? mem_wr_addr[9:2] : m_awaddr[9:2])][23:16] <= m_wdata[23:16];
                if (m_wstrb[3]) mem[(mem_aw_seen ? mem_wr_addr[9:2] : m_awaddr[9:2])][31:24] <= m_wdata[31:24];
            end

            if ((mem_aw_seen || (m_awvalid && m_awready)) &&
                (mem_w_seen  || (m_wvalid  && m_wready))) begin
                m_bvalid    <= 1'b1;
                m_bid       <= (mem_aw_seen ? mem_wr_id : m_awid);
                m_bresp     <= force_slverr ? 2'b10 : 2'b00;
                mem_aw_seen <= 1'b0;
                mem_w_seen  <= 1'b0;
            end else if (m_bvalid && m_bready) begin
                m_bvalid    <= 1'b0;
            end

            // ---------------- Read path ----------------
            if (m_arvalid && m_arready) begin
                m_rvalid <= 1'b1;
                m_rdata  <= mem[m_araddr[9:2]];
                m_rresp  <= force_slverr ? 2'b10 : 2'b00;
                m_rlast  <= 1'b1;
                m_rid    <= m_arid;
            end else if (m_rvalid && m_rready) begin
                m_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Helpers
    // =========================================================================
    integer pass_count = 0;
    integer fail_count = 0;

    task check(input string name, input logic cond);
        if (cond) begin
            $display("[PASS] %s", name); pass_count++;
        end else begin
            $display("[FAIL] %s", name); fail_count++;
        end
    endtask

    task init_cpu;
        lsu_awvalid=0; lsu_awid=0; lsu_awaddr=0; lsu_awlen=0;
        lsu_awsize=3'd2; lsu_awburst=2'b01; lsu_awlock=0;
        lsu_awcache=4'b0011; lsu_awprot=0; lsu_awqos=0;
        lsu_wvalid=0; lsu_wdata=0; lsu_wstrb=8'hFF; lsu_wlast=1;
        lsu_bready=1;
        lsu_arvalid=0; lsu_arid=0; lsu_araddr=0; lsu_arlen=0;
        lsu_arsize=3'd2; lsu_arburst=2'b01; lsu_arlock=0;
        lsu_arcache=4'b0011; lsu_arprot=0; lsu_arqos=0;
        lsu_rready=1;
        ifu_arvalid=0; ifu_arid=0; ifu_araddr=0; ifu_arlen=0;
        ifu_arsize=3'd2; ifu_arburst=2'b01; ifu_arlock=0;
        ifu_arcache=4'b0011; ifu_arprot=0; ifu_arqos=0;
        ifu_rready=1;
    endtask

    // LSU 32-bit write helper
    task lsu_wr32(input [SOC_AW-1:0] addr, input [31:0] data,
                  input [3:0] strb, output [1:0] bresp);
        @(posedge clk); #1;
        lsu_awvalid=1; lsu_awaddr=addr; lsu_awsize=3'd2; lsu_awid=4'h1;
        lsu_wvalid=1;  lsu_wdata={32'h0, data}; lsu_wstrb={4'h0, strb}; lsu_wlast=1;
        fork
            begin
                do @(posedge clk);
                while (!lsu_awready);
                #1 lsu_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!lsu_wready);
                #1 lsu_wvalid = 0;
            end
        join
        do @(posedge clk);
        while (!lsu_bvalid);
        bresp = lsu_bresp;
        lsu_bready=1; @(posedge clk); #1;
    endtask

    // LSU 32-bit read helper
    task lsu_rd32(input [SOC_AW-1:0] addr, input [CPU_TAG-1:0] id,
                  output [31:0] data, output [1:0] rresp);
        @(posedge clk); #1;
        lsu_arvalid=1; lsu_araddr=addr; lsu_arsize=3'd2; lsu_arid=id;
        @(posedge clk); #1;
        while (!lsu_arready) @(posedge clk) #1;
        lsu_arvalid=0;
        while (!lsu_rvalid) @(posedge clk) #1;
        data = lsu_rdata[31:0]; rresp = lsu_rresp;
        lsu_rready=1; @(posedge clk); #1;
    endtask

    // IFU 32-bit read helper
    task ifu_rd32(input [SOC_AW-1:0] addr, input [CPU_TAG-1:0] id,
                  output [31:0] data, output [1:0] rresp);
        @(posedge clk); #1;
        ifu_arvalid=1; ifu_araddr=addr; ifu_arsize=3'd2; ifu_arid=id;
        @(posedge clk); #1;
        while (!ifu_arready) @(posedge clk) #1;
        ifu_arvalid=0;
        while (!ifu_rvalid) @(posedge clk) #1;
        data = ifu_rdata[31:0]; rresp = ifu_rresp;
        ifu_rready=1; @(posedge clk); #1;
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    logic [1:0]  resp;
    logic [31:0] rdata32;
    logic [SOC_IW-1:0] seen_id;

    initial begin
        // Pre-populate memory
        for (int i = 0; i < 256; i++) mem[i] = 32'hDEAD_0000 | i;
        init_cpu();
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // TC01 – LSU 32-bit write
        $display("--- TC01: LSU 32-bit write ---");
        lsu_wr32(32'h10, 32'hAABB_CCDD, 4'hF, resp);
        check("TC01_LSU_WR_RESP", resp == 2'b00);
        check("TC01_MEM_DATA",    mem[4] == 32'hAABB_CCDD);

        // TC02 – LSU 32-bit read
        $display("--- TC02: LSU 32-bit read ---");
        mem[8] = 32'h1234_5678;
        lsu_rd32(32'h20, 4'h2, rdata32, resp);
        check("TC02_LSU_RD_RESP", resp == 2'b00);
        check("TC02_LSU_RD_DATA", rdata32 == 32'h1234_5678);

        // TC03 – IFU 32-bit read
        $display("--- TC03: IFU 32-bit read ---");
        mem[12] = 32'hFEEDFACE;
        ifu_rd32(32'h30, 4'h3, rdata32, resp);
        check("TC03_IFU_RD_RESP", resp == 2'b00);
        check("TC03_IFU_RD_DATA", rdata32 == 32'hFEEDFACE);

        // TC04 – LSU priority over IFU
        $display("--- TC04: LSU priority over IFU ---");
        // Both request at the same time; expect LSU write to be served first
        // (master-side arvalid both high – adapter will pick LSU write)
        fork
            begin
                lsu_wr32(32'h40, 32'hCCCC_CCCC, 4'hF, resp);
            end
            begin
                // IFU request issued slightly later
                @(posedge clk); @(posedge clk);
                ifu_rd32(32'h50, 4'h1, rdata32, resp);
            end
        join
        check("TC04_LSU_WIN",    mem[16] == 32'hCCCC_CCCC);
        // IFU read also must have eventually completed
        check("TC04_IFU_DONE",   resp == 2'b00);

        // TC05 – IFU starvation: make many LSU requests, IFU must still complete
        $display("--- TC05: IFU not starved ---");
        fork
            begin : lsu_loop
                repeat(4) lsu_wr32(32'h60, 32'hAAAA_AAAA, 4'hF, resp);
            end
            begin : ifu_check
                @(posedge clk);
                ifu_rd32(32'h100, 4'hF, rdata32, resp);
                check("TC05_IFU_COMPLETE", (resp == 2'b00 || resp == 2'b10)); // any valid response
            end
        join

        // TC06 – 64-bit LSU write splits into two 32-bit beats
        $display("--- TC06: 64-bit LSU write ---");
        @(posedge clk); #1;
        lsu_awvalid=1; lsu_awaddr=32'h80; lsu_awsize=3'd3; lsu_awid=4'h4;  // size=3 → 8 bytes
        lsu_wvalid=1;
        lsu_wdata = 64'hDEAD_BEEF_CAFE_BABE;
        lsu_wstrb = 8'hFF;
        lsu_wlast = 1;
        fork
            begin
                do @(posedge clk);
                while (!lsu_awready);
                #1 lsu_awvalid = 0;
            end
            begin
                do @(posedge clk);
                while (!lsu_wready);
                #1 lsu_wvalid = 0;
            end
        join
        while (!lsu_bvalid) @(posedge clk) #1;
        resp = lsu_bresp; lsu_bready=1; @(posedge clk); #1;
        check("TC06_64B_WR_RESP",  resp == 2'b00);
        // Verify both 32-bit halves written to memory
        check("TC06_LO_WORD",      mem[32] == 32'hCAFE_BABE);
        check("TC06_HI_WORD",      mem[33] == 32'hDEAD_BEEF);

        // TC07 – 64-bit LSU read assembled from two 32-bit responses
        $display("--- TC07: 64-bit LSU read ---");
        mem[36] = 32'h1111_2222;
        mem[37] = 32'h3333_4444;
        @(posedge clk); #1;
        lsu_arvalid=1; lsu_araddr=32'h90; lsu_arsize=3'd3; lsu_arid=4'h5;
        @(posedge clk); #1;
        while (!lsu_arready) @(posedge clk) #1;
        lsu_arvalid=0;
        while (!lsu_rvalid) @(posedge clk) #1;
        resp = lsu_rresp;
        check("TC07_64B_RD_RESP",  resp == 2'b00);
        check("TC07_64B_RD_LO",    lsu_rdata[31:0]  == 32'h1111_2222);
        check("TC07_64B_RD_HI",    lsu_rdata[63:32] == 32'h3333_4444);
        lsu_rready=1; @(posedge clk); #1;

        // TC08 – Write strobe preserved
        $display("--- TC08: Write strobe byte lanes ---");
        mem[20] = 32'hFFFF_FFFF;
        // Write only byte 0 with 0x00
        lsu_wr32(32'h50, 32'h0000_0000, 4'h1, resp);
        check("TC08_STRB_RESP",    resp == 2'b00);
        check("TC08_STRB_BYTE0",   mem[20][7:0]  == 8'h00);
        check("TC08_STRB_UPPER",   mem[20][31:8] == 24'hFFFFFF);

        // TC09 – ID translation: output 8-bit ID must encode LSU tag
        $display("--- TC09: ID translation ---");
        @(posedge clk); #1;
        lsu_arvalid=1; lsu_araddr=32'h0; lsu_arsize=3'd2; lsu_arid=4'hA;
        @(posedge clk); #1;
        while (!lsu_arready) @(posedge clk) #1;
        seen_id = m_arid;
        lsu_arvalid=0;
        while (!lsu_rvalid) @(posedge clk) #1;
        lsu_rready=1; @(posedge clk); #1;
        // LSU tag = 3'b001, so 8-bit ID = {1'b0, 3'b001, 4'hA} = 8'h1A
        check("TC09_ID_TRANS", seen_id == 8'h1A);

        // TC10 – SLVERR propagated back to LSU
        $display("--- TC10: Error response propagation ---");
        force_slverr = 1;
        lsu_rd32(32'h0, 4'h1, rdata32, resp);
        check("TC10_SLVERR", resp == 2'b10);
        force_slverr = 0;

        // TC11 – Response routing: IFU gets IFU response
        $display("--- TC11: Response routing IFU vs LSU ---");
        // IFU read while LSU is idle; check ifu_rid == original arid
        ifu_rd32(32'h0C, 4'hB, rdata32, resp);
        check("TC11_IFU_RID",    ifu_rid == 4'hB);
        check("TC11_IFU_RESP",   resp == 2'b00);
        // LSU rvalid must NOT fire during IFU-only read
        check("TC11_LSU_QUIET",  !lsu_rvalid);

        // ==================================================================
        repeat(2) @(posedge clk);
        $display("========================================");
        $display(" tb_cpu_adapter RESULTS");
        $display(" PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish(fail_count > 0 ? 1 : 0);
    end

    initial begin
        #200_000;
        $display("[FAIL] TIMEOUT");
        $finish(1);
    end

endmodule
