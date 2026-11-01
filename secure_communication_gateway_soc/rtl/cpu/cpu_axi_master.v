// =============================================================================
// cpu_axi_master.v  –  RISC-V CPU AXI4 Master Wrapper Stub
//
// Spec refs:
//   - Section 3  : 32-bit RISC-V RV32I core
//   - Section 4  : CPU is master S0 on the interconnect
//   - Section 5  : CPU can access all 9 slaves
//   - Section 15 : Verilog-2001, synchronous active-high reset
//
// This module is a behavioural stub that models a minimal RISC-V pipeline
// driving the AXI4 master port.  In production this would be replaced by a
// real RISC-V core (e.g. PicoRV32, VexRiscv, SERV).  For simulation and
// FPGA prototyping it provides:
//
//   1. A 32-bit program counter starting at RESET_VECTOR (default 0x00000000).
//   2. An instruction-fetch AXI4 read interface to the instruction memory.
//   3. A load/store AXI4 read/write interface to the data memory and
//      memory-mapped peripherals.
//   4. A simple 3-stage pipeline: FETCH → DECODE/EXECUTE → WRITEBACK.
//   5. A small register file (x0..x31).
//   6. Support for the minimal RV32I instruction subset needed by the
//      firmware: LW, SW, LB, SB, ADDI, ADD, BNE, BEQ, JAL, JALR, LUI, AUIPC.
//
// AXI4 port conventions:
//   - Single-beat (ARLEN/AWLEN = 0), INCR burst, SIZE = 4 bytes.
//   - ID field is tied to a constant to simplify interconnect routing.
//   - PROT = 3'b000, CACHE = 4'b0011 (normal non-cacheable bufferable).
//
// Reset:
//   - On rst the program counter resets to RESET_VECTOR.
//   - All register file entries reset to 0.
//   - AXI handshake signals de-asserted.
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module cpu_axi_master #(
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 8,
    parameter RESET_VECTOR = 32'h0000_0000
) (
    input  wire                    clk,
    input  wire                    rst,

    // =========================================================================
    // AXI4 master interface  (connects to interconnect S0)
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
    // Debug / external halt
    // =========================================================================
    input  wire                    halt,    // stop execution when high
    output wire [ADDR_WIDTH-1:0]   dbg_pc   // current PC (for testbench use)
);

    // =========================================================================
    // Register file
    // =========================================================================
    reg [31:0] regfile [0:31];
    integer    rf_i;

    // =========================================================================
    // Pipeline registers
    // =========================================================================
    reg [31:0] pc;

    // Stage 1: Fetch
    reg [31:0] fetch_pc;
    reg        fetch_valid;

    // Stage 2: Decode / Execute
    reg [31:0] dec_instr;
    reg [31:0] dec_pc;
    reg        dec_valid;

    // AXI fixed fields
    localparam AXI_ID    = {ID_WIDTH{1'b0}};
    localparam AXI_LEN   = 8'h00;
    localparam AXI_SIZE  = 3'b010;   // 4 bytes
    localparam AXI_BURST = 2'b01;    // INCR
    localparam AXI_CACHE = 4'b0011;
    localparam AXI_PROT  = 3'b000;

    // =========================================================================
    // CPU FSM
    // =========================================================================
    localparam [2:0]
        CPU_FETCH    = 3'd0,
        CPU_IFWAIT   = 3'd1,
        CPU_DECODE   = 3'd2,
        CPU_LWAIT    = 3'd3,
        CPU_LWWAIT   = 3'd4,
        CPU_SWWAIT   = 3'd5,
        CPU_SWBWAIT  = 3'd6,
        CPU_HALT     = 3'd7;

    reg [2:0] cpu_state;

    // Decoded fields
    wire [6:0] opcode = dec_instr[ 6: 0];
    wire [4:0] rd     = dec_instr[11: 7];
    wire [2:0] funct3 = dec_instr[14:12];
    wire [4:0] rs1    = dec_instr[19:15];
    wire [4:0] rs2    = dec_instr[24:20];
    wire [6:0] funct7 = dec_instr[31:25];

    // Immediate values
    wire [31:0] imm_i = {{20{dec_instr[31]}}, dec_instr[31:20]};
    wire [31:0] imm_s = {{20{dec_instr[31]}}, dec_instr[31:25], dec_instr[11:7]};
    wire [31:0] imm_b = {{19{dec_instr[31]}}, dec_instr[31], dec_instr[7],
                          dec_instr[30:25], dec_instr[11:8], 1'b0};
    wire [31:0] imm_u = {dec_instr[31:12], 12'h000};
    wire [31:0] imm_j = {{11{dec_instr[31]}}, dec_instr[31], dec_instr[19:12],
                          dec_instr[20], dec_instr[30:21], 1'b0};

    // Register read values
    wire [31:0] rs1_val = (rs1 == 5'd0) ? 32'd0 : regfile[rs1];
    wire [31:0] rs2_val = (rs2 == 5'd0) ? 32'd0 : regfile[rs2];

    // ALU result (combinational)
    reg  [31:0] alu_result;
    always @(*) begin
        case (opcode)
            7'b0010011: begin  // I-type ALU (ADDI, SLTI, ANDI, ORI, XORI, SLLI, SRLI, SRAI)
                case (funct3)
                    3'b000: alu_result = rs1_val + imm_i;           // ADDI
                    3'b010: alu_result = ($signed(rs1_val) < $signed(imm_i)) ? 32'd1 : 32'd0;  // SLTI
                    3'b011: alu_result = (rs1_val < imm_i) ? 32'd1 : 32'd0; // SLTIU
                    3'b100: alu_result = rs1_val ^ imm_i;           // XORI
                    3'b110: alu_result = rs1_val | imm_i;           // ORI
                    3'b111: alu_result = rs1_val & imm_i;           // ANDI
                    3'b001: alu_result = rs1_val << imm_i[4:0];     // SLLI
                    3'b101: alu_result = (funct7[5]) ?
                                $signed(rs1_val) >>> imm_i[4:0] :  // SRAI
                                rs1_val >> imm_i[4:0];              // SRLI
                    default: alu_result = 32'd0;
                endcase
            end
            7'b0110011: begin  // R-type ALU
                case ({funct7[5], funct3})
                    4'b0000: alu_result = rs1_val + rs2_val;         // ADD
                    4'b1000: alu_result = rs1_val - rs2_val;         // SUB
                    4'b0001: alu_result = rs1_val << rs2_val[4:0];   // SLL
                    4'b0010: alu_result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0;
                    4'b0011: alu_result = (rs1_val < rs2_val) ? 32'd1 : 32'd0;
                    4'b0100: alu_result = rs1_val ^ rs2_val;         // XOR
                    4'b0101: alu_result = rs1_val >> rs2_val[4:0];   // SRL
                    4'b1101: alu_result = $signed(rs1_val) >>> rs2_val[4:0]; // SRA
                    4'b0110: alu_result = rs1_val | rs2_val;         // OR
                    4'b0111: alu_result = rs1_val & rs2_val;         // AND
                    default: alu_result = 32'd0;
                endcase
            end
            7'b0110111: alu_result = imm_u;                          // LUI
            7'b0010111: alu_result = dec_pc + imm_u;                 // AUIPC
            7'b1101111: alu_result = dec_pc + 32'd4;                 // JAL link addr
            7'b1100111: alu_result = dec_pc + 32'd4;                 // JALR link addr
            default:    alu_result = 32'd0;
        endcase
    end

    // Branch condition
    wire branch_taken;
    reg  branch_cond;
    always @(*) begin
        case (funct3)
            3'b000: branch_cond = (rs1_val == rs2_val);             // BEQ
            3'b001: branch_cond = (rs1_val != rs2_val);             // BNE
            3'b100: branch_cond = ($signed(rs1_val) < $signed(rs2_val)); // BLT
            3'b101: branch_cond = ($signed(rs1_val) >= $signed(rs2_val)); // BGE
            3'b110: branch_cond = (rs1_val < rs2_val);              // BLTU
            3'b111: branch_cond = (rs1_val >= rs2_val);             // BGEU
            default: branch_cond = 1'b0;
        endcase
    end
    assign branch_taken = (opcode == 7'b1100011) && branch_cond;

    // Next PC calculation
    wire [31:0] branch_target = dec_pc + imm_b;
    wire [31:0] jal_target    = dec_pc + imm_j;
    wire [31:0] jalr_target   = (rs1_val + imm_i) & ~32'd1;

    // Load effective address
    wire [31:0] load_addr  = rs1_val + imm_i;
    wire [31:0] store_addr = rs1_val + imm_s;

    // Store byte strobe and data alignment
    reg [3:0]  sw_strobe;
    reg [31:0] store_wdata;
    always @(*) begin
        case (funct3)
            3'b000: begin // SB
                sw_strobe   = 4'b0001 << store_addr[1:0];
                store_wdata = {4{rs2_val[7:0]}};
            end
            3'b001: begin // SH
                sw_strobe   = store_addr[1] ? 4'b1100 : 4'b0011;
                store_wdata = {2{rs2_val[15:0]}};
            end
            3'b010: begin // SW
                sw_strobe   = 4'b1111;
                store_wdata = rs2_val;
            end
            default: begin
                sw_strobe   = 4'b1111;
                store_wdata = rs2_val;
            end
        endcase
    end

    // Load data from m_axi_rdata directly
    wire [1:0] load_byte_offset = load_addr[1:0];
    reg [31:0] loaded_data;
    always @(*) begin
        case (funct3)
            3'b000: begin // LB
                case (load_byte_offset)
                    2'd0: loaded_data = {{24{m_axi_rdata[ 7]}}, m_axi_rdata[ 7: 0]};
                    2'd1: loaded_data = {{24{m_axi_rdata[15]}}, m_axi_rdata[15: 8]};
                    2'd2: loaded_data = {{24{m_axi_rdata[23]}}, m_axi_rdata[23:16]};
                    2'd3: loaded_data = {{24{m_axi_rdata[31]}}, m_axi_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH
                loaded_data = load_byte_offset[1] ?
                    {{16{m_axi_rdata[31]}}, m_axi_rdata[31:16]} :
                    {{16{m_axi_rdata[15]}}, m_axi_rdata[15: 0]};
            end
            3'b010: loaded_data = m_axi_rdata; // LW
            3'b100: begin // LBU
                case (load_byte_offset)
                    2'd0: loaded_data = {24'd0, m_axi_rdata[ 7: 0]};
                    2'd1: loaded_data = {24'd0, m_axi_rdata[15: 8]};
                    2'd2: loaded_data = {24'd0, m_axi_rdata[23:16]};
                    2'd3: loaded_data = {24'd0, m_axi_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU
                loaded_data = load_byte_offset[1] ?
                    {16'd0, m_axi_rdata[31:16]} :
                    {16'd0, m_axi_rdata[15: 0]};
            end
            default: loaded_data = m_axi_rdata;
        endcase
    end

    assign dbg_pc = pc;

    // =========================================================================
    // Main CPU / AXI FSM
    // =========================================================================
    always @(posedge clk) begin
        if (rst) begin
            pc             <= RESET_VECTOR;
            cpu_state      <= CPU_FETCH;
            fetch_valid    <= 1'b0;
            dec_valid      <= 1'b0;
            m_axi_awvalid  <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            m_axi_bready   <= 1'b0;
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;
            // AXI fixed fields
            m_axi_awid     <= AXI_ID;
            m_axi_awlen    <= AXI_LEN;
            m_axi_awsize   <= AXI_SIZE;
            m_axi_awburst  <= AXI_BURST;
            m_axi_awlock   <= 1'b0;
            m_axi_awcache  <= AXI_CACHE;
            m_axi_awprot   <= AXI_PROT;
            m_axi_awqos    <= 4'd0;
            m_axi_wlast    <= 1'b1;
            m_axi_arid     <= AXI_ID;
            m_axi_arlen    <= AXI_LEN;
            m_axi_arsize   <= AXI_SIZE;
            m_axi_arburst  <= AXI_BURST;
            m_axi_arlock   <= 1'b0;
            m_axi_arcache  <= AXI_CACHE;
            m_axi_arprot   <= AXI_PROT;
            m_axi_arqos    <= 4'd0;
            // Clear register file
            for (rf_i = 0; rf_i < 32; rf_i = rf_i + 1)
                regfile[rf_i] <= 32'd0;
        end else begin

            if (halt) begin
                cpu_state <= CPU_HALT;
            end else begin
                case (cpu_state)

                    // ----------------------------------------------------------
                    CPU_HALT: begin
                        if (!halt) cpu_state <= CPU_FETCH;
                    end

                    // ----------------------------------------------------------
                    // Issue AXI read for instruction at PC
                    // ----------------------------------------------------------
                    CPU_FETCH: begin
                        m_axi_araddr  <= pc;
                        m_axi_arvalid <= 1'b1;
                        m_axi_rready  <= 1'b0;
                        fetch_pc      <= pc;
                        if (m_axi_arvalid && m_axi_arready) begin
                            m_axi_arvalid <= 1'b0;
                            m_axi_rready  <= 1'b1;
                            cpu_state     <= CPU_IFWAIT;
                        end
                    end

                    // ----------------------------------------------------------
                    // Wait for instruction data
                    // ----------------------------------------------------------
                    CPU_IFWAIT: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            m_axi_rready <= 1'b0;
                            dec_instr    <= m_axi_rdata;
                            dec_pc       <= fetch_pc;
                            dec_valid    <= 1'b1;
                            cpu_state    <= CPU_DECODE;
                        end
                    end

                    // ----------------------------------------------------------
                    // Decode + Execute
                    // ----------------------------------------------------------
                    CPU_DECODE: begin
                        dec_valid <= 1'b0;

                        case (opcode)
                            // ---- ALU I-type --------------------------------
                            7'b0010011: begin
                                if (rd != 5'd0) regfile[rd] <= alu_result;
                                pc        <= dec_pc + 32'd4;
                                cpu_state <= CPU_FETCH;
                            end
                            // ---- ALU R-type --------------------------------
                            7'b0110011: begin
                                if (rd != 5'd0) regfile[rd] <= alu_result;
                                pc        <= dec_pc + 32'd4;
                                cpu_state <= CPU_FETCH;
                            end
                            // ---- LUI ---------------------------------------
                            7'b0110111: begin
                                if (rd != 5'd0) regfile[rd] <= alu_result;
                                pc        <= dec_pc + 32'd4;
                                cpu_state <= CPU_FETCH;
                            end
                            // ---- AUIPC -------------------------------------
                            7'b0010111: begin
                                if (rd != 5'd0) regfile[rd] <= alu_result;
                                pc        <= dec_pc + 32'd4;
                                cpu_state <= CPU_FETCH;
                            end
                            // ---- LOAD (LW/LB/LH/LBU/LHU) ------------------
                            7'b0000011: begin
                                m_axi_araddr  <= load_addr;
                                m_axi_arvalid <= 1'b1;
                                m_axi_rready  <= 1'b0;
                                cpu_state     <= CPU_LWAIT;
                            end
                            // ---- STORE (SW/SB/SH) --------------------------
                            7'b0100011: begin
                                m_axi_awaddr  <= store_addr;
                                m_axi_awvalid <= 1'b1;
                                m_axi_wdata   <= store_wdata;
                                m_axi_wstrb   <= sw_strobe;
                                m_axi_wvalid  <= 1'b1;
                                m_axi_bready  <= 1'b0;
                                cpu_state     <= CPU_SWWAIT;
                            end
                            // ---- BRANCH ------------------------------------
                            7'b1100011: begin
                                pc        <= branch_taken ? branch_target : dec_pc + 32'd4;
                                cpu_state <= CPU_FETCH;
                            end
                            // ---- JAL ---------------------------------------
                            7'b1101111: begin
                                if (rd != 5'd0) regfile[rd] <= dec_pc + 32'd4;
                                pc        <= jal_target;
                                cpu_state <= CPU_FETCH;
                            end
                            // ---- JALR --------------------------------------
                            7'b1100111: begin
                                if (rd != 5'd0) regfile[rd] <= dec_pc + 32'd4;
                                pc        <= jalr_target;
                                cpu_state <= CPU_FETCH;
                            end
                            // ---- FENCE (NOP) / SYSTEM ----------------------
                            7'b0001111,
                            7'b1110011: begin
                                pc        <= dec_pc + 32'd4;
                                cpu_state <= CPU_FETCH;
                            end
                            default: begin
                                // Unknown opcode – stall
                                cpu_state <= CPU_HALT;
                            end
                        endcase
                    end

                    // ----------------------------------------------------------
                    // Load: wait for AR to be accepted
                    // ----------------------------------------------------------
                    CPU_LWAIT: begin
                        if (m_axi_arvalid && m_axi_arready) begin
                            m_axi_arvalid <= 1'b0;
                            m_axi_rready  <= 1'b1;
                            cpu_state     <= CPU_LWWAIT;
                        end
                    end

                    // ----------------------------------------------------------
                    // Load: wait for read data
                    // ----------------------------------------------------------
                    CPU_LWWAIT: begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            m_axi_rready  <= 1'b0;
                            if (rd != 5'd0) regfile[rd] <= loaded_data;
                            pc        <= dec_pc + 32'd4;
                            cpu_state <= CPU_FETCH;
                        end
                    end

                    // ----------------------------------------------------------
                    // Store: wait for AW and W acceptance
                    // ----------------------------------------------------------
                    CPU_SWWAIT: begin
                        if (m_axi_awvalid && m_axi_awready) begin
                            m_axi_awvalid <= 1'b0;
                        end
                        if (m_axi_wvalid && m_axi_wready) begin
                            m_axi_wvalid <= 1'b0;
                        end
                        if ((!m_axi_awvalid || m_axi_awready) && (!m_axi_wvalid || m_axi_wready)) begin
                            m_axi_bready <= 1'b1;
                            cpu_state    <= CPU_SWBWAIT;
                        end
                    end

                    // ----------------------------------------------------------
                    // Wait for write response
                    // ----------------------------------------------------------
                    CPU_SWBWAIT: begin
                        if (m_axi_bvalid && m_axi_bready) begin
                            m_axi_bready <= 1'b0;
                            pc           <= dec_pc + 32'd4;
                            cpu_state    <= CPU_FETCH;
                        end
                    end

                    default: cpu_state <= CPU_FETCH;

                endcase
            end
        end
    end

endmodule

`resetall
