# Native SoC hardware status (Genesys 2)

## Status (2026-10-24)

CVA6 and NOEL-V run as native SoCs (no Scala/TileLink) on the repository's
own Genesys 2 shell (MIG DDR, repo UART/SD/Ethernet, clocks, pins). Build any
of them with `make CONFIG=<cfg> BOARD=genesys2 bitstream`, program with
`make ... program`. All run at 50 MHz. BOOM `rocket64x1` (v3 Medium, 50 MHz)
and `rocket64x1v4` (v4 Medium, 40 MHz) use the normal Rocket-chip flow and
were benchmarked alongside them (v4 Medium: bare-metal only, Linux hangs; see
below).

| CONFIG | SoC | Genesys 2 result |
| --- | --- | --- |
| `rocket64cva6` | CVA6 cv64a6_imafdc_sv39 (WT), DDR uncached | Bitstream OK; Linux reaches initrd, then systemd gives up ("Failed to start up manager") after ~13 min of uncached execution. Not investigated further. |
| `rocket64cva6hp` | CVA6 HPDcache WB, cached DDR, Zicbom + `dma-noncoherent` | **Linux login**, eth0 DHCP + ping, SD DMA checksum stable across drop_caches |
| `rocket64cva6hp2` | HP + dual issue, ALU bypass, 16-entry scoreboard, I$ 32 KiB/8-way, D$ 64 KiB/16-way, BTB 64, BHT 1024, RAS 4, hardware `time` CSR | **Linux login** (`/init` at 24 s vs 35 s on HP); 97.7k LUTs (48%), CPU clock slack +0.517 ns |
| `rocket64noelv` | NOEL-V GP (`cfg=16#300#`) | **Linux login**, eth0 + ping, SD DMA checksum OK |
| `rocket64noelvhp` | NOEL-V HP (`cfg=16#400#`) | **Linux login**, eth0 + ping, SD DMA checksum OK |
| `rocket64noelvhp2` | 2 x HP harts (SMP), BHT 512, 512 KiB L2C-Lite, 512 MiB DDR | For larger FPGAs: ~182k LUTs of SoC, does not fit the xc7k325t |
| `rocket64noelvhp2s` | hp2 with unused features removed (H, AIA, CFI, half FP, PMP 8, fewer triggers/counters) | Bitstream OK: 170.8k LUTs (84%), 220 BRAM, timing met; **SMP Linux login** (2 CPUs) |

### Root causes fixed on 2026-10-24

1. **CVA6 Linux hang at the first timer tick**: Vivado 2024.1 synthesizes
   the decoder's `irq_ctrl_i.mideleg[interrupt_cause[...]]` as 0, so
   delegated interrupts were taken in M-mode and in S-mode with SIE=0
   (re-trap forever at stvec). Proven on hardware with
   `scripts/native/hwtest/irq-sie0*.S` and in the netlist (`mideleg_q[5]` had
   no load in the decoder). Fix: `patches/cva6/decoder-irq-deleg.patch`
   (constant-index delegation bits). Patches in `patches/cva6/` (and per
   config, `patches/cva6/hp2/`) are applied to copies under
   `workspace/<cfg>/native-<board>/cva6-patched/`; the submodule is untouched.
2. **CVA6 PLIC off by one**: `rv_plic` maps `irq_sources_i[0]` to source 1;
   the subsystem had shifted the board IRQs by one, so SD interrupts ran the
   Ethernet handler (interrupt storm, boot stall after `PF_INET6`).
3. **NOEL-V hang in OpenSBI CSR probing**: GP/HP reset with
   `mnstatus.NMIE=0` (Smrnmi) and possibly `mstatus.MDT=1` (Smdbltrp); any
   M-mode trap then enters the critical-error state. The boot head
   (`src/main/resources/noelv/native/board-head.S`) sets NMIE and clears MDT.
4. CVA6 has no `time` CSR in any upstream config; OpenSBI emulates every
   `rdtime` (slow Linux boot, ~25 min to login). hp2 adds it in hardware
   (`patches/cva6/hp2/02-time-csr.patch`, `TimeCsr` parameter).

### Limits found

- NOEL-V L1 caches are at most 4 ways and virtually indexed, so a way cannot
  exceed 4 KiB; HP already uses 4 x 4 KiB. The BHT history is limited to 5
  bits (64-bit field) and the core uses the direct-mapped BTB (max 32).
- L2C-Lite has one memory BAR and the noelvsys ACLINT sits at 0xB000_0000,
  so configs with the L2 expose 512 MiB of DDR.
- Upstream CVA6 has no multi-core coherence in this AXI flow; Culsans and
  OpenPiton exist but use their own CVA6 fork / cache system and were not
  integrated (decision 2026-10-24).

### Debug notes

- CVA6: xsdb over the onboard JTAG (`hw_server` on tcp:3121), targets
  "RISC-V" (system bus) and "Hart #0". Bare-metal tests: `scripts/native/hwtest`.
- NOEL-V: GRMON 4.1.2 eval, `grmon -digilent -jtagserial 200300BB2DF7 -ni -nb`
  (stop `hw_server` first). Killing GRMON while the CPU runs under `go`
  leaves `mtime` frozen.
- CoreMark harness: `scripts/native/coremark` (bare-metal: `run_coremark.py`,
  Linux: `linux_bench.py`); results in `workspace/hw-validation/coremark.csv`.

### CoreMark/MHz (2026-10-24)

Best of 5 validated runs per build, 4000 iterations, on the Genesys 2.
Bare-metal uses GCC 15.1 (`/tools/riscv`); Linux uses the Debian-hosted
cross GCC 11.4, static, posix port. The two compilers differ, so compare
cores within a column, not bare-metal against Linux.

| Core (CONFIG, MHz) | Bare-metal base | Bare-metal opt | Linux base | Linux opt |
| --- | --- | --- | --- | --- |
| CVA6 HP (`rocket64cva6hp`, 50) | 2.369 | 2.772 (opt) | 1.955 | 2.046 (opt2) |
| CVA6 HP2 (`rocket64cva6hp2`, 50) | 3.233 | 3.905 (opt2) | 2.839 | 3.333 (opt2) |
| NOEL-V HP (`rocket64noelvhp`, 50) | 3.591 | 4.653 (opt) | 3.148 | 3.537 (opt) |
| NOEL-V HP2s (`rocket64noelvhp2s`, 50, 1 hart) | 3.569 | 4.650 (opt) | 3.185 | 3.731 (opt) |
| BOOM v3 Medium (`rocket64x1`, 50) | 4.773 | 4.654 (opt4) | 3.874 | 4.158 (opt2) |
| BOOM v4 Medium (`rocket64x1v4`, 40) | 4.328 | 4.597 (opt2) | - (Linux hangs) | - |

Normalized to BOOM v3 Medium (`rocket64x1`) = 1.00 on the same column:

| Core | Bare-metal base | Bare-metal opt | Linux base | Linux opt |
| --- | --- | --- | --- | --- |
| CVA6 HP | 0.50 | 0.60 | 0.50 | 0.49 |
| CVA6 HP2 | 0.68 | 0.84 | 0.73 | 0.80 |
| NOEL-V HP | 0.75 | 1.00 | 0.81 | 0.85 |
| NOEL-V HP2s (1 hart) | 0.75 | 1.00 | 0.82 | 0.90 |
| BOOM v3 Medium | 1.00 | 1.00 | 1.00 | 1.00 |
| BOOM v4 Medium | 0.91 | 0.99 | - | - |

Per flag set (bare metal; opt3/opt4 were run on BOOM only):

| Core | base | opt | opt2 | opt3 | opt4 |
| --- | --- | --- | --- | --- | --- |
| CVA6 HP | 2.369 | 2.772 | 2.684 | - | - |
| CVA6 HP2 | 3.233 | 3.778 | 3.905 | - | - |
| NOEL-V HP | 3.591 | 4.653 | 4.636 | - | - |
| NOEL-V HP2s | 3.569 | 4.650 | 4.643 | - | - |
| BOOM v3 Medium | 4.773 | 4.634 | 4.644 | 4.523 | 4.654 |
| BOOM v4 Medium | 4.328 | 4.218 | 4.597 | 4.107 | 4.248 |

Linux per flag set: CVA6 HP 1.955 / 1.944 / 2.046, CVA6 HP2 2.839 / 3.195 /
3.333, NOEL-V HP 3.148 / 3.537 / 3.495, NOEL-V HP2s 3.185 / 3.731 / 3.669,
BOOM v3 3.874 / 4.083 / 4.158 (base / opt / opt2).

BOOM results were measured with BOOM master 58ef2720; the committed stable
pin b4283f3 differs in BOOM v3 only in exception-path fixes.

- base: `-O2 -march=rv64imafdc` (same code for every core).
- opt / opt2: `-O3 -flto` with unrolling/inlining, the core's real ISA
  (Zba/Zbb/Zbs/Zbc/Zicond/Zcb on CVA6 and NOEL-V) and two `-mtune` models;
  opt3 is plain `-O3 -flto`, opt4 is `-O2 -flto` + tune2. The column shows
  the best of opt..opt4 (`scripts/native/coremark/summarize.py`).
- BOOM v4 Medium does not boot Linux. This is an upstream BOOM v4 bug and v4
  is supported here for bare metal only. Boots stop at about 22 s, right after
  "Freeing initrd memory", when the first dynamically linked process starts
  (`modprobe` from the initrd, or any dynamic binary from a test initramfs;
  static binaries run fine). The hart cannot be halted over JTAG, but the
  system bus still answers (DDR, UART, CLINT). An ILA capture at the hang
  shows the L1 and L2 caches idle with empty TileLink queues, the ROB full
  of uncommitted entries, and the PTW answering the same kind of request
  from its L2 TLB every 5 cycles. That points to a livelock between the
  v4 LSU TLB-miss retry queue and the small data TLB (2 sectored entries in
  the Medium config), not a bus or cache deadlock. Reproduced on BOOM
  master 58ef2720 and on the stable pin b4283f3; the core is not patched
  (policy: core bugs are handled by version choice, not by editing the
  core). Bare-metal CoreMark runs fine.
- On BOOM, GCC 15's aggressive flags lose to plain `-O2` on bare metal.
- HP2s SMP: two concurrent copies under Linux give ~7.05 CoreMark/MHz in
  total (1.89x one copy).
- Raw data is written locally to `workspace/hw-validation/coremark.csv` (not
  committed); `scripts/native/coremark/summarize.py` builds this table from it.
