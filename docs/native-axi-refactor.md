# Native AXI SoC architecture

## Decision

CVA6 and NOEL-V are independent SoC-generator backends. They are not
Rocket-Chip tiles and they do not depend on Chisel, Diplomacy, TileLink, the
FIRRTL compiler, or the generated VHDL wrapper.

`CONFIG` selects the SoC backend and `BOARD` selects the FPGA shell:

| CONFIG family | SoC implementation |
| --- | --- |
| Rocket and BOOM | existing Scala/Rocket-Chip flow |
| `rocket64cva6` | repository-owned native AXI wrapper around official CVA6 RTL |
| `rocket64noelv` | repository-owned GRLIB wrapper around `noelvsys` and its native AHB/AXI path |

The historical names are retained so scripts and generated-image directories
do not change. They do not imply that CVA6 or NOEL-V is instantiated inside a
Rocket subsystem.

## Ownership boundary

The upstream repositories remain read-only submodules:

- `generators/cva6`
- `generators/grlib`
- `generators/riscv-boom`

All adaptation belongs to this repository under `src/main/resources`,
`board`, `scripts`, and the root build system. Do not carry integration edits
inside the CVA6 or GRLIB submodule worktrees.

## Board-facing contract

Each native SoC must provide:

- one AXI4 path to DDR;
- one AXI4 path to the repository board peripherals;
- a direct DDR path for SD and Ethernet DMA, with an explicit coherency policy;
- the common reset/clock-good handshake;
- external peripheral interrupts;
- a RISC-V Debug Specification compatible JTAG endpoint;
- a backend-composed boot ROM image and a matching generated device tree.

The Genesys 2 shell continues to own the MIG, repository `sdc_controller`,
repository Ethernet MAC/DMA, repository UART, XADC, clocks, resets,
constraints, and physical pins. This is a mandatory backend boundary, not
just a compatible interface: CVA6 and NOEL-V must not substitute the upstream
CVA6 SPI/LowRISC Ethernet blocks or GRLIB board peripherals. The shell must
not depend on Scala, Diplomacy, or TileLink for a native backend.

## CVA6 backend

Reuse the official CVA6 FPGA SoC building blocks rather than only the `ariane`
CPU module: CVA6, `dm_top`/`dmi_jtag`, CLINT, PLIC, AXI crossbar, and AXI ROM
adapter. The repository wrapper replaces the official board-specific DDR,
SPI, Ethernet, and UART endpoints with the common board AXI contract.

CVA6 already has an official Genesys 2 implementation. It is the reference
for reset, PMA, atomics, debug, and clock behavior, but its source is not
modified inside the submodule.

## NOEL-V backend

Use GRLIB's `noelvsys`, including its official interrupt/timer and debug
subsystems. External memory and board I/O leave the subsystem over GRLIB AHB
and are converted with GRLIB's `ahb2axi4b` bridge in repository-owned RTL
(DDR optionally through an `l2c_lite_axi4` L2). Board DMA enters the AHB bus
through `axi2ahb`, so the L1 snooping keeps it coherent. Debug is GRLIB
`ahbjtag` for GRMON. The boot ROM is an AHB slave generated from the same repository image
used by the other configurations.

The previous core-only `noelvcpu` wrapper is not the final native backend
because it duplicates services that `noelvsys` already provides.

## Boot-ROM and software contract

The ROM is layered rather than forced to be byte-identical between backends:

1. a backend-native reset/early-init stage performs the CPU and interconnect
   setup required by official CVA6 or GRLIB/NOEL-V behavior;
2. control passes to the repository common board-loader stage, which owns the
   UART diagnostics, repository SD controller, FAT lookup of `BOOT.ELF`, DTB
   selection, and the firmware handoff ABI.

The stages may be linked into one generated ROM image or chained as two
images. Backend-specific initialization must not fork the board memory map,
shared SD-card contents, payload format, or Linux userspace contract.

The boot sequence remains:

```text
native early init -> repository board loader -> SD BOOT.ELF -> OpenSBI -> U-Boot -> Linux
```

The DTS is backend-specific for CPU, interrupt, timer, and debug nodes, then
composed with the board DTS for DDR, UART, SD, and Ethernet. SD images and the
Linux payload remain shared when the resulting physical peripheral map is the
same.

SD and Ethernet are DMA masters outside the private CPU caches. Until a
coherent port is implemented, each backend must either mark DMA buffers
uncached or perform architecturally valid cache maintenance. Correctness is
required before re-enabling cached DDR.

## Migration status (2026-10-24)

Both native backends are implemented and pass on the Genesys 2 board shell:

| CONFIG | Linux on Genesys 2 | DMA policy |
| --- | --- | --- |
| `rocket64cva6` | reaches initrd; systemd gives up (uncached DDR, very slow) | DDR uncached |
| `rocket64cva6hp` | login, Ethernet, SD | cached; Zicbom + `dma-noncoherent` |
| `rocket64cva6hp2` | login, Ethernet, SD | same as HP |
| `rocket64noelv` | login, Ethernet, SD | cached; DMA snooped on AHB |
| `rocket64noelvhp` | login, Ethernet, SD | same as GP |
| `rocket64noelvhp2s` | SMP login (2 harts) | same, behind 512 KiB L2C-Lite |
| `rocket64noelvhp2` | not run (does not fit xc7k325t) | same as hp2s |

Build flow: each SoC is synthesized out of context as its own netlist
(`scripts/native/synth-cva6.tcl`, `synth-noelv.tcl`, and `synth-spinal.tcl`
for VexiiRiscv and NaxRiscv, which share `SpinalBoardWrapper`). The root Makefile then
builds the normal board project from `vivado.tcl` with that netlist in place
of the Rocket Chip HDL, so no SystemVerilog header or GRLIB library reaches
the board IP runs, and the project/bitstream/flash targets are shared with
Rocket and BOOM. `mk/native.mk` owns the per-backend
variables.

CVA6 source fixes are kept as patches (`patches/cva6/*.patch`, and per config
`patches/cva6/<cfg>/`) applied to copies under
`workspace/<cfg>/native-<board>/cva6-patched/`; the submodule is unchanged.
See `docs/hardware-status.md` for the root causes, limits, benchmarks and debug notes.

Remaining work: VCU118 shell for the same backends (including the full
`rocket64noelvhp2`), the CVA6 baseline systemd failure, the Shuttle HP and
NaxRiscv Linux failures (see `docs/hardware-status.md`). Added since: Shuttle
(Rocket Chip flow), VexiiRiscv and NaxRiscv (native, SpinalHDL). Planned
next, in this order: BlackParrot, OpenC910 (single core and SMP) and
XiangShan; the larger ones target VCU118.
