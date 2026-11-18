// =============================================================================
// File: i2c_master.v
// Description: Synthesizable I2C Master Controller with Standard 100kHz / 400kHz
//              baud generator, 7-bit slave addressing, START/STOP generation,
//              and ACK/NACK handshake detection.
// =============================================================================

`timescale 1ns / 1ps

module i2c_master #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter I2C_BUS_HZ  = 100_000
)(
    input  wire        clk,
    input  wire        rst,
    
    // Command / Data Interface
    input  wire        start_cmd,     // Pulse to start transfer
    input  wire        stop_cmd,      // Pulse to issue STOP condition
    input  wire        read_cmd,      // 1: Read byte, 0: Write byte
    input  wire [6:0]  slave_addr,    // 7-bit slave address
    input  wire [7:0]  tx_data,       // Data byte to transmit
    output reg  [7:0]  rx_data,       // Data byte received
    output reg         busy,          // High during active transaction
    output reg         ack_error,     // High if slave NACKs
    output reg         done,          // Pulse when byte transaction completes
    
    // I2C Physical Bus Lines (Open-drain with tri-state / pull-up modeling)
    input  wire        scl_i,
    output reg         scl_o,
    output reg         scl_t,         // 1: High-Z (pull-up), 0: Drive low
    input  wire        sda_i,
    output reg         sda_o,
    output reg         sda_t          // 1: High-Z (pull-up), 0: Drive low
);

    // Clock divider for 4 phases per I2C clock cycle:
    // Phase 0: SCL Low,  SDA changes
    // Phase 1: SCL High, setup time
    // Phase 2: SCL High, sample SDA
    // Phase 3: SCL Low,  hold time
    localparam QUARTER_DIV = CLK_FREQ_HZ / (I2C_BUS_HZ * 4);
    
    reg [15:0] clk_cnt;
    reg [1:0]  phase;
    reg        tick;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt <= 16'd0;
            tick    <= 1'b0;
        end else if (busy) begin
            if (clk_cnt >= QUARTER_DIV - 1) begin
                clk_cnt <= 16'd0;
                tick    <= 1'b1;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
                tick    <= 1'b0;
            end
        end else begin
            clk_cnt <= 16'd0;
            tick    <= 1'b0;
        end
    end

    // FSM States
    localparam IDLE       = 4'd0;
    localparam START_COND = 4'd1;
    localparam SEND_ADDR  = 4'd2;
    localparam ADDR_ACK   = 4'd3;
    localparam WRITE_DATA = 4'd4;
    localparam WRITE_ACK  = 4'd5;
    localparam READ_DATA  = 4'd6;
    localparam READ_ACK   = 4'd7;
    localparam STOP_COND  = 4'd8;
    localparam COMPLETE   = 4'd9;

    reg [3:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       is_read;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            busy      <= 1'b0;
            ack_error <= 1'b0;
            done      <= 1'b0;
            rx_data   <= 8'd0;
            scl_o     <= 1'b1;
            scl_t     <= 1'b1;
            sda_o     <= 1'b1;
            sda_t     <= 1'b1;
            bit_cnt   <= 4'd0;
            shift_reg <= 8'd0;
            phase     <= 2'd0;
            is_read   <= 1'b0;
        end else begin
            done <= 1'b0;
            
            case (state)
                IDLE: begin
                    scl_t     <= 1'b1; // Pull-up
                    sda_t     <= 1'b1;
                    ack_error <= 1'b0;
                    phase     <= 2'd0;
                    if (start_cmd) begin
                        busy      <= 1'b1;
                        is_read   <= read_cmd;
                        shift_reg <= {slave_addr, read_cmd};
                        state     <= START_COND;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                START_COND: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin scl_t <= 1'b1; sda_t <= 1'b1; end // SCL=1, SDA=1
                            2'd1: begin sda_o <= 1'b0; sda_t <= 1'b0; end // SDA falls while SCL=1 (START)
                            2'd2: begin scl_o <= 1'b0; scl_t <= 1'b0; end // SCL pulls low
                            2'd3: begin
                                bit_cnt <= 4'd7;
                                state   <= SEND_ADDR;
                            end
                        endcase
                    end
                end

                SEND_ADDR: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin // Phase 0: SCL low, set SDA
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                sda_o <= shift_reg[bit_cnt];
                                sda_t <= shift_reg[bit_cnt];
                            end
                            2'd1: begin // Phase 1: SCL rises
                                scl_t <= 1'b1;
                            end
                            2'd2: begin // Phase 2: SCL high (setup/hold)
                                scl_t <= 1'b1;
                            end
                            2'd3: begin // Phase 3: SCL falls
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                if (bit_cnt == 4'd0) begin
                                    state <= ADDR_ACK;
                                end else begin
                                    bit_cnt <= bit_cnt - 1'b1;
                                end
                            end
                        endcase
                    end
                end

                ADDR_ACK: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin // Release SDA for slave ACK
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                sda_t <= 1'b1;
                            end
                            2'd1: begin // SCL rises
                                scl_t <= 1'b1;
                            end
                            2'd2: begin // Sample ACK on SCL high (ACK is low)
                                scl_t <= 1'b1;
                                if (sda_i != 1'b0) begin
                                    ack_error <= 1'b1; // NACK received
                                end
                            end
                            2'd3: begin // SCL falls
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                bit_cnt <= 4'd7;
                                if (ack_error || sda_i != 1'b0) begin
                                    state <= STOP_COND;
                                end else if (is_read) begin
                                    state <= READ_DATA;
                                end else begin
                                    shift_reg <= tx_data;
                                    state     <= WRITE_DATA;
                                end
                            end
                        endcase
                    end
                end

                WRITE_DATA: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                sda_o <= shift_reg[bit_cnt];
                                sda_t <= shift_reg[bit_cnt];
                            end
                            2'd1: scl_t <= 1'b1;
                            2'd2: scl_t <= 1'b1;
                            2'd3: begin
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                if (bit_cnt == 4'd0)
                                    state <= WRITE_ACK;
                                else
                                    bit_cnt <= bit_cnt - 1'b1;
                            end
                        endcase
                    end
                end

                WRITE_ACK: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin scl_o <= 1'b0; scl_t <= 1'b0; sda_t <= 1'b1; end
                            2'd1: scl_t <= 1'b1;
                            2'd2: begin
                                scl_t <= 1'b1;
                                if (sda_i != 1'b0) ack_error <= 1'b1;
                            end
                            2'd3: begin
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                if (stop_cmd || ack_error)
                                    state <= STOP_COND;
                                else
                                    state <= COMPLETE;
                            end
                        endcase
                    end
                end

                READ_DATA: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin scl_o <= 1'b0; scl_t <= 1'b0; sda_t <= 1'b1; end
                            2'd1: scl_t <= 1'b1;
                            2'd2: begin
                                scl_t <= 1'b1;
                                rx_data[bit_cnt] <= sda_i; // Sample incoming bit
                            end
                            2'd3: begin
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                if (bit_cnt == 4'd0)
                                    state <= READ_ACK;
                                else
                                    bit_cnt <= bit_cnt - 1'b1;
                            end
                        endcase
                    end
                end

                READ_ACK: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin // Master drives ACK (low) or NACK (high if last byte)
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                sda_o <= stop_cmd ? 1'b1 : 1'b0; // NACK before STOP
                                sda_t <= stop_cmd ? 1'b1 : 1'b0;
                            end
                            2'd1: scl_t <= 1'b1;
                            2'd2: scl_t <= 1'b1;
                            2'd3: begin
                                scl_o <= 1'b0; scl_t <= 1'b0;
                                if (stop_cmd)
                                    state <= STOP_COND;
                                else
                                    state <= COMPLETE;
                            end
                        endcase
                    end
                end

                STOP_COND: begin
                    if (tick) begin
                        phase <= phase + 1'b1;
                        case (phase)
                            2'd0: begin scl_o <= 1'b0; scl_t <= 1'b0; sda_o <= 1'b0; sda_t <= 1'b0; end
                            2'd1: begin scl_t <= 1'b1; end // SCL rises high
                            2'd2: begin sda_t <= 1'b1; end // SDA rises while SCL high (STOP condition)
                            2'd3: begin
                                state <= COMPLETE;
                            end
                        endcase
                    end
                end

                COMPLETE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
