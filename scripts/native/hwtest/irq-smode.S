// Linux-like: S-mode loop with Sv39 on polls the UART and does cached DDR
// store/load, while M-mode timer interrupts (OpenSBI-like handler that saves
// a 336-byte frame on the M stack) arrive every 1000 mtime ticks.
// Pass: s4 (S loop) and s5 (M interrupts) keep counting, no exception.
.option norvc
.globl _start
_start:
  li   sp, 0x80380000           # M stack
  la   t0, mtrap
  csrw mtvec, t0
  li   s0, 0x0200bff8
  li   s1, 0x02004000
  li   s2, 0x60010000
  li   s3, 0x80390000
  li   s4, 0
  li   s5, 0
  # Sv39 root page table at 0x80310000: identity 1 GiB pages for 0x0-0xbfffffff
  li   t0, 0x80310000
  li   t1, 0xcf                 # V R W X A D
  sd   t1, 0(t0)                # 0x00000000 -> 0x00000000 (CLINT)
  li   t2, 0x10000000           # (0x40000000 >> 12) << 10
  or   t2, t2, t1
  sd   t2, 8(t0)                # 0x40000000 (UART at 0x60010000)
  li   t2, 0x20000000           # (0x80000000 >> 12) << 10
  or   t2, t2, t1
  sd   t2, 16(t0)               # 0x80000000 DDR
  li   t1, 0x8000000000080310   # Sv39, root PPN 0x80310
  csrw satp, t1
  sfence.vma
  # PMP: allow S-mode everything (OpenSBI does the same for its domain)
  li   t0, -1
  csrw pmpaddr0, t0
  li   t0, 0x1f                 # NAPOT RWX
  csrw pmpcfg0, t0
  # arm timer, enable MTIE; M interrupts are always taken from S-mode
  ld   t0, 0(s0)
  addi t0, t0, 1000
  sd   t0, 0(s1)
  li   t0, 0x80
  csrw mie, t0
  # mret into S-mode at sloop
  la   t0, sloop
  csrw mepc, t0
  li   t0, 0x1800
  csrc mstatus, t0
  li   t0, 0x0800               # MPP = S
  csrs mstatus, t0
  mret
sloop:
  lw   t1, 8(s2)
  andi t1, t1, 8
  bnez t1, 1f
  li   t2, 0x2e
  sw   t2, 4(s2)
1:
  sd   s4, 0(s3)
  ld   t3, 0(s3)
  bne  t3, s4, sbad
  addi s4, s4, 1
  j    sloop
sbad:
  j sbad
.align 4
mtrap:
  addi sp, sp, -336
  sd   ra, 8(sp)
  sd   gp, 16(sp)
  sd   tp, 24(sp)
  sd   t0, 32(sp)
  sd   t1, 40(sp)
  sd   t2, 48(sp)
  sd   s3, 56(sp)
  sd   a0, 64(sp)
  sd   a1, 72(sp)
  sd   a2, 80(sp)
  sd   a3, 88(sp)
  sd   a4, 96(sp)
  sd   a5, 104(sp)
  sd   a6, 112(sp)
  sd   a7, 120(sp)
  sd   t3, 128(sp)
  sd   t4, 136(sp)
  sd   t5, 144(sp)
  sd   t6, 152(sp)
  csrr t0, mepc
  sd   t0, 256(sp)
  csrr t0, mstatus
  sd   t0, 264(sp)
  csrr t0, mcause
  sd   t0, 280(sp)
  ld   t1, 280(sp)
  bgez t1, mbad            # must be an interrupt
  ld   t0, 0(s0)
  addi t0, t0, 1000
  sd   t0, 0(s1)
  addi s5, s5, 1
  ld   t0, 256(sp)
  csrw mepc, t0
  ld   t0, 264(sp)
  csrw mstatus, t0
  ld   ra, 8(sp)
  ld   gp, 16(sp)
  ld   tp, 24(sp)
  ld   t0, 32(sp)
  ld   t1, 40(sp)
  ld   t2, 48(sp)
  ld   s3, 56(sp)
  ld   a0, 64(sp)
  ld   a1, 72(sp)
  ld   a2, 80(sp)
  ld   a3, 88(sp)
  ld   a4, 96(sp)
  ld   a5, 104(sp)
  ld   a6, 112(sp)
  ld   a7, 120(sp)
  ld   t3, 128(sp)
  ld   t4, 136(sp)
  ld   t5, 144(sp)
  ld   t6, 152(sp)
  addi sp, sp, 336
  mret
mbad:
  j mbad
