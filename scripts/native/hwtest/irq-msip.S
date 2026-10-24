// Machine software interrupt via CLINT msip in a loop.
.option norvc
.globl _start
_start:
  li   sp, 0x80380000
  la   t0, trap
  csrw mtvec, t0
  li   s0, 0x02000000      # msip
  li   s4, 0
  li   s5, 0
  li   t0, 0x8
  csrw mie, t0             # MSIE
  csrsi mstatus, 8
loop:
  li   t1, 1
  sw   t1, 0(s0)           # raise MSIP
  addi s4, s4, 1
  j    loop
.align 4
trap:
  addi sp, sp, -16
  sd   t0, 0(sp)
  sw   zero, 0(s0)         # clear MSIP
  addi s5, s5, 1
  ld   t0, 0(sp)
  addi sp, sp, 16
  mret
