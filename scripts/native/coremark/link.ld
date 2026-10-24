OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = LOAD_ADDR, LENGTH = 0x01000000 }
SECTIONS {
  .text : { *(.text.start) *(.text .text.*) } > ram
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > ram
  .data : { *(.data .data.* .sdata .sdata.*) } > ram
  .bss : { _bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(8); _bss_end = .; } > ram
  . = ALIGN(16);
  . += 0x40000;
  _stack_top = .;
  /DISCARD/ : { *(.eh_frame*) *(.comment) *(.riscv.attributes) }
}
