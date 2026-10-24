// Synchronous trap (ecall) in a loop: handler counts in s5 and returns past it.
.option norvc
.globl _start
_start:
  li   sp, 0x80380000
  la   t0, trap
  csrw mtvec, t0
  li   s4, 0
  li   s5, 0
loop:
  ecall
  addi s4, s4, 1
  j    loop
.align 4
trap:
  addi sp, sp, -16
  sd   t0, 0(sp)
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  addi s5, s5, 1
  ld   t0, 0(sp)
  addi sp, sp, 16
  mret
