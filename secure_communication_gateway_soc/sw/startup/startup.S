# =============================================================================
# startup.S  –  RISC-V RV32I Startup code for Secure Communication Gateway SoC
#
# Memory map (from soc_defines.vh):
#   Instruction memory : 0x0000_0000  (64 KB)
#   Data memory        : 0x0001_0000  (64 KB)
#
# Reset vector: 0x0000_0000  (must match cpu_axi_master.v RESET_VECTOR)
#
# This file:
#   1. Provides the reset handler at the reset vector (0x0).
#   2. Sets up the stack pointer at the top of DMEM.
#   3. Optionally zeroes the BSS section.
#   4. Calls main().
#   5. Provides a minimal trap vector (loop on fault/interrupt).
# =============================================================================

    .section .text.startup, "ax", @progbits
    .globl  _start
    .type   _start, @function

# ----------------------------------------------------------------------------
# Reset vector  –  placed at 0x00000000 by the linker script
# ----------------------------------------------------------------------------
_start:
    # Disable interrupts (RISC-V does not have a standard way at this level;
    # no CSR support in minimal stub, so just proceed)

    # ---- Set up stack pointer -----------------------------------------------
    # _stack_top is defined in the linker script as end of DMEM (0x0001_FFFC)
    la   sp, _stack_top

    # ---- Zero BSS section ----------------------------------------------------
    la   a0, __bss_start
    la   a1, __bss_end
1:
    bge  a0, a1, 2f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    1b
2:

    # ---- Call global constructors (C++ / GCC, if any) -----------------------
    # la   a0, __init_array_start
    # la   a1, __init_array_end
    # (skip for pure C projects)

    # ---- Jump to main -------------------------------------------------------
    call main

    # ---- If main returns, spin forever ---------------------------------------
_halt:
    j    _halt

    .size _start, . - _start

# ----------------------------------------------------------------------------
# Minimal exception / interrupt handler  –  loop on any trap
# Placed at _trap_vector; the CPU stub does not use CSRs so this is
# informational only.
# ----------------------------------------------------------------------------
    .section .text.trap, "ax", @progbits
    .globl  _trap_vector
    .type   _trap_vector, @function
_trap_vector:
    j    _trap_vector
    .size _trap_vector, . - _trap_vector

# ----------------------------------------------------------------------------
# Minimal standard memory functions
# ----------------------------------------------------------------------------
    .section .text, "ax", @progbits
    .globl  memcpy
    .type   memcpy, @function
memcpy:
    mv   t0, a0
1:  beqz a2, 2f
    lb   t1, 0(a1)
    sb   t1, 0(t0)
    addi t0, t0, 1
    addi a1, a1, 1
    addi a2, a2, -1
    j    1b
2:  ret
    .size memcpy, . - memcpy

    .globl  memset
    .type   memset, @function
memset:
    mv   t0, a0
1:  beqz a2, 2f
    sb   a1, 0(t0)
    addi t0, t0, 1
    addi a2, a2, -1
    j    1b
2:  ret
    .size memset, . - memset
