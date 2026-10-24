// [variant: no mret delivery; S code toggles SIE] OpenSBI/Linux timer hand-off: M-timer -> M handler clears MTIE, sets
// mip.STIP, mret -> immediate S-timer trap (delegated) -> S handler ecalls
// "set_timer" (M clears STIP, re-arms mtimecmp, sets MTIE) -> sret.
// S main loop polls the UART like the kernel console.
// Pass: s4 (S loop), s5 (S timer traps), s6 (M timer irqs) all count up.
.option norvc
.globl _start
_start:
  li   sp, 0x80380000           # M stack
  li   s9, 0x80370000           # S stack (separate register use below)
  la   t0, mtrap
  csrw mtvec, t0
  la   t0, strap
  csrw stvec, t0
  li   s0, 0x0200bff8
  li   s1, 0x02004000
  li   s2, 0x60010000
  li   s4, 0
  li   s5, 0
  li   s6, 0
  li   t0, 0x20                 # delegate STIP to S
  csrw mideleg, t0
  li   t0, -1
  csrw pmpaddr0, t0
  li   t0, 0x1f
  csrw pmpcfg0, t0
  ld   t0, 0(s0)
  addi t0, t0, 1000
  sd   t0, 0(s1)
  li   t0, 0xa0                 # MTIE | STIE
  csrw mie, t0
  la   t0, sloop
  csrw mepc, t0
  li   t0, 0x1800
  csrc mstatus, t0
  li   t0, 0x0800               # MPP = S
  csrs mstatus, t0
  mret
sloop:
  csrsi sstatus, 2              # enable S interrupts from S-mode code
  csrci sstatus, 2              # ...and disable again
  lw   t1, 8(s2)
  andi t1, t1, 8
  bnez t1, 1f
  li   t2, 0x2e
  sw   t2, 4(s2)
1:
  addi s4, s4, 1
  j    sloop

.align 4
strap:                          # S-mode timer handler (kernel)
  csrr t5, scause
  bgez t5, sbad
  addi s5, s5, 1
  li   a7, 0                    # "set_timer"
  ecall
  li   t5, 0x20
  csrc sstatus, t5
  sret
sbad:
  j sbad

.align 4
mtrap:                          # M-mode (OpenSBI)
  csrr t6, mcause
  bltz t6, m_irq
  li   t5, 9                    # ecall from S
  bne  t6, t5, mbad
  li   t5, 0x20                 # clear STIP
  csrc mip, t5
  ld   t5, 0(s0)
  addi t5, t5, 1000
  sd   t5, 0(s1)
  li   t5, 0x80                 # MTIE back on
  csrs mie, t5
  csrr t5, mepc
  addi t5, t5, 4
  csrw mepc, t5
  mret
m_irq:
  addi s6, s6, 1
  li   t5, 0x80                 # MTIE off
  csrc mie, t5
  li   t5, 0x20                 # STIP on
  csrs mip, t5
  mret
mbad:
  j mbad
