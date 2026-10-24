// Cached store, uncached UART status read, cached load.
#include "common.inc"
loop:
  sd   s4, 0(sp)
  lw t0, 8(s2)
  ld   t3, 0(sp)
  bne  t3, s4, bad          // stale/wrong data
  addi s4, s4, 1
  addi sp, sp, -64
  li   t4, 0x80300800
  bgt  sp, t4, loop
  li   sp, 0x80380000
  j    loop
bad:
  j bad
.align 4
park:
  j park
