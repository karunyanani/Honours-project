/* =============================================================================
 * soc.ld  –  Linker script for Secure Communication Gateway SoC
 *
 * Memory map (from soc_defines.vh):
 *   IMEM : 0x0000_0000  64 KB  (instruction memory – execute from here)
 *   DMEM : 0x0001_0000  64 KB  (data/stack/heap)
 *
 * Section layout:
 *   IMEM : .text.startup  (reset vector at address 0)
 *          .text          (all other code)
 *          .rodata        (read-only data – kept in IMEM to save DMEM)
 *   DMEM : .data          (initialised globals – copied from IMEM LMA)
 *          .bss           (zero-initialised globals – zeroed by startup.S)
 *          heap           (grows upward from end of BSS)
 *          stack          (grows downward from top of DMEM)
 *
 * Stack: 4 KB reserved at the top of DMEM.
 * =============================================================================
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rwx) : ORIGIN = 0x00010000, LENGTH = 64K
}

/* Stack size reservation */
_stack_size = 4K;

SECTIONS
{
    /* -----------------------------------------------------------------------
     * .text  –  Instruction memory
     * --------------------------------------------------------------------- */
    .text :
    {
        /* Reset vector MUST be at address 0 */
        KEEP(*(.text.startup))

        /* All other code */
        *(.text)
        *(.text.*)

        /* Read-only data lives in IMEM (no separate .rodata region needed) */
        . = ALIGN(4);
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)

        . = ALIGN(4);
        _etext = .;                 /* end of code+rodata in IMEM */
    } > IMEM

    /* -----------------------------------------------------------------------
     * .data  –  Initialised data in DMEM, loaded from IMEM
     * LMA = load address (IMEM, after .text)
     * VMA = run address (DMEM)
     * --------------------------------------------------------------------- */
    .data : AT(_etext)
    {
        _data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > DMEM

    /* -----------------------------------------------------------------------
     * .bss  –  Zero-initialised data (no LMA; startup.S zeros it)
     * --------------------------------------------------------------------- */
    .bss :
    {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > DMEM

    /* -----------------------------------------------------------------------
     * Heap – starts right after BSS, grows upward
     * --------------------------------------------------------------------- */
    _heap_start = __bss_end;

    /* -----------------------------------------------------------------------
     * Stack – top of DMEM, grows downward
     * 4 KB reserved.
     * --------------------------------------------------------------------- */
    _stack_top  = ORIGIN(DMEM) + LENGTH(DMEM) - 4;   /* word-aligned */
    _stack_base = _stack_top - _stack_size;

    /* -----------------------------------------------------------------------
     * Trap vector section (placed after .text in IMEM)
     * --------------------------------------------------------------------- */
    .trap :
    {
        KEEP(*(.text.trap))
    } > IMEM

    /* -----------------------------------------------------------------------
     * Discard debug/exception table sections
     * --------------------------------------------------------------------- */
    /DISCARD/ :
    {
        *(.eh_frame)
        *(.note*)
        *(.comment)
    }
}

/* Provide symbols used by startup.S */
PROVIDE(_start       = 0x00000000);
PROVIDE(_trap_vector = _etext);
