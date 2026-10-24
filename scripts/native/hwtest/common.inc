# Shared prologue: M-mode, trap vector parks the hart and keeps mcause/mepc.
.option norvc
.globl _start
_start:
  la   t0, park
  csrw mtvec, t0
  li   sp, 0x80380000
  li   s0, 0x0200bff8      # CLINT mtime
  li   s1, 0x02004000      # CLINT mtimecmp
  li   s2, 0x60010000      # board UART
  li   s4, 0               # pass counter
