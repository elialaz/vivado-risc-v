// OpenSBI-like trap frame: 42 doubleword stores to cold lines, then loads
// of the last-stored fields. Walks a fresh 336-byte frame each pass.
#include "common.inc"
  li   s3, 0x80700000
loop:
  addi s3, s3, -336
  sd   s4, 0(s3)
  sd   s4, 8(s3)
  sd   s4, 16(s3)
  sd   s4, 24(s3)
  sd   s4, 32(s3)
  sd   s4, 40(s3)
  sd   s4, 48(s3)
  sd   s4, 56(s3)
  sd   s4, 64(s3)
  sd   s4, 72(s3)
  sd   s4, 80(s3)
  sd   s4, 88(s3)
  sd   s4, 96(s3)
  sd   s4, 104(s3)
  sd   s4, 112(s3)
  sd   s4, 120(s3)
  sd   s4, 128(s3)
  sd   s4, 136(s3)
  sd   s4, 144(s3)
  sd   s4, 152(s3)
  sd   s4, 160(s3)
  sd   s4, 168(s3)
  sd   s4, 176(s3)
  sd   s4, 184(s3)
  sd   s4, 192(s3)
  sd   s4, 200(s3)
  sd   s4, 208(s3)
  sd   s4, 216(s3)
  sd   s4, 224(s3)
  sd   s4, 232(s3)
  sd   s4, 240(s3)
  sd   s4, 248(s3)
  sd   s4, 256(s3)
  sd   s4, 264(s3)
  sd   s4, 272(s3)
  sd   s4, 280(s3)
  sd   s4, 288(s3)
  sd   s4, 296(s3)
  sd   s4, 304(s3)
  sd   s4, 312(s3)
  sd   s4, 320(s3)
  sd   s4, 328(s3)
  ld   t3, 328(s3)
  bne  t3, s4, bad
  ld   t3, 280(s3)
  bne  t3, s4, bad
  ld   t3, 0(s3)
  bne  t3, s4, bad
  addi s4, s4, 1
  li   t4, 0x80400000
  bgt  s3, t4, loop
  li   s3, 0x80700000
  j    loop
bad:
  j bad
.align 4
park:
  j park
