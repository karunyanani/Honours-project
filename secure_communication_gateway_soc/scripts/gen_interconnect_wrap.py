#!/usr/bin/env python3
"""
gen_interconnect_wrap.py
========================
Generator for soc_axi_interconnect_wrap_2x9.v

Usage (from repo root):
    python3 scripts/gen_interconnect_wrap.py > rtl/soc_axi_interconnect_wrap_2x9.v

Requirements:
  - Python 3.6+
  - No external dependencies

This script encodes all address-map and connectivity information from the SoC
requirements document in one place (mirroring soc_defines.vh) and emits a
fully-expanded, hand-unrolled Verilog-2001 wrapper so that the module can be
audited without running the script.

Re-generate whenever the address map or slave list changes.
"""

import textwrap, sys

# ---------------------------------------------------------------------------
# Address map definition  (single source of truth → also reflected in soc_defines.vh)
# ---------------------------------------------------------------------------
# Each entry: (m_port_idx, name, base_addr, addr_width_log2, connect_mask)
#   connect_mask: 2-bit field  bit0=RISC-V(S0)  bit1=DMA(S1)
SLAVES = [
    # port  name            base         aw    mask
    (0,  "IMEM",  0x00000000, 16, 0b01),  # RISC-V only
    (1,  "DMEM",  0x00010000, 16, 0b11),  # both
    (2,  "UART",  0x10000000,  8, 0b11),  # both
    (3,  "TIMER", 0x10000100,  8, 0b01),  # RISC-V only
    (4,  "GPIO",  0x10000200,  8, 0b01),  # RISC-V only
    (5,  "AES",   0x10000300,  8, 0b11),  # both
    (6,  "DMA",   0x10000400,  8, 0b01),  # RISC-V only (DMA cannot reach its own cfg)
    (7,  "SPI",   0x10000500,  8, 0b11),  # both
    (8,  "WDT",   0x10000600,  8, 0b01),  # RISC-V only
]

S_COUNT = 2   # masters: 0=RISC-V core, 1=DMA Controller
M_COUNT = len(SLAVES)

# Build packed parameter values (MSB = highest M-port index)
def pack_base_addr():
    """Returns 288-bit hex string for M_BASE_ADDR (9 x 32-bit fields, M8 at MSB)."""
    val = 0
    for port, name, base, aw, mask in reversed(SLAVES):
        val = (val << 32) | (base & 0xFFFFFFFF)
    # reversed() makes M8 the last appended → shifts to MSB position correctly
    # Actually we need M0 at LSB: iterate in normal order and shift up
    val = 0
    for port, name, base, aw, mask in SLAVES:
        val |= (base & 0xFFFFFFFF) << (port * 32)
    return val

def pack_addr_width():
    """Returns 288-bit value for M_ADDR_WIDTH (9 x 32-bit fields)."""
    val = 0
    for port, name, base, aw, mask in SLAVES:
        val |= (aw & 0xFFFFFFFF) << (port * 32)
    return val

def pack_connect(bit):
    """Pack connectivity for a given S-port bit position (bit0=S0, bit1=S1)."""
    # M_CONNECT_READ / M_CONNECT_WRITE:
    # M_COUNT concatenated fields of S_COUNT bits
    # Field for M-port i occupies bits [i*S_COUNT +: S_COUNT]
    val = 0
    for port, name, base, aw, mask in SLAVES:
        s_bit = (mask >> bit) & 1
        val |= s_bit << port   # bit per M-port whether S[bit] can access it
    # Now pack as M_COUNT x S_COUNT word:
    # Each M-port contributes S_COUNT=2 bits.  bit[i*2+0]=S0, bit[i*2+1]=S1
    packed = 0
    for port, name, base, aw, mask in SLAVES:
        s0 = (mask >> 0) & 1
        s1 = (mask >> 1) & 1
        packed |= (s0 << (port * S_COUNT + 0))
        packed |= (s1 << (port * S_COUNT + 1))
    return packed

def hex_param(val, bits):
    """Format as Verilog integer literal."""
    nibbles = (bits + 3) // 4
    return f"{bits}'h{val:0{nibbles}X}"

BASE_ADDR_VAL  = pack_base_addr()
ADDR_WIDTH_VAL = pack_addr_width()
CONN_VAL       = pack_connect(0)   # same value used for both R and W (symmetric)

BASE_ADDR_BITS  = M_COUNT * 32
ADDR_WIDTH_BITS = M_COUNT * 32
CONN_BITS       = M_COUNT * S_COUNT

# ---------------------------------------------------------------------------
# Port list helpers
# ---------------------------------------------------------------------------

def s_ports(sig, width, direction, count=S_COUNT):
    return f"    {direction:6s} wire [{count}*{width}-1:0] {sig}"

def m_ports(sig, width, direction, count=M_COUNT):
    return f"    {direction:6s} wire [{count}*{width}-1:0] {sig}"

HEADER = """\
// =============================================================================
// soc_axi_interconnect_wrap_2x9.v
//
// AXI4 interconnect wrapper: 2 masters (S-side) x 9 slaves (M-side)
//
// THIS FILE IS GENERATED.  Do not edit by hand.
// Re-generate:
//   python3 scripts/gen_interconnect_wrap.py > rtl/soc_axi_interconnect_wrap_2x9.v
//
// Address map and connectivity are defined in:
//   rtl/soc_defines.vh   (Verilog)
//   scripts/gen_interconnect_wrap.py  (generator / ground truth)
//
// Arbitration policy: round-robin across {arb_chans} request channels
//   (one write-request + one read-request channel per master).
//   ARB_LSB_HIGH_PRIORITY=1 means the lower-indexed channel wins ties.
//   Channel encoding: channel 0 = S0-write, 1 = S0-read,
//                     2 = S1-write, 3 = S1-read.
//   DMA (S1) is channels 2/3; RISC-V core (S0) is channels 0/1.
//   Under equal contention, S0 (lower index) wins.  This is documented
//   and tested in tb/tb_interconnect.sv (arbitration test).
// =============================================================================

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "soc_defines.vh"
"""

def gen_wrapper():
    lines = []
    lines.append(HEADER.format(arb_chans=S_COUNT*2))

    # ---- module declaration --------------------------------------------------
    lines.append(f"module soc_axi_interconnect_wrap_2x9 (")
    lines.append(f"    input  wire clk,")
    lines.append(f"    input  wire rst,")
    lines.append(f"")

    # S-side (master → interconnect)
    lines.append(f"    //")
    lines.append(f"    // S-side (AXI master interfaces – drives these ports)")
    lines.append(f"    //")
    for ch in ["aw", "w", "b", "ar", "r"]:
        if ch == "aw":
            sigs = [
                ("s_axi_awid",    f"AXI_ID_WIDTH",   "input "),
                ("s_axi_awaddr",  f"AXI_ADDR_WIDTH", "input "),
                ("s_axi_awlen",   f"8",               "input "),
                ("s_axi_awsize",  f"3",               "input "),
                ("s_axi_awburst", f"2",               "input "),
                ("s_axi_awlock",  f"1",               "input "),
                ("s_axi_awcache", f"4",               "input "),
                ("s_axi_awprot",  f"3",               "input "),
                ("s_axi_awqos",   f"4",               "input "),
                ("s_axi_awvalid", f"1",               "input "),
                ("s_axi_awready", f"1",               "output"),
            ]
        elif ch == "w":
            sigs = [
                ("s_axi_wdata",  f"AXI_DATA_WIDTH", "input "),
                ("s_axi_wstrb",  f"AXI_STRB_WIDTH", "input "),
                ("s_axi_wlast",  f"1",              "input "),
                ("s_axi_wvalid", f"1",              "input "),
                ("s_axi_wready", f"1",              "output"),
            ]
        elif ch == "b":
            sigs = [
                ("s_axi_bid",    f"AXI_ID_WIDTH", "output"),
                ("s_axi_bresp",  f"2",            "output"),
                ("s_axi_bvalid", f"1",            "output"),
                ("s_axi_bready", f"1",            "input "),
            ]
        elif ch == "ar":
            sigs = [
                ("s_axi_arid",    f"AXI_ID_WIDTH",   "input "),
                ("s_axi_araddr",  f"AXI_ADDR_WIDTH", "input "),
                ("s_axi_arlen",   f"8",               "input "),
                ("s_axi_arsize",  f"3",               "input "),
                ("s_axi_arburst", f"2",               "input "),
                ("s_axi_arlock",  f"1",               "input "),
                ("s_axi_arcache", f"4",               "input "),
                ("s_axi_arprot",  f"3",               "input "),
                ("s_axi_arqos",   f"4",               "input "),
                ("s_axi_arvalid", f"1",               "input "),
                ("s_axi_arready", f"1",               "output"),
            ]
        else:  # r
            sigs = [
                ("s_axi_rid",    f"AXI_ID_WIDTH",   "output"),
                ("s_axi_rdata",  f"AXI_DATA_WIDTH", "output"),
                ("s_axi_rresp",  f"2",              "output"),
                ("s_axi_rlast",  f"1",              "output"),
                ("s_axi_rvalid", f"1",              "output"),
                ("s_axi_rready", f"1",              "input "),
            ]
        lines.append(f"    // {ch.upper()} channel")
        for sig, w, dir_ in sigs:
            if w == "1":
                lines.append(f"    {dir_} wire [{S_COUNT}-1:0]              {sig},")
            elif w in ("AXI_ID_WIDTH", "AXI_ADDR_WIDTH", "AXI_DATA_WIDTH", "AXI_STRB_WIDTH"):
                lines.append(f"    {dir_} wire [{S_COUNT}*`{w}-1:0]     {sig},")
            else:
                lines.append(f"    {dir_} wire [{S_COUNT}*{w}-1:0]          {sig},")
        lines.append("")

    # M-side (interconnect → slave)
    lines.append(f"    //")
    lines.append(f"    // M-side (AXI slave interfaces – drives these ports)")
    lines.append(f"    //")
    M = M_COUNT
    for ch in ["aw", "w", "b", "ar", "r"]:
        if ch == "aw":
            sigs = [
                ("m_axi_awid",     "AXI_ID_WIDTH",   "output"),
                ("m_axi_awaddr",   "AXI_ADDR_WIDTH", "output"),
                ("m_axi_awlen",    "8",              "output"),
                ("m_axi_awsize",   "3",              "output"),
                ("m_axi_awburst",  "2",              "output"),
                ("m_axi_awlock",   "1",              "output"),
                ("m_axi_awcache",  "4",              "output"),
                ("m_axi_awprot",   "3",              "output"),
                ("m_axi_awqos",    "4",              "output"),
                ("m_axi_awregion", "4",              "output"),
                ("m_axi_awvalid",  "1",              "output"),
                ("m_axi_awready",  "1",              "input "),
            ]
        elif ch == "w":
            sigs = [
                ("m_axi_wdata",  "AXI_DATA_WIDTH", "output"),
                ("m_axi_wstrb",  "AXI_STRB_WIDTH", "output"),
                ("m_axi_wlast",  "1",              "output"),
                ("m_axi_wvalid", "1",              "output"),
                ("m_axi_wready", "1",              "input "),
            ]
        elif ch == "b":
            sigs = [
                ("m_axi_bid",    "AXI_ID_WIDTH", "input "),
                ("m_axi_bresp",  "2",            "input "),
                ("m_axi_bvalid", "1",            "input "),
                ("m_axi_bready", "1",            "output"),
            ]
        elif ch == "ar":
            sigs = [
                ("m_axi_arid",     "AXI_ID_WIDTH",   "output"),
                ("m_axi_araddr",   "AXI_ADDR_WIDTH", "output"),
                ("m_axi_arlen",    "8",              "output"),
                ("m_axi_arsize",   "3",              "output"),
                ("m_axi_arburst",  "2",              "output"),
                ("m_axi_arlock",   "1",              "output"),
                ("m_axi_arcache",  "4",              "output"),
                ("m_axi_arprot",   "3",              "output"),
                ("m_axi_arqos",    "4",              "output"),
                ("m_axi_arregion", "4",              "output"),
                ("m_axi_arvalid",  "1",              "output"),
                ("m_axi_arready",  "1",              "input "),
            ]
        else:  # r
            sigs = [
                ("m_axi_rid",    "AXI_ID_WIDTH",   "input "),
                ("m_axi_rdata",  "AXI_DATA_WIDTH", "input "),
                ("m_axi_rresp",  "2",              "input "),
                ("m_axi_rlast",  "1",              "input "),
                ("m_axi_rvalid", "1",              "input "),
                ("m_axi_rready", "1",              "output"),
            ]
        lines.append(f"    // {ch.upper()} channel")
        last_sig = sigs[-1][0]
        for sig, w, dir_ in sigs:
            comma = "" if (sig == last_sig and ch == "r") else ","
            if w == "1":
                lines.append(f"    {dir_} wire [{M}-1:0]              {sig}{comma}")
            elif w in ("AXI_ID_WIDTH", "AXI_ADDR_WIDTH", "AXI_DATA_WIDTH", "AXI_STRB_WIDTH"):
                lines.append(f"    {dir_} wire [{M}*`{w}-1:0]     {sig}{comma}")
            else:
                lines.append(f"    {dir_} wire [{M}*{w}-1:0]          {sig}{comma}")
        lines.append("")

    lines.append(");")
    lines.append("")

    # ---- unused-user stubs (tied off inside) --------------------------------
    lines.append("    // USER / xUSER signals are disabled (AWUSER_ENABLE = 0)")
    lines.append("    wire [2-1:0]  s_axi_awuser_tieoff = 2'b0;")
    lines.append("    wire [2-1:0]  s_axi_wuser_tieoff  = 2'b0;")
    lines.append("    wire [2-1:0]  s_axi_aruser_tieoff = 2'b0;")
    lines.append("    wire [2*1-1:0] s_axi_buser_nc;")
    lines.append("    wire [2*1-1:0] s_axi_ruser_nc;")
    lines.append("    wire [9*1-1:0] m_axi_awuser_nc;")
    lines.append("    wire [9*1-1:0] m_axi_wuser_nc;")
    lines.append("    wire [9*1-1:0] m_axi_aruser_nc;")
    lines.append("    wire [9*1-1:0] m_axi_buser_tieoff = 9'b0;")
    lines.append("    wire [9*1-1:0] m_axi_ruser_tieoff = 9'b0;")
    lines.append("")

    # ---- instantiation -------------------------------------------------------
    base_hex  = hex_param(BASE_ADDR_VAL,  BASE_ADDR_BITS)
    addrw_hex = hex_param(ADDR_WIDTH_VAL, ADDR_WIDTH_BITS)
    conn_hex  = hex_param(CONN_VAL,       CONN_BITS)

    lines.append("    axi_interconnect #(")
    lines.append(f"        .S_COUNT          ({S_COUNT}),")
    lines.append(f"        .M_COUNT          ({M_COUNT}),")
    lines.append(f"        .DATA_WIDTH       (`AXI_DATA_WIDTH),")
    lines.append(f"        .ADDR_WIDTH       (`AXI_ADDR_WIDTH),")
    lines.append(f"        .STRB_WIDTH       (`AXI_STRB_WIDTH),")
    lines.append(f"        .ID_WIDTH         (`AXI_ID_WIDTH),")
    lines.append(f"        .AWUSER_ENABLE    (0),")
    lines.append(f"        .WUSER_ENABLE     (0),")
    lines.append(f"        .BUSER_ENABLE     (0),")
    lines.append(f"        .ARUSER_ENABLE    (0),")
    lines.append(f"        .RUSER_ENABLE     (0),")
    lines.append(f"        .FORWARD_ID       (0),")
    lines.append(f"        .M_REGIONS        (1),")
    lines.append(f"        .M_BASE_ADDR      ({base_hex}),")
    lines.append(f"        .M_ADDR_WIDTH     ({addrw_hex}),")
    lines.append(f"        .M_CONNECT_READ   ({conn_hex}),")
    lines.append(f"        .M_CONNECT_WRITE  ({conn_hex}),")
    lines.append(f"        .M_SECURE         (9'b0)")
    lines.append(f"    ) u_axi_interconnect (")
    lines.append(f"        .clk              (clk),")
    lines.append(f"        .rst              (rst),")
    lines.append(f"        // S-side (from masters)")
    lines.append(f"        .s_axi_awid       (s_axi_awid),")
    lines.append(f"        .s_axi_awaddr     (s_axi_awaddr),")
    lines.append(f"        .s_axi_awlen      (s_axi_awlen),")
    lines.append(f"        .s_axi_awsize     (s_axi_awsize),")
    lines.append(f"        .s_axi_awburst    (s_axi_awburst),")
    lines.append(f"        .s_axi_awlock     (s_axi_awlock),")
    lines.append(f"        .s_axi_awcache    (s_axi_awcache),")
    lines.append(f"        .s_axi_awprot     (s_axi_awprot),")
    lines.append(f"        .s_axi_awqos      (s_axi_awqos),")
    lines.append(f"        .s_axi_awuser     (s_axi_awuser_tieoff),")
    lines.append(f"        .s_axi_awvalid    (s_axi_awvalid),")
    lines.append(f"        .s_axi_awready    (s_axi_awready),")
    lines.append(f"        .s_axi_wdata      (s_axi_wdata),")
    lines.append(f"        .s_axi_wstrb      (s_axi_wstrb),")
    lines.append(f"        .s_axi_wlast      (s_axi_wlast),")
    lines.append(f"        .s_axi_wuser      (s_axi_wuser_tieoff),")
    lines.append(f"        .s_axi_wvalid     (s_axi_wvalid),")
    lines.append(f"        .s_axi_wready     (s_axi_wready),")
    lines.append(f"        .s_axi_bid        (s_axi_bid),")
    lines.append(f"        .s_axi_bresp      (s_axi_bresp),")
    lines.append(f"        .s_axi_buser      (s_axi_buser_nc),")
    lines.append(f"        .s_axi_bvalid     (s_axi_bvalid),")
    lines.append(f"        .s_axi_bready     (s_axi_bready),")
    lines.append(f"        .s_axi_arid       (s_axi_arid),")
    lines.append(f"        .s_axi_araddr     (s_axi_araddr),")
    lines.append(f"        .s_axi_arlen      (s_axi_arlen),")
    lines.append(f"        .s_axi_arsize     (s_axi_arsize),")
    lines.append(f"        .s_axi_arburst    (s_axi_arburst),")
    lines.append(f"        .s_axi_arlock     (s_axi_arlock),")
    lines.append(f"        .s_axi_arcache    (s_axi_arcache),")
    lines.append(f"        .s_axi_arprot     (s_axi_arprot),")
    lines.append(f"        .s_axi_arqos      (s_axi_arqos),")
    lines.append(f"        .s_axi_aruser     (s_axi_aruser_tieoff),")
    lines.append(f"        .s_axi_arvalid    (s_axi_arvalid),")
    lines.append(f"        .s_axi_arready    (s_axi_arready),")
    lines.append(f"        .s_axi_rid        (s_axi_rid),")
    lines.append(f"        .s_axi_rdata      (s_axi_rdata),")
    lines.append(f"        .s_axi_rresp      (s_axi_rresp),")
    lines.append(f"        .s_axi_rlast      (s_axi_rlast),")
    lines.append(f"        .s_axi_ruser      (s_axi_ruser_nc),")
    lines.append(f"        .s_axi_rvalid     (s_axi_rvalid),")
    lines.append(f"        .s_axi_rready     (s_axi_rready),")
    lines.append(f"        // M-side (to slaves)")
    lines.append(f"        .m_axi_awid       (m_axi_awid),")
    lines.append(f"        .m_axi_awaddr     (m_axi_awaddr),")
    lines.append(f"        .m_axi_awlen      (m_axi_awlen),")
    lines.append(f"        .m_axi_awsize     (m_axi_awsize),")
    lines.append(f"        .m_axi_awburst    (m_axi_awburst),")
    lines.append(f"        .m_axi_awlock     (m_axi_awlock),")
    lines.append(f"        .m_axi_awcache    (m_axi_awcache),")
    lines.append(f"        .m_axi_awprot     (m_axi_awprot),")
    lines.append(f"        .m_axi_awqos      (m_axi_awqos),")
    lines.append(f"        .m_axi_awregion   (m_axi_awregion),")
    lines.append(f"        .m_axi_awuser     (m_axi_awuser_nc),")
    lines.append(f"        .m_axi_awvalid    (m_axi_awvalid),")
    lines.append(f"        .m_axi_awready    (m_axi_awready),")
    lines.append(f"        .m_axi_wdata      (m_axi_wdata),")
    lines.append(f"        .m_axi_wstrb      (m_axi_wstrb),")
    lines.append(f"        .m_axi_wlast      (m_axi_wlast),")
    lines.append(f"        .m_axi_wuser      (m_axi_wuser_nc),")
    lines.append(f"        .m_axi_wvalid     (m_axi_wvalid),")
    lines.append(f"        .m_axi_wready     (m_axi_wready),")
    lines.append(f"        .m_axi_bid        (m_axi_bid),")
    lines.append(f"        .m_axi_bresp      (m_axi_bresp),")
    lines.append(f"        .m_axi_buser      (m_axi_buser_tieoff),")
    lines.append(f"        .m_axi_bvalid     (m_axi_bvalid),")
    lines.append(f"        .m_axi_bready     (m_axi_bready),")
    lines.append(f"        .m_axi_arid       (m_axi_arid),")
    lines.append(f"        .m_axi_araddr     (m_axi_araddr),")
    lines.append(f"        .m_axi_arlen      (m_axi_arlen),")
    lines.append(f"        .m_axi_arsize     (m_axi_arsize),")
    lines.append(f"        .m_axi_arburst    (m_axi_arburst),")
    lines.append(f"        .m_axi_arlock     (m_axi_arlock),")
    lines.append(f"        .m_axi_arcache    (m_axi_arcache),")
    lines.append(f"        .m_axi_arprot     (m_axi_arprot),")
    lines.append(f"        .m_axi_arqos      (m_axi_arqos),")
    lines.append(f"        .m_axi_arregion   (m_axi_arregion),")
    lines.append(f"        .m_axi_aruser     (m_axi_aruser_nc),")
    lines.append(f"        .m_axi_arvalid    (m_axi_arvalid),")
    lines.append(f"        .m_axi_arready    (m_axi_arready),")
    lines.append(f"        .m_axi_rid        (m_axi_rid),")
    lines.append(f"        .m_axi_rdata      (m_axi_rdata),")
    lines.append(f"        .m_axi_rresp      (m_axi_rresp),")
    lines.append(f"        .m_axi_rlast      (m_axi_rlast),")
    lines.append(f"        .m_axi_ruser      (m_axi_ruser_tieoff),")
    lines.append(f"        .m_axi_rvalid     (m_axi_rvalid),")
    lines.append(f"        .m_axi_rready     (m_axi_rready)")
    lines.append(f"    );")
    lines.append(f"")
    lines.append(f"endmodule")
    lines.append(f"")
    lines.append(f"`resetall")
    lines.append(f"")

    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Also print the decoded address map for human verification
# ---------------------------------------------------------------------------
def print_map():
    print("// Address map verification (from generator):")
    for port, name, base, aw, mask in SLAVES:
        top = base | ((1 << aw) - 1)
        print(f"//   M{port} {name:6s}  0x{base:08X} - 0x{top:08X}  ({1<<aw} B)"
              f"  mask={mask:02b}")
    print(f"//")
    print(f"// M_BASE_ADDR  = {hex_param(BASE_ADDR_VAL,  BASE_ADDR_BITS)}")
    print(f"// M_ADDR_WIDTH = {hex_param(ADDR_WIDTH_VAL, ADDR_WIDTH_BITS)}")
    print(f"// M_CONNECT    = {hex_param(CONN_VAL,       CONN_BITS)}")
    print()


if __name__ == "__main__":
    print_map()
    print(gen_wrapper())
