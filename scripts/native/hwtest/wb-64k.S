// CPU stores 64 KiB (2x the L1 D-cache) at 0x80500000; the runner then reads
// DDR over the debug bus (bypassing the cache): evicted lines must be there.
#include "common.inc"
  li   t0, 0x80500000
  li   t1, 0x80510000
  li   t2, 0xC0DE0000
1:
  sd   t2, 0(t0)
  addi t2, t2, 1
  addi t0, t0, 8
  blt  t0, t1, 1b
  li   s4, 1
2: j 2b
.align 4
park: j park
