// CVA6-native reset stage followed by the repository common board loader.

#include "common.h"

#define MIP_MSIP (1 << 3)

.section .text.start, "ax", @progbits
.globl _start
_start:
  csrr a0, mhartid
  la a1, _dtb
  la s0, _ram
  j _start_bootrom

_start_bootrom:
  li s2, 0
  sw s2, 0(s0)
  li sp, BOOTROM_MEM_END
  call main
  j _hang

.section .text.hang, "ax", @progbits
.globl _hang
_hang:
  csrr a0, mhartid
  la a1, _dtb
  la s0, _ram
  beqz a0, _start_bootrom
1:
  csrw mtvec, s0
  csrwi mie, MIP_MSIP
  wfi
  csrr t0, mip
  andi t0, t0, MIP_MSIP
  beqz t0, 1b
  ecall
  j 1b

.section .rodata.dtb, "a", @progbits
.globl _dtb
.align 5, 0
_dtb:
  .incbin DEVICE_TREE
