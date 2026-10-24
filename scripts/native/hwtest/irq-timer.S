// M-mode timer interrupt every 1000 mtime ticks while the main loop polls the
// UART and does cached DDR store/load (what Linux does at its first tick).
// Pass: s4 (loop) and s5 (interrupts) both keep counting, mcause stays 0x80..7.
.option norvc
.globl _start
_start:
  li   sp, 0x80380000
  la   t0, trap
  csrw mtvec, t0
  li   s0, 0x0200bff8
  li   s1, 0x02004000
  li   s2, 0x60010000
  li   s3, 0x80390000
  li   s4, 0
  li   s5, 0
  ld   t0, 0(s0)
  addi t0, t0, 1000
  sd   t0, 0(s1)
  li   t0, 0x80
  csrw mie, t0
  csrsi mstatus, 8
loop:
  lw   t1, 8(s2)
  andi t1, t1, 8
  bnez t1, 1f
  li   t2, 0x2e
  sw   t2, 4(s2)
1:
  sd   s4, 0(s3)
  ld   t3, 0(s3)
  bne  t3, s4, bad
  addi s4, s4, 1
  j    loop
bad:
  j bad
.align 4
trap:
  addi sp, sp, -32
  sd   t0, 0(sp)
  sd   t1, 8(sp)
  ld   t0, 0(s0)
  addi t0, t0, 1000
  sd   t0, 0(s1)
  addi s5, s5, 1
  ld   t1, 8(sp)
  ld   t0, 0(sp)
  addi sp, sp, 32
  mret
