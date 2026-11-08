// =============================================================================
// aes.v  –  Dual-Mode AES-128 Encryption Engine (AXI4-Lite slave)
//
// Spec refs:
//   - Section 4  : M5, base 0x10000300, 256 B
//   - Section 5  : CPU and DMA accessible
//   - Section 6  : Dual-Mode AES-128 encryption:
//                    * NIST SP 800-38A Counter (CTR) mode (stream encryption)
//                    * NIST FIPS-197 Electronic Codebook (ECB) mode (block KAT)
//                    * 128-bit key, 128-bit block, 128-bit IV/counter
//   - Section 11 : DMA loads plaintext/reads ciphertext; CPU writes key
//   - soc_defines.vh register map
//
// Register map (byte offsets from base address):
//   0x00  AES_KEY0      RW  : key word 0 (bits 127:96)
//   0x04  AES_KEY1      RW  : key word 1 (bits  95:64)
//   0x08  AES_KEY2      RW  : key word 2 (bits  63:32)
//   0x0C  AES_KEY3      RW  : key word 3 (bits  31:0)
//   0x10  AES_CTRL      RW  : [0]=START  [1]=KEY_VALID  [2]=CTR_MODE (1=CTR, 0=ECB)
//   0x14  AES_STATUS    R   : [0]=DONE   [1]=BUSY
//   0x18  AES_DATA_IN0  W   : plaintext word 0 (bits 127:96)
//   0x1C  AES_DATA_IN1  W   : plaintext word 1 (bits  95:64)
//   0x20  AES_DATA_IN2  W   : plaintext word 2 (bits  63:32)
//   0x24  AES_DATA_IN3  W   : plaintext word 3 (bits  31:0)
//   0x28  AES_DATA_OUT0 R   : ciphertext word 0
//   0x2C  AES_DATA_OUT1 R   : ciphertext word 1
//   0x30  AES_DATA_OUT2 R   : ciphertext word 2
//   0x34  AES_DATA_OUT3 R   : ciphertext word 3
//   0x38  AES_IV0       RW  : CTR IV/Counter word 0 (bits 127:96)
//   0x3C  AES_IV1       RW  : CTR IV/Counter word 1 (bits  95:64)
//   0x40  AES_IV2       RW  : CTR IV/Counter word 2 (bits  63:32)
//   0x44  AES_IV3       RW  : CTR IV/Counter word 3 (bits  31:0)
//
// Operation flow:
//   1. CPU writes 128-bit key to AES_KEY0..3 and sets AES_CTRL[1]=KEY_VALID.
//   2. In CTR mode: Program initial 128-bit IV/Counter at AES_IV0..3.
//   3. CPU or DMA writes 128-bit plaintext to AES_DATA_IN0..3.
//   4. CPU or DMA triggers encryption:
//        - For CTR mode: write AES_CTRL = {CTR_MODE=1, KEY_VALID=1, START=1} (0x07)
//        - For ECB mode: write AES_CTRL = {CTR_MODE=0, KEY_VALID=1, START=1} (0x03)
//   5. Engine computes 10 AES-128 rounds over 11 clock cycles:
//        - In CTR mode: Keystream = AES(Counter); Ciphertext = Plaintext ^ Keystream;
//                       Counter auto-increments (IV <= IV + 1) upon completion.
//        - In ECB mode: Ciphertext = AES(Plaintext).
//   6. AES_STATUS[0]=DONE asserted; ciphertext available in AES_DATA_OUT0..3.
//   7. Reading AES_STATUS clears DONE (read-to-clear) OR writing
//      START=1 again starts a new encryption operation.
//
// Scoped watchdog reset (wdt_rst):
//   - Clears BUSY/DONE and the processing pipeline registers.
//   - Key registers and CTR mode configurations are NOT cleared (retained).
//
// AES-128 implementation:
//   Self-contained, purely combinational S-box table with registered
//   round pipeline. 10-round datapath is pipeline-staged per round to meet
//   timing. Total latency: 11 cycles (1 input register + 10 rounds).
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

module aes #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
) (
    input  wire                    clk,
    input  wire                    rst,       // system reset (synchronous active-high)
    input  wire                    wdt_rst,   // scoped watchdog reset (clears pipeline, not key)

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

    // Status sideband (for DMA polling)
    output wire                    aes_done    // pulses high when encryption complete
);

    // =========================================================================
    // AES S-Box (forward substitution, 256-entry)
    // =========================================================================
    function [7:0] sbox_f;
        input [7:0] x;
        reg [7:0] sbox_rom [0:255];
        integer i;
        begin
            sbox_rom[  0]=8'h63; sbox_rom[  1]=8'h7c; sbox_rom[  2]=8'h77; sbox_rom[  3]=8'h7b;
            sbox_rom[  4]=8'hf2; sbox_rom[  5]=8'h6b; sbox_rom[  6]=8'h6f; sbox_rom[  7]=8'hc5;
            sbox_rom[  8]=8'h30; sbox_rom[  9]=8'h01; sbox_rom[ 10]=8'h67; sbox_rom[ 11]=8'h2b;
            sbox_rom[ 12]=8'hfe; sbox_rom[ 13]=8'hd7; sbox_rom[ 14]=8'hab; sbox_rom[ 15]=8'h76;
            sbox_rom[ 16]=8'hca; sbox_rom[ 17]=8'h82; sbox_rom[ 18]=8'hc9; sbox_rom[ 19]=8'h7d;
            sbox_rom[ 20]=8'hfa; sbox_rom[ 21]=8'h59; sbox_rom[ 22]=8'h47; sbox_rom[ 23]=8'hf0;
            sbox_rom[ 24]=8'had; sbox_rom[ 25]=8'hd4; sbox_rom[ 26]=8'ha2; sbox_rom[ 27]=8'haf;
            sbox_rom[ 28]=8'h9c; sbox_rom[ 29]=8'ha4; sbox_rom[ 30]=8'h72; sbox_rom[ 31]=8'hc0;
            sbox_rom[ 32]=8'hb7; sbox_rom[ 33]=8'hfd; sbox_rom[ 34]=8'h93; sbox_rom[ 35]=8'h26;
            sbox_rom[ 36]=8'h36; sbox_rom[ 37]=8'h3f; sbox_rom[ 38]=8'hf7; sbox_rom[ 39]=8'hcc;
            sbox_rom[ 40]=8'h34; sbox_rom[ 41]=8'ha5; sbox_rom[ 42]=8'he5; sbox_rom[ 43]=8'hf1;
            sbox_rom[ 44]=8'h71; sbox_rom[ 45]=8'hd8; sbox_rom[ 46]=8'h31; sbox_rom[ 47]=8'h15;
            sbox_rom[ 48]=8'h04; sbox_rom[ 49]=8'hc7; sbox_rom[ 50]=8'h23; sbox_rom[ 51]=8'hc3;
            sbox_rom[ 52]=8'h18; sbox_rom[ 53]=8'h96; sbox_rom[ 54]=8'h05; sbox_rom[ 55]=8'h9a;
            sbox_rom[ 56]=8'h07; sbox_rom[ 57]=8'h12; sbox_rom[ 58]=8'h80; sbox_rom[ 59]=8'he2;
            sbox_rom[ 60]=8'heb; sbox_rom[ 61]=8'h27; sbox_rom[ 62]=8'hb2; sbox_rom[ 63]=8'h75;
            sbox_rom[ 64]=8'h09; sbox_rom[ 65]=8'h83; sbox_rom[ 66]=8'h2c; sbox_rom[ 67]=8'h1a;
            sbox_rom[ 68]=8'h1b; sbox_rom[ 69]=8'h6e; sbox_rom[ 70]=8'h5a; sbox_rom[ 71]=8'ha0;
            sbox_rom[ 72]=8'h52; sbox_rom[ 73]=8'h3b; sbox_rom[ 74]=8'hd6; sbox_rom[ 75]=8'hb3;
            sbox_rom[ 76]=8'h29; sbox_rom[ 77]=8'he3; sbox_rom[ 78]=8'h2f; sbox_rom[ 79]=8'h84;
            sbox_rom[ 80]=8'h53; sbox_rom[ 81]=8'hd1; sbox_rom[ 82]=8'h00; sbox_rom[ 83]=8'hed;
            sbox_rom[ 84]=8'h20; sbox_rom[ 85]=8'hfc; sbox_rom[ 86]=8'hb1; sbox_rom[ 87]=8'h5b;
            sbox_rom[ 88]=8'h6a; sbox_rom[ 89]=8'hcb; sbox_rom[ 90]=8'hbe; sbox_rom[ 91]=8'h39;
            sbox_rom[ 92]=8'h4a; sbox_rom[ 93]=8'h4c; sbox_rom[ 94]=8'h58; sbox_rom[ 95]=8'hcf;
            sbox_rom[ 96]=8'hd0; sbox_rom[ 97]=8'hef; sbox_rom[ 98]=8'haa; sbox_rom[ 99]=8'hfb;
            sbox_rom[100]=8'h43; sbox_rom[101]=8'h4d; sbox_rom[102]=8'h33; sbox_rom[103]=8'h85;
            sbox_rom[104]=8'h45; sbox_rom[105]=8'hf9; sbox_rom[106]=8'h02; sbox_rom[107]=8'h7f;
            sbox_rom[108]=8'h50; sbox_rom[109]=8'h3c; sbox_rom[110]=8'h9f; sbox_rom[111]=8'ha8;
            sbox_rom[112]=8'h51; sbox_rom[113]=8'ha3; sbox_rom[114]=8'h40; sbox_rom[115]=8'h8f;
            sbox_rom[116]=8'h92; sbox_rom[117]=8'h9d; sbox_rom[118]=8'h38; sbox_rom[119]=8'hf5;
            sbox_rom[120]=8'hbc; sbox_rom[121]=8'hb6; sbox_rom[122]=8'hda; sbox_rom[123]=8'h21;
            sbox_rom[124]=8'h10; sbox_rom[125]=8'hff; sbox_rom[126]=8'hf3; sbox_rom[127]=8'hd2;
            sbox_rom[128]=8'hcd; sbox_rom[129]=8'h0c; sbox_rom[130]=8'h13; sbox_rom[131]=8'hec;
            sbox_rom[132]=8'h5f; sbox_rom[133]=8'h97; sbox_rom[134]=8'h44; sbox_rom[135]=8'h17;
            sbox_rom[136]=8'hc4; sbox_rom[137]=8'ha7; sbox_rom[138]=8'h7e; sbox_rom[139]=8'h3d;
            sbox_rom[140]=8'h64; sbox_rom[141]=8'h5d; sbox_rom[142]=8'h19; sbox_rom[143]=8'h73;
            sbox_rom[144]=8'h60; sbox_rom[145]=8'h81; sbox_rom[146]=8'h4f; sbox_rom[147]=8'hdc;
            sbox_rom[148]=8'h22; sbox_rom[149]=8'h2a; sbox_rom[150]=8'h90; sbox_rom[151]=8'h88;
            sbox_rom[152]=8'h46; sbox_rom[153]=8'hee; sbox_rom[154]=8'hb8; sbox_rom[155]=8'h14;
            sbox_rom[156]=8'hde; sbox_rom[157]=8'h5e; sbox_rom[158]=8'h0b; sbox_rom[159]=8'hdb;
            sbox_rom[160]=8'he0; sbox_rom[161]=8'h32; sbox_rom[162]=8'h3a; sbox_rom[163]=8'h0a;
            sbox_rom[164]=8'h49; sbox_rom[165]=8'h06; sbox_rom[166]=8'h24; sbox_rom[167]=8'h5c;
            sbox_rom[168]=8'hc2; sbox_rom[169]=8'hd3; sbox_rom[170]=8'hac; sbox_rom[171]=8'h62;
            sbox_rom[172]=8'h91; sbox_rom[173]=8'h95; sbox_rom[174]=8'he4; sbox_rom[175]=8'h79;
            sbox_rom[176]=8'he7; sbox_rom[177]=8'hc8; sbox_rom[178]=8'h37; sbox_rom[179]=8'h6d;
            sbox_rom[180]=8'h8d; sbox_rom[181]=8'hd5; sbox_rom[182]=8'h4e; sbox_rom[183]=8'ha9;
            sbox_rom[184]=8'h6c; sbox_rom[185]=8'h56; sbox_rom[186]=8'hf4; sbox_rom[187]=8'hea;
            sbox_rom[188]=8'h65; sbox_rom[189]=8'h7a; sbox_rom[190]=8'hae; sbox_rom[191]=8'h08;
            sbox_rom[192]=8'hba; sbox_rom[193]=8'h78; sbox_rom[194]=8'h25; sbox_rom[195]=8'h2e;
            sbox_rom[196]=8'h1c; sbox_rom[197]=8'ha6; sbox_rom[198]=8'hb4; sbox_rom[199]=8'hc6;
            sbox_rom[200]=8'he8; sbox_rom[201]=8'hdd; sbox_rom[202]=8'h74; sbox_rom[203]=8'h1f;
            sbox_rom[204]=8'h4b; sbox_rom[205]=8'hbd; sbox_rom[206]=8'h8b; sbox_rom[207]=8'h8a;
            sbox_rom[208]=8'h70; sbox_rom[209]=8'h3e; sbox_rom[210]=8'hb5; sbox_rom[211]=8'h66;
            sbox_rom[212]=8'h48; sbox_rom[213]=8'h03; sbox_rom[214]=8'hf6; sbox_rom[215]=8'h0e;
            sbox_rom[216]=8'h61; sbox_rom[217]=8'h35; sbox_rom[218]=8'h57; sbox_rom[219]=8'hb9;
            sbox_rom[220]=8'h86; sbox_rom[221]=8'hc1; sbox_rom[222]=8'h1d; sbox_rom[223]=8'h9e;
            sbox_rom[224]=8'he1; sbox_rom[225]=8'hf8; sbox_rom[226]=8'h98; sbox_rom[227]=8'h11;
            sbox_rom[228]=8'h69; sbox_rom[229]=8'hd9; sbox_rom[230]=8'h8e; sbox_rom[231]=8'h94;
            sbox_rom[232]=8'h9b; sbox_rom[233]=8'h1e; sbox_rom[234]=8'h87; sbox_rom[235]=8'he9;
            sbox_rom[236]=8'hce; sbox_rom[237]=8'h55; sbox_rom[238]=8'h28; sbox_rom[239]=8'hdf;
            sbox_rom[240]=8'h8c; sbox_rom[241]=8'ha1; sbox_rom[242]=8'h89; sbox_rom[243]=8'h0d;
            sbox_rom[244]=8'hbf; sbox_rom[245]=8'he6; sbox_rom[246]=8'h42; sbox_rom[247]=8'h68;
            sbox_rom[248]=8'h41; sbox_rom[249]=8'h99; sbox_rom[250]=8'h2d; sbox_rom[251]=8'h0f;
            sbox_rom[252]=8'hb0; sbox_rom[253]=8'h54; sbox_rom[254]=8'hbb; sbox_rom[255]=8'h16;
            sbox_f = sbox_rom[x];
        end
    endfunction

    // =========================================================================
    // GF(2^8) multiplication helpers for MixColumns
    // =========================================================================
    function [7:0] xtime;
        input [7:0] x;
        begin
            xtime = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
        end
    endfunction

    function [7:0] mul2;
        input [7:0] x;
        begin mul2 = xtime(x); end
    endfunction

    function [7:0] mul3;
        input [7:0] x;
        begin mul3 = xtime(x) ^ x; end
    endfunction

    // =========================================================================
    // SubBytes on a 128-bit state (applying sbox to each of 16 bytes)
    // =========================================================================
    function [127:0] sub_bytes;
        input [127:0] state;
        integer b;
        reg [127:0] out;
        begin
            for (b = 0; b < 16; b = b + 1)
                out[8*b +: 8] = sbox_f(state[8*b +: 8]);
            sub_bytes = out;
        end
    endfunction

    // =========================================================================
    // ShiftRows:  state is stored column-major (word3=col0 at bits 127:96)
    //   Row 0 (bytes 0,4,8,12 of state matrix) – no shift
    //   Row 1 (bytes 1,5,9,13)                 – shift left by 1
    //   Row 2 (bytes 2,6,10,14)                – shift left by 2
    //   Row 3 (bytes 3,7,11,15)                – shift left by 3
    //
    // State byte index (big-endian word packing):
    //   Word0[31:24] = byte 0  (col0,row0)  Word0[23:16] = byte 1  (col0,row1)
    //   Word0[15: 8] = byte 2  (col0,row2)  Word0[ 7: 0] = byte 3  (col0,row3)
    //   Word1[31:24] = byte 4  (col1,row0)  etc.
    // =========================================================================
    function [127:0] shift_rows;
        input [127:0] s;
        reg [7:0] b [0:15];
        integer i;
        begin
            // unpack (MSB = byte 0)
            for (i = 0; i < 16; i = i + 1)
                b[i] = s[127 - 8*i -: 8];
            // Row 0: b0,b4,b8,b12  → no change
            // Row 1: b1,b5,b9,b13  → rotate left 1: b5,b9,b13,b1
            // Row 2: b2,b6,b10,b14 → rotate left 2: b10,b14,b2,b6
            // Row 3: b3,b7,b11,b15 → rotate left 3: b15,b3,b7,b11
            shift_rows = {b[0], b[5], b[10], b[15],
                          b[4], b[9], b[14], b[3],
                          b[8], b[13], b[2], b[7],
                          b[12], b[1], b[6], b[11]};
        end
    endfunction

    // =========================================================================
    // MixColumns on a single column (4 bytes, big-endian within 32-bit word)
    // =========================================================================
    function [31:0] mix_col;
        input [31:0] col;
        reg [7:0] s0, s1, s2, s3;
        begin
            s0 = col[31:24]; s1 = col[23:16]; s2 = col[15:8]; s3 = col[7:0];
            mix_col = {mul2(s0)^mul3(s1)^s2^s3,
                       s0^mul2(s1)^mul3(s2)^s3,
                       s0^s1^mul2(s2)^mul3(s3),
                       mul3(s0)^s1^s2^mul2(s3)};
        end
    endfunction

    function [127:0] mix_columns;
        input [127:0] s;
        begin
            mix_columns = {mix_col(s[127:96]),
                           mix_col(s[ 95:64]),
                           mix_col(s[ 63:32]),
                           mix_col(s[ 31: 0])};
        end
    endfunction

    // =========================================================================
    // Key Schedule helpers
    // =========================================================================
    function [31:0] sub_word;
        input [31:0] w;
        begin
            sub_word = {sbox_f(w[31:24]), sbox_f(w[23:16]),
                        sbox_f(w[15:8]),  sbox_f(w[7:0])};
        end
    endfunction

    function [31:0] rot_word;
        input [31:0] w;
        begin rot_word = {w[23:0], w[31:24]}; end
    endfunction

    // =========================================================================
    // AES round constants Rcon[1..10]
    // =========================================================================
    function [7:0] rcon;
        input [3:0] r;  // 1-based (1..10)
        begin
            case (r)
                4'd1:  rcon = 8'h01;
                4'd2:  rcon = 8'h02;
                4'd3:  rcon = 8'h04;
                4'd4:  rcon = 8'h08;
                4'd5:  rcon = 8'h10;
                4'd6:  rcon = 8'h20;
                4'd7:  rcon = 8'h40;
                4'd8:  rcon = 8'h80;
                4'd9:  rcon = 8'h1b;
                4'd10: rcon = 8'h36;
                default: rcon = 8'h00;
            endcase
        end
    endfunction

    // =========================================================================
    // Full 10-round key schedule: produce all 11 round keys from key_in
    // =========================================================================
    function [11*128-1:0] key_schedule;
        input [127:0] key_in;
        reg [31:0] w [0:43];
        integer i;
        begin
            // w[0..3] = initial key
            w[0] = key_in[127:96];
            w[1] = key_in[ 95:64];
            w[2] = key_in[ 63:32];
            w[3] = key_in[ 31: 0];

            for (i = 4; i < 44; i = i + 1) begin
                if (i % 4 == 0)
                    w[i] = w[i-4] ^ sub_word(rot_word(w[i-1])) ^ {rcon(i/4), 24'h0};
                else
                    w[i] = w[i-4] ^ w[i-1];
            end

            // Pack round keys: rk[0] = w[0..3], rk[1] = w[4..7] ...
            key_schedule = { w[ 0], w[ 1], w[ 2], w[ 3],
                             w[ 4], w[ 5], w[ 6], w[ 7],
                             w[ 8], w[ 9], w[10], w[11],
                             w[12], w[13], w[14], w[15],
                             w[16], w[17], w[18], w[19],
                             w[20], w[21], w[22], w[23],
                             w[24], w[25], w[26], w[27],
                             w[28], w[29], w[30], w[31],
                             w[32], w[33], w[34], w[35],
                             w[36], w[37], w[38], w[39],
                             w[40], w[41], w[42], w[43] };
        end
    endfunction

    // =========================================================================
    // Registers
    // =========================================================================
    reg [127:0] key_r;           // AES key – survives wdt_rst
    reg         key_valid_r;

    reg [127:0] plaintext_r;     // input data
    reg [127:0] pt_lat;          // Plaintext latched when operation starts
    reg [127:0] ciphertext_r;    // output data
    reg [127:0] iv_ctr_r;        // CTR mode 128-bit counter / IV (retained across wdt_rst)
    reg         mode_ctr_r;      // 1 = CTR mode, 0 = ECB mode

    reg         start_r;         // latched START pulse
    reg         busy_r;
    reg         done_r;
    reg         status_read_latched; // Track status read on AR phase for clean read-to-clear

    // =========================================================================
    // Pipeline: 11 stage registers (stage 0 = after AddRoundKey with rk0,
    //           stages 1-10 = after each AES round)
    // =========================================================================
    reg [127:0] pipe  [0:10];
    reg [10:0]  pipe_v;           // valid bits for each pipeline stage

    // Pre-compute key schedule (combinational)
    wire [11*128-1:0] rkeys = key_schedule(key_r);

    // Helper to extract round key i (0-indexed)
    function [127:0] rk;
        input [10*128+127:0] ks;
        input integer        i;
        begin rk = ks[128*(10-i) +: 128]; end
    endfunction

    // =========================================================================
    // Encryption pipeline (synchronous, 11 cycles latency)
    // =========================================================================
    wire do_rst = rst | wdt_rst;

    integer p;

    always @(posedge clk) begin
        if (do_rst) begin
            pipe_v  <= 11'b0;
            busy_r  <= 1'b0;
            done_r  <= 1'b0;
        end else begin
            // Stage 0: initial AddRoundKey
            // In CTR mode, input to cipher is iv_ctr_r; in ECB mode, plaintext_r
            if (start_r && key_valid_r) begin
                pipe[0]  <= (mode_ctr_r ? iv_ctr_r : plaintext_r) ^ rk(rkeys, 0);
                pt_lat   <= plaintext_r;
                pipe_v[0]<= 1'b1;
                busy_r   <= 1'b1;
                done_r   <= 1'b0;
            end else begin
                pipe_v[0] <= 1'b0;
            end

            // Rounds 1-9: SubBytes + ShiftRows + MixColumns + AddRoundKey
            begin : round_loop
                integer r;
                for (r = 1; r <= 9; r = r + 1) begin
                    if (pipe_v[r-1]) begin
                        pipe[r]   <= mix_columns(shift_rows(sub_bytes(pipe[r-1]))) ^ rk(rkeys, r);
                        pipe_v[r] <= 1'b1;
                    end else begin
                        pipe_v[r] <= 1'b0;
                    end
                end
            end

            // Round 10: SubBytes + ShiftRows + AddRoundKey (no MixColumns)
            if (pipe_v[9]) begin
                pipe[10]   <= shift_rows(sub_bytes(pipe[9])) ^ rk(rkeys, 10);
                pipe_v[10] <= 1'b1;
            end else begin
                pipe_v[10] <= 1'b0;
            end

            // Capture result
            if (pipe_v[10]) begin
                // In CTR mode: Ciphertext = Plaintext ^ Keystream; auto-increment counter
                if (mode_ctr_r) begin
                    ciphertext_r <= pt_lat ^ pipe[10];
                    iv_ctr_r     <= iv_ctr_r + 1'b1;
                end else begin
                    ciphertext_r <= pipe[10];
                end
                busy_r       <= 1'b0;
                done_r       <= 1'b1;
            end
        end
    end

    assign aes_done = done_r;

    // =========================================================================
    // AXI4-Lite slave  –  Write path
    // =========================================================================
    wire [7:0] aw_off = s_axi_awaddr[7:0];

    reg [ADDR_WIDTH-1:0] aw_addr_lat;
    reg                  aw_pend;

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
            key_r         <= 128'b0;
            key_valid_r   <= 1'b0;
            plaintext_r   <= 128'b0;
            iv_ctr_r      <= 128'h0000_0000_0000_0000_0000_0000_0000_0001;
            mode_ctr_r    <= 1'b0;
            start_r       <= 1'b0;
        end else if (wdt_rst) begin
            start_r       <= 1'b0;
        end else begin
            start_r       <= 1'b0;   // Single-cycle pulse default

            // AW and W concurrent
            if (aw_fire && w_fire) begin
                case (cur_wr_off)
                    8'h00: begin
                               if (cur_wstrb[3]) key_r[127:120] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[119:112] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[111:104] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[103: 96] <= cur_wdata[ 7: 0];
                           end
                    8'h04: begin
                               if (cur_wstrb[3]) key_r[ 95: 88] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[ 87: 80] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[ 79: 72] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[ 71: 64] <= cur_wdata[ 7: 0];
                           end
                    8'h08: begin
                               if (cur_wstrb[3]) key_r[ 63: 56] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[ 55: 48] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[ 47: 40] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[ 39: 32] <= cur_wdata[ 7: 0];
                           end
                    8'h0C: begin
                               if (cur_wstrb[3]) key_r[ 31: 24] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[ 23: 16] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[ 15:  8] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[  7:  0] <= cur_wdata[ 7: 0];
                           end
                    8'h10: begin
                               if (cur_wstrb[0]) begin
                                   start_r     <= cur_wdata[0];
                                   key_valid_r <= cur_wdata[1];
                                   if (cur_wdata[2])
                                       mode_ctr_r <= 1'b1;
                                   else if (!cur_wdata[0])
                                       mode_ctr_r <= 1'b0;
                               end
                           end
                    8'h18: begin
                               if (cur_wstrb[3]) plaintext_r[127:120] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[119:112] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[111:104] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[103: 96] <= cur_wdata[ 7: 0];
                           end
                    8'h1C: begin
                               if (cur_wstrb[3]) plaintext_r[ 95: 88] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[ 87: 80] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[ 79: 72] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[ 71: 64] <= cur_wdata[ 7: 0];
                           end
                    8'h20: begin
                               if (cur_wstrb[3]) plaintext_r[ 63: 56] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[ 55: 48] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[ 47: 40] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[ 39: 32] <= cur_wdata[ 7: 0];
                           end
                    8'h24: begin
                               if (cur_wstrb[3]) plaintext_r[ 31: 24] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[ 23: 16] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[ 15:  8] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[  7:  0] <= cur_wdata[ 7: 0];
                           end
                    8'h38: begin
                               if (cur_wstrb[3]) iv_ctr_r[127:120] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[119:112] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[111:104] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[103: 96] <= cur_wdata[ 7: 0];
                           end
                    8'h3C: begin
                               if (cur_wstrb[3]) iv_ctr_r[ 95: 88] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[ 87: 80] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[ 79: 72] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[ 71: 64] <= cur_wdata[ 7: 0];
                           end
                    8'h40: begin
                               if (cur_wstrb[3]) iv_ctr_r[ 63: 56] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[ 55: 48] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[ 47: 40] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[ 39: 32] <= cur_wdata[ 7: 0];
                           end
                    8'h44: begin
                               if (cur_wstrb[3]) iv_ctr_r[ 31: 24] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[ 23: 16] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[ 15:  8] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[  7:  0] <= cur_wdata[ 7: 0];
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
                    8'h00: begin
                               if (cur_wstrb[3]) key_r[127:120] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[119:112] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[111:104] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[103: 96] <= cur_wdata[ 7: 0];
                           end
                    8'h04: begin
                               if (cur_wstrb[3]) key_r[ 95: 88] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[ 87: 80] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[ 79: 72] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[ 71: 64] <= cur_wdata[ 7: 0];
                           end
                    8'h08: begin
                               if (cur_wstrb[3]) key_r[ 63: 56] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[ 55: 48] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[ 47: 40] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[ 39: 32] <= cur_wdata[ 7: 0];
                           end
                    8'h0C: begin
                               if (cur_wstrb[3]) key_r[ 31: 24] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) key_r[ 23: 16] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) key_r[ 15:  8] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) key_r[  7:  0] <= cur_wdata[ 7: 0];
                           end
                    8'h10: begin
                               if (cur_wstrb[0]) begin
                                   start_r     <= cur_wdata[0];
                                   key_valid_r <= cur_wdata[1];
                                   if (cur_wdata[2])
                                       mode_ctr_r <= 1'b1;
                                   else if (!cur_wdata[0])
                                       mode_ctr_r <= 1'b0;
                               end
                           end
                    8'h18: begin
                               if (cur_wstrb[3]) plaintext_r[127:120] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[119:112] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[111:104] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[103: 96] <= cur_wdata[ 7: 0];
                           end
                    8'h1C: begin
                               if (cur_wstrb[3]) plaintext_r[ 95: 88] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[ 87: 80] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[ 79: 72] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[ 71: 64] <= cur_wdata[ 7: 0];
                           end
                    8'h20: begin
                               if (cur_wstrb[3]) plaintext_r[ 63: 56] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[ 55: 48] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[ 47: 40] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[ 39: 32] <= cur_wdata[ 7: 0];
                           end
                    8'h24: begin
                               if (cur_wstrb[3]) plaintext_r[ 31: 24] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) plaintext_r[ 23: 16] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) plaintext_r[ 15:  8] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) plaintext_r[  7:  0] <= cur_wdata[ 7: 0];
                           end
                    8'h38: begin
                               if (cur_wstrb[3]) iv_ctr_r[127:120] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[119:112] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[111:104] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[103: 96] <= cur_wdata[ 7: 0];
                           end
                    8'h3C: begin
                               if (cur_wstrb[3]) iv_ctr_r[ 95: 88] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[ 87: 80] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[ 79: 72] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[ 71: 64] <= cur_wdata[ 7: 0];
                           end
                    8'h40: begin
                               if (cur_wstrb[3]) iv_ctr_r[ 63: 56] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[ 55: 48] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[ 47: 40] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[ 39: 32] <= cur_wdata[ 7: 0];
                           end
                    8'h44: begin
                               if (cur_wstrb[3]) iv_ctr_r[ 31: 24] <= cur_wdata[31:24];
                               if (cur_wstrb[2]) iv_ctr_r[ 23: 16] <= cur_wdata[23:16];
                               if (cur_wstrb[1]) iv_ctr_r[ 15:  8] <= cur_wdata[15: 8];
                               if (cur_wstrb[0]) iv_ctr_r[  7:  0] <= cur_wdata[ 7: 0];
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
    // AXI4-Lite slave  –  Read path
    // =========================================================================
    wire [7:0] ar_off = s_axi_araddr[7:0];

    always @(posedge clk) begin
        if (rst) begin
            s_axi_arready       <= 1'b1;
            s_axi_rvalid        <= 1'b0;
            s_axi_rresp         <= 2'b00;
            s_axi_rdata         <= 32'd0;
            status_read_latched <= 1'b0;
        end else if (wdt_rst) begin
            status_read_latched <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready       <= 1'b0;
                status_read_latched <= (ar_off == 8'h14);
                case (ar_off)
                    // Key readback
                    8'h00: s_axi_rdata <= key_r[127:96];
                    8'h04: s_axi_rdata <= key_r[ 95:64];
                    8'h08: s_axi_rdata <= key_r[ 63:32];
                    8'h0C: s_axi_rdata <= key_r[ 31: 0];
                    // CTRL
                    8'h10: s_axi_rdata <= {29'd0, mode_ctr_r, key_valid_r, 1'b0};  // START is pulse
                    // STATUS (reading DONE clears it)
                    8'h14: s_axi_rdata <= {30'd0, busy_r, done_r};
                    // Plaintext
                    8'h18: s_axi_rdata <= plaintext_r[127:96];
                    8'h1C: s_axi_rdata <= plaintext_r[ 95:64];
                    8'h20: s_axi_rdata <= plaintext_r[ 63:32];
                    8'h24: s_axi_rdata <= plaintext_r[ 31: 0];
                    // Ciphertext
                    8'h28: s_axi_rdata <= ciphertext_r[127:96];
                    8'h2C: s_axi_rdata <= ciphertext_r[ 95:64];
                    8'h30: s_axi_rdata <= ciphertext_r[ 63:32];
                    8'h34: s_axi_rdata <= ciphertext_r[ 31: 0];
                    // IV / CTR readback
                    8'h38: s_axi_rdata <= iv_ctr_r[127:96];
                    8'h3C: s_axi_rdata <= iv_ctr_r[ 95:64];
                    8'h40: s_axi_rdata <= iv_ctr_r[ 63:32];
                    8'h44: s_axi_rdata <= iv_ctr_r[ 31: 0];
                    default: s_axi_rdata <= 32'd0;
                endcase
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
            end

            // Clear done only after STATUS read is consumed by master with DONE=1
            if (s_axi_rvalid && s_axi_rready && status_read_latched && s_axi_rdata[0])
                done_r <= 1'b0;

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid        <= 1'b0;
                s_axi_arready       <= 1'b1;
                status_read_latched <= 1'b0;
            end
        end
    end

endmodule

`resetall
