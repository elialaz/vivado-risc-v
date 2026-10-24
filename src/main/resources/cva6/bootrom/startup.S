# Repository-owned single-hart CVA6 reset and payload handoff.

.section .text.init
.option norvc
.globl _prog_start
_prog_start:
  li sp, 0x84000000
  call main
  csrr a0, mhartid
  la a1, _dtb
  li t0, 0x80000000
  jr t0

.section .dtb
.globl _dtb
.align 4, 0
_dtb:
  .incbin "cv64a6.dtb"
