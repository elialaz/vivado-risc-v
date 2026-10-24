// S-mode with sstatus.SIE=0 and a delegated, enabled, pending STIP from the
// start (no earlier trap). The privileged spec forbids taking it.
// Pass: s4 (S loop) counts, s5 (S traps) = 0, s6 (M traps) = 0.
.option norvc
.globl _start
_start:
  li   sp, 0x80380000
  la   t0, mtrap
  csrw mtvec, t0
  la   t0, strap
  csrw stvec, t0
  li   s4, 0
  li   s5, 0
  li   s6, 0
  li   s8, 0
  li   s9, 0
  li   t0, -1
  csrw pmpaddr0, t0
  li   t0, 0x1f
  csrw pmpcfg0, t0
  li   t0, 0x20                 # delegate STIP
  csrw mideleg, t0
  li   t0, 0x20                 # STIE only
  csrw mie, t0
  li   t0, 0x20                 # STIP pending
  csrs mip, t0
  li   t0, 0x2                  # SIE = 0
  csrc mstatus, t0
  la   t0, sloop
  csrw mepc, t0
  li   t0, 0x1800
  csrc mstatus, t0
  li   t0, 0x0800               # MPP = S
  csrs mstatus, t0
  mret
sloop:
  addi s4, s4, 1
  j    sloop

.align 6
strap:
  addi s5, s5, 1
  csrr s8, sstatus
  csrr s9, sepc
1:
  j    1b

.align 6
mtrap:
  addi s6, s6, 1
  csrr s7, mcause
1:
  j    1b
