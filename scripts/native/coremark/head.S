// Bare-metal CoreMark start-up for the native and Rocket/BOOM SoCs.
// Loaded by the debugger at LOAD_ADDR (default 0x90000000, a DDR region the
// boot ROM never touches), entered in M-mode.
// With -DSMODE (cores without a usable debugger, e.g. Shuttle) the image is
// loaded and started from the U-Boot prompt instead (loady + go): it runs in
// S-mode under OpenSBI, keeps U-Boot's trap vector, and returns to U-Boot.
.section .text.start, "ax", @progbits
.globl _start
_start:
#ifdef SMODE
  la   t0, uboot_regs
  sd   ra, 0(t0)
  sd   sp, 8(t0)
  sd   gp, 16(t0)
  sd   tp, 24(t0)
  li   t0, (1 << 13)              // sstatus.FS = Initial (FPU on)
  csrs sstatus, t0
#else
#ifdef PARK_SECONDARY
  csrr t0, mhartid                // SMP SoCs: CoreMark runs on hart 0 only
  bnez t0, park
#endif
  la   t0, trap
  csrw mtvec, t0
#ifdef NOELV
  // NOEL-V: resumable NMIs on (else any trap stops the hart), double-trap
  // flag clear, L1 caches + DMA snooping on (a debugger reset clears them).
  li   t0, 8
  csrs 0x744, t0
  li   t0, 1
  slli t0, t0, 42
  csrc mstatus, t0
  li   t0, 0x1cf
  csrw 0x7c1, t0
#endif
  fence.i                         // drop stale lines from a previous image
  li   t0, (1 << 13)              // mstatus.FS = Initial (FPU on)
  csrs mstatus, t0
#endif
  la   sp, _stack_top
  la   t0, _bss_start
  la   t1, _bss_end
1:
  bgeu t0, t1, 2f
  sd   zero, 0(t0)
  addi t0, t0, 8
  j    1b
2:
  call main
  la   a0, done_msg
  call kputs
#ifdef SMODE
  fence.i
  la   t0, uboot_regs
  ld   ra, 0(t0)
  ld   sp, 8(t0)
  ld   gp, 16(t0)
  ld   tp, 24(t0)
  li   a0, 0
  ret
#endif
done:
#ifdef CBOM
  // CVA6 HP (write-back HPDcache, not snooped): write back and invalidate
  // the whole image + stack, so the debugger's next load (system bus, past
  // the caches) cannot be shadowed by stale lines.
  .option push
  .option arch, +zicbom
  la   t0, _start
  la   t1, _stack_top
3:
  cbo.flush (t0)
  addi t0, t0, CBOM_BLOCK
  bltu t0, t1, 3b
  .option pop
#endif
  fence.i
  ebreak                          // GRMON/xsdb see the halt
  wfi
  j    done

.align 4
trap:
  csrr a0, mcause
  li   t0, 3                      // breakpoint: no debugger caught it, park
  beq  a0, t0, park
  csrr a1, mepc
  csrr a2, mtval
  call report_trap
park:
  wfi
  j    park

#ifdef SMODE
.section .data
.align 3
uboot_regs:
  .dword 0, 0, 0, 0
#endif

.section .rodata
done_msg:
  .asciz "COREMARK_DONE"
