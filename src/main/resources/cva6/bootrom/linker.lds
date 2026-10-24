OUTPUT_ARCH("riscv")
ENTRY(_prog_start)

SECTIONS
{
    . = 0x00010000;

    .text.init : { *(.text.init) }
    .text : ALIGN(0x100) {
        *(.text.startup)
        *(.text .text.*)
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        *(.dtb)
    }
    .data : ALIGN(0x100) {
        *(.data .data.*)
        *(.sdata .sdata.*)
        *(.got .got.*)
    }
    ASSERT(. <= 0x00020000, "CVA6 Boot ROM exceeds its 64 KiB address window")

    .bss 0x80000000 (NOLOAD) : ALIGN(16) {
        _BSS_START_ = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(16);
        _BSS_END_ = .;
    }
    ASSERT(SIZEOF(.bss) <= 0x00002000, "CVA6 Boot ROM BSS exceeds its 8 KiB staging window")
}
