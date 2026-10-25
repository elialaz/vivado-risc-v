# Hardware status of the added cores (Genesys 2)

## Status (2026-10-25)

CVA6, NOEL-V, VexiiRiscv and NaxRiscv run as native SoCs (no Scala/TileLink
from this repository) on the repository's own Genesys 2 shell (MIG DDR, repo
UART/SD/Ethernet, clocks, pins). BOOM and Shuttle use the normal Rocket Chip
flow. Build any of them with `make CONFIG=<cfg> BOARD=genesys2 bitstream`,
program with `make ... program`. All run at 50 MHz except BOOM v4 Medium
(40 MHz). The same SD card image boots every configuration.

| CONFIG | SoC | Genesys 2 result |
| --- | --- | --- |
| `rocket64cva6` | CVA6 cv64a6_imafdc_sv39 (WT), DDR uncached | Bitstream OK; Linux reaches initrd, then systemd gives up ("Failed to start up manager") after ~13 min of uncached execution. Not investigated further. |
| `rocket64cva6hp` | CVA6 HPDcache WB, cached DDR, Zicbom + `dma-noncoherent` | **Linux login**, eth0 DHCP + ping, SD DMA checksum stable across drop_caches |
| `rocket64cva6hp2` | HP + dual issue, ALU bypass, 16-entry scoreboard, I$ 32 KiB/8-way, D$ 64 KiB/16-way, BTB 64, BHT 1024, RAS 4, hardware `time` CSR | **Linux login** (`/init` at 24 s vs 35 s on HP); 97.7k LUTs (48%), CPU clock slack +0.517 ns |
| `rocket64noelv` | NOEL-V GP (`cfg=16#300#`) | **Linux login**, eth0 + ping, SD DMA checksum OK |
| `rocket64noelvhp` | NOEL-V HP (`cfg=16#400#`) | **Linux login**, eth0 + ping, SD DMA checksum OK |
| `rocket64noelvhp2` | 2 x HP harts (SMP), BHT 512, 512 KiB L2C-Lite, 512 MiB DDR | For larger FPGAs: ~182k LUTs of SoC, does not fit the xc7k325t |
| `rocket64noelvhp2s` | hp2 with unused features removed (H, AIA, CFI, half FP, PMP 8, fewer triggers/counters) | Bitstream OK: 170.8k LUTs (84%), 220 BRAM, timing met; **SMP Linux login** (2 CPUs) |
| `rocket64shuttle` | Shuttle 2-wide in-order (UC Berkeley), Rocket Chip tile, broadcast coherence | **Linux login**; 76.3k LUTs (37%), 35.5 BRAM |
| `rocket64shuttlehp` | Shuttle 2-wide, BTB 64 / RAS 8 / BHT 1024, 512 KiB L2, 256-bit memory edge | **Linux login**; 89.9k LUTs (44%), 163.5 BRAM, timing met |
| `rocket64shuttlehp2` | 2 x Shuttle HP | 138.8k LUTs (68%), 192.5 BRAM, timing met; **Linux login with `maxcpus=1`**; with both harts the boot hangs (see below) |
| `rocket64vexii` | VexiiRiscv single issue, LiteX "debian" options (4-way 16 KiB L1s, BTB/RAS/gshare, reduced-accuracy FPU), 128 KiB L2 | **Linux login**, eth0 DHCP + ping, SD DMA checksum stable; 31.5k LUTs (15%), 84 BRAM |
| `rocket64vexiihp` | VexiiRiscv dual issue with every `--max-ipc` option, Zba/Zbb/Zbs, 8-way 32 KiB L1s, full FPU, 256 KiB L2 | **Linux login** + the same checks; 45.2k LUTs (22%), 141 BRAM |
| `rocket64vexiihp2` | 2 x VexiiRiscv HP, coherent | **SMP Linux login** (2 CPUs); 70.1k LUTs (34%), 188 BRAM |
| `rocket64nax` | NaxRiscv out-of-order, 2 decode / 2 ALU, RV64GC, 128 KiB L2 | Bitstream OK: 46.4k LUTs (23%), 79.5 BRAM; Linux: see below |

Build provenance: the results for `rocket64cva6hp2`, `rocket64noelvhp2s`,
`rocket64shuttlehp`, `rocket64shuttlehp2`, `rocket64vexiihp2`,
`rocket64nax`, `rocket64x1` and `rocket64x1v4` come from bitstreams built
from the current sources and pins. The other rows were measured on
bitstreams built before the last source changes, which only added features
for the newer configs (CVA6 `time` CSR option, multi-hart NOEL-V device
tree, shared SpinalHDL wrapper, Shuttle 2379b9b, BOOM b4283f3). Those builds
were removed to save disk; rebuild them before re-measuring.

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

### New cores (2026-10-25)

- **Shuttle** (`generators/shuttle`, Rocket Chip flow). The first pin
  (b37cf7c, the revision Chipyard paired with this rocket-chip) hung in
  Linux; e37ce14 has D-cache/writeback fixes and boots. The pin is now
  2379b9b, which also builds the D-cache from the configured parameters
  (before a653f9c the tile used default D-cache parameters while the rest of
  the tile saw the configured ones). HP findings: with 3-wide retire
  (Chipyard's `Shuttle3WideConfig`) Linux panics about 20 s into boot with
  "stack-protector: Kernel stack is corrupted in
  `__riscv_compat_sys_epoll_pwait2`", reproducibly, also with `maxcpus=1`
  and with the base configuration plus 3-wide retire alone; larger L1s
  (16-way I$, 8-way D$, 8 MSHRs) were ruled out. HP therefore stays 2-wide.
  With 2-wide retire, the dual-core `rocket64shuttlehp2` still hangs at a
  random point of the boot (2.9 s, 38 s), while the same bitstream boots to
  login with `maxcpus=1`: Shuttle multi-core coherence (with the inclusive
  L2) is not stable on this revision, so the dual-core HP is bare metal
  only. Bare-metal CoreMark is fine in every variant. A 16-byte fetch does not elaborate
  (TLB response type mismatch in `ShuttleFrontend`, also on Shuttle master).
  JTAG debug does not enumerate on these pins (fixed upstream only together
  with a newer rocket-chip).
- **VexiiRiscv** (`generators/vexiiriscv`, LiteX pin 235753e2). The SoC is
  VexiiRiscv's own LiteX generator output (`vexiiriscv.soc.litex.SocGen`);
  `src/main/resources/spinal/SpinalBoardWrapper.v` adds the repository boot
  ROM on the peripheral bus at 0x10000, maps board IO at 0x6000_0000, rebases
  DDR for MIG and adapts the coherent DMA port (4-bit IDs) to the board's
  8-bit DMA fabric. Linux worked on the first bitstream. The post-synthesis
  estimates leave +14.3 ns (base) and +10.7 ns (HP) of slack at 50 MHz, so
  higher clocks are likely possible.
- **NaxRiscv** (`generators/naxriscv`, pin ba63ee6d, the revision LiteX
  pinned from 2024.08 to 2025.12). Same wrapper. NaxRiscv's MMU faults on any
  address outside its io and memory ranges, so the CLINT/PLIC window
  (0xF000_0000-0xFFFF_FFFF) is passed as an io region; on the newer pin
  9f452d5 the boot ROM also needs to be in `memRange`. Bare metal and
  OpenSBI/U-Boot work. Linux 7.0 stops in `memmap_init` with "Unable to
  handle kernel paging request at ffffffc500400034" (store fault on the
  third 2 MiB vmemmap page) on both pins; the page tables in memory are
  correct (checked over JTAG), so the fault comes from the core's MMU. Not
  patched (policy); left as bare metal only.

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
- VexiiRiscv / NaxRiscv: their RISC-V debug TAP sits behind the BSCAN-to-JTAG
  bridge (`debug_bridge` + `bscan2jtag`). hw_server lists it as an unknown
  device (IDCODE 0x10002fff) and xsdb does not attach a RISC-V target, so
  `scripts/native/riscv-dmi.tcl` drives the debug module with raw JTAG scans:
  `xsdb scripts/native/riscv-dmi.tcl status|halt|resume|read <addr>`.
- CoreMark harness: `scripts/native/coremark` (bare-metal: `run_coremark.py`,
  Linux: `linux_bench.py`); results in `workspace/hw-validation/coremark.csv`.
  The `uboot` backend wakes U-Boot with Ctrl-C, not Enter: an empty line
  makes U-Boot repeat the last command (it re-ran the previous `go`).

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
| Shuttle (`rocket64shuttle`, 50) | 3.011 | 3.848 (opt2) | 2.666 | 3.159 (opt2) |
| Shuttle HP (`rocket64shuttlehp2`, 50, 1 hart) | 3.022 | 3.883 (opt2) | 2.719 | 3.266 (opt2) |
| VexiiRiscv (`rocket64vexii`, 50) | 2.382 | 2.752 (opt2) | 2.079 | 2.508 (opt2) |
| VexiiRiscv HP (`rocket64vexiihp`, 50) | 3.545 | 4.535 (opt2) | 3.189 | 3.802 (opt) |
| VexiiRiscv HP2 (`rocket64vexiihp2`, 50, 1 hart) | - | - | 3.188 | 3.819 (opt2) |
| NaxRiscv (`rocket64nax`, 50) | 4.102 | 4.249 (opt2) | - (Linux faults) | - |

Normalized to BOOM v3 Medium (`rocket64x1`) = 1.00 on the same column:

| Core | Bare-metal base | Bare-metal opt | Linux base | Linux opt |
| --- | --- | --- | --- | --- |
| CVA6 HP | 0.50 | 0.60 | 0.50 | 0.49 |
| CVA6 HP2 | 0.68 | 0.84 | 0.73 | 0.80 |
| NOEL-V HP | 0.75 | 1.00 | 0.81 | 0.85 |
| NOEL-V HP2s (1 hart) | 0.75 | 1.00 | 0.82 | 0.90 |
| BOOM v3 Medium | 1.00 | 1.00 | 1.00 | 1.00 |
| BOOM v4 Medium | 0.91 | 0.99 | - | - |
| Shuttle | 0.63 | 0.83 | 0.69 | 0.76 |
| Shuttle HP | 0.63 | 0.83 | 0.70 | 0.79 |
| VexiiRiscv | 0.50 | 0.59 | 0.54 | 0.60 |
| VexiiRiscv HP | 0.74 | 0.97 | 0.82 | 0.91 |
| NaxRiscv | 0.86 | 0.91 | - | - |

Per flag set (bare metal; opt3/opt4 were run on BOOM only):

| Core | base | opt | opt2 | opt3 | opt4 |
| --- | --- | --- | --- | --- | --- |
| CVA6 HP | 2.369 | 2.772 | 2.684 | - | - |
| CVA6 HP2 | 3.233 | 3.778 | 3.905 | - | - |
| NOEL-V HP | 3.591 | 4.653 | 4.636 | - | - |
| NOEL-V HP2s | 3.569 | 4.650 | 4.643 | - | - |
| BOOM v3 Medium | 4.773 | 4.634 | 4.644 | 4.523 | 4.654 |
| BOOM v4 Medium | 4.328 | 4.218 | 4.597 | 4.107 | 4.248 |
| Shuttle | 3.011 | 3.773 | 3.848 | - | - |
| Shuttle HP | 3.022 | 3.841 | 3.883 | - | - |
| VexiiRiscv | 2.382 | 2.592 | 2.752 | - | - |
| VexiiRiscv HP | 3.545 | 4.472 | 4.535 | - | - |
| NaxRiscv | 4.102 | 4.217 | 4.249 | - | - |

Linux per flag set: CVA6 HP 1.955 / 1.944 / 2.046, CVA6 HP2 2.839 / 3.195 /
3.333, NOEL-V HP 3.148 / 3.537 / 3.495, NOEL-V HP2s 3.185 / 3.731 / 3.669,
BOOM v3 3.874 / 4.083 / 4.158, Shuttle 2.666 / 3.048 / 3.159, Shuttle HP
(1 hart) 2.719 / 3.179 / 3.266, VexiiRiscv
2.079 / 2.345 / 2.508, VexiiRiscv HP 3.189 / 3.802 / 3.723, VexiiRiscv HP2
(1 hart) 3.188 / 3.787 / 3.819 (base / opt / opt2).

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
- SMP, two concurrent copies under Linux: NOEL-V HP2s ~7.05 CoreMark/MHz in
  total (1.89x one copy), VexiiRiscv HP2 7.61 (2.01x one copy).
- Shuttle, VexiiRiscv and NaxRiscv have no JTAG loading flow here, so their
  bare-metal images are S-mode builds (`-DSMODE`) loaded by U-Boot `loady`
  and started with `go` (`run_coremark.py --backend uboot`). The Shuttle
  bare-metal and Linux numbers were measured on Shuttle e37ce14; the pin then
  moved to 2379b9b, which changes only the D-cache parameter plumbing (no
  effect with the default caches) and front-end register timing.
- Raw data is written locally to `workspace/hw-validation/coremark.csv` (not
  committed); `scripts/native/coremark/summarize.py` builds this table from it.
