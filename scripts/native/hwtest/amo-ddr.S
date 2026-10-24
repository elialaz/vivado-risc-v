// AMOs and LR/SC on cached DDR (Linux spinlocks/atomics), results checked.
// Pass: s4 keeps counting; s6 = step that failed (0 = none).
#include "common.inc"
  li   s3, 0x80600000
  li   s6, 0
loop:
  addi s7, s3, 8
  addi s8, s3, 4
  sd   zero, 0(s3)
  sd   zero, 8(s3)
  li   t0, 1
  li   s6, 1
  amoadd.w t1, t0, (s3)        # old 0, mem 1
  bnez t1, bad
  li   s6, 2
  amoadd.w t1, t0, (s3)        # old 1, mem 2
  li   t2, 1
  bne  t1, t2, bad
  li   s6, 3
  li   t0, 0x1234
  amoswap.d t1, t0, (s7)      # old 0
  bnez t1, bad
  li   s6, 4
  ld   t1, 8(s3)
  bne  t1, t0, bad
  li   s6, 5
  lw   t1, 0(s3)
  li   t2, 2
  bne  t1, t2, bad
  li   s6, 6
2:
  lr.d t1, (s7)
  addi t1, t1, 1
  sc.d t2, t1, (s7)
  bnez t2, 2b
  ld   t1, 8(s3)
  li   t2, 0x1235
  bne  t1, t2, bad
  li   s6, 7
  li   t0, 0x100
  amoor.w t1, t0, (s8)
  lw   t1, 4(s3)
  bne  t1, t0, bad
  li   s6, 0
  addi s4, s4, 1
  addi s3, s3, 64
  li   t4, 0x80680000
  blt  s3, t4, loop
  li   s3, 0x80600000
  j    loop
bad:
  j bad
.align 4
park:
  j park
