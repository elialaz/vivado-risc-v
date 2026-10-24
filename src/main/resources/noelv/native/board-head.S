// SPDX-License-Identifier: GPL-2.0-only
// NOEL-V native reset stage followed by the repository common board loader.
//
// The ROM is linked at the repository-standard address 0x10000 (stock
// bootrom/bootrom.lds, DTB at 0x10080) and is mapped both there and at the
// NOEL-V reset vector 0xC0000000. Execution starts in the reset alias and
// jumps to the linked alias first.

#include "common.h"

#define MIP_MSIP          (1 << 3)

// Smrnmi / Smdbltrp
#define CSR_MNSTATUS      0x744
#define MNSTATUS_NMIE     (1 << 3)
#define MSTATUS_MDT_BIT   42

// NOEL-V cache control CSR: I/D cache enable (bits 3:0), I/D flush (7:6) and
// D-cache AHB snooping (8). Stock presets reset with all of these off; this
// is the value GRLIB's own NOEL-V boot PROM writes. Snooping keeps the board
// SD/Ethernet DMA coherent with the write-through L1 data cache.
#define CSR_CCTRL         0x7c1
#define CCTRL_ENABLE      0x1cf

// GRLIB ACLINT: PLIC trigger-type register for sources 0-31 (0 = level,
// 1 = edge; GRLIB resets to edge). The board interrupts are level signals
// on PLIC sources 5-12.
#define ACLINT_PLIC_IRQT  0xB0018100
#define BOARD_IRQ_MASK    0x00001FE0

.section .text.start, "ax", @progbits
.globl _start
_start:
  // Absolute (not PC-relative) jump from 0xC0000000 to the linked alias.
  .option push
  .option norelax
  lui t0, %hi(_nv_early_init)
  addi t0, t0, %lo(_nv_early_init)
  jr t0
  .option pop

.section .text, "ax", @progbits
_nv_early_init:
  // Smrnmi/Smdbltrp (GP and HP presets): the hart resets with
  // mnstatus.NMIE=0 and may have mstatus.MDT=1. Either one turns any M-mode
  // trap into a critical-error stop, and OpenSBI probes CSRs by trapping.
  li t0, MNSTATUS_NMIE
  csrs CSR_MNSTATUS, t0
  li t0, 1
  slli t0, t0, MSTATUS_MDT_BIT
  csrc mstatus, t0

  li t0, CCTRL_ENABLE
  csrw CSR_CCTRL, t0
  fence.i

  li t0, ACLINT_PLIC_IRQT
  lw t1, 0(t0)
  li t2, ~BOARD_IRQ_MASK
  and t1, t1, t2
  sw t1, 0(t0)
  fence rw, rw

  // Only hart 0 runs the loader. The others wait in _hang until OpenSBI
  // (HSM hart_start) raises their MSIP, then enter it at the start of RAM.
  csrr a0, mhartid
  bnez a0, _hang
  la a1, _dtb
  la s0, _ram

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
  beqz a0, _start
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
