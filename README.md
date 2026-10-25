# vivado-risc-v

# AMD/Xilinx Vivado block designs for FPGA RISC-V SoC running Debian Linux distro.

This repository contains FPGA prototype of fully functional [RISC-V](https://riscv.org/) Linux server
with networking, online Linux package repository and daily package updates.
It includes scripts and sources to generate RISC-V SoC HDL, AMD/Xilinx Vivado project, FPGA bitstream, and bootable SD card.
The SD card contains [RISC-V Open Source Supervisor Binary Interface (OpenSBI)](https://github.com/riscv/opensbi), [U-Boot](https://github.com/u-boot/u-boot), [Linux kernel](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/) and [Debian root FS](https://wiki.debian.org/RISC-V).
Linux package repositories and regular updates are provided by [Debian](https://wiki.debian.org/RISC-V).
Over 90% of packages of the whole Debian collection are available for download.

Also can be used to run [bare-metal](https://github.com/eugene-tarassov/vivado-risc-v/tree/master/bare-metal) or RTOS software.

The project is used as reference design to validate RISC-V support in [Eclipse TCF](https://wiki.eclipse.org/TCF/RISC-V).

AMD/Xilinx tools support debugging of RISC-V software over JTAG.

# Prerequisites

## Hardware
[AMD VC707](https://www.xilinx.com/products/boards-and-kits/ek-v7-vc707-g.html) or
[AMD KC705](https://www.xilinx.com/products/boards-and-kits/ek-k7-kc705-g.html) or
[Digilent Genesys 2](https://digilent.com/reference/programmable-logic/genesys-2/start) or
[Digilent Nexys Video](https://digilent.com/reference/programmable-logic/nexys-video/start) or
[Digilent Nexys A7 100T](https://digilent.com/reference/programmable-logic/nexys-a7/start) or
[Digilent Arty A7 100T](https://digilent.com/reference/programmable-logic/arty-a7/start) board.

VC707 allows to prototype more powerful system: up to 8 64-bit RISC-V cores, up to 100MHz clock speed, 1GB RAM.

KC705 and Genesys 2 are as fast as VC707, but have slightly smaller FPGA - up to 4 cores.

Nexys Video is several times less expensive, academic discount is avaialble. It supports up to 2 cores, up to 50MHz clock speed.

Nexys A7 100T and Arty A7 100T are least expensive supported boards. They have small and slow FPGA, barely enough to run Linux on a single core RISC-V at 50MHz.

## Workstation
[Ubuntu 20.04 or 24.04 LTS](https://ubuntu.com/download/desktop) machine with min 32GB RAM.
sudo access required. Other versions or distributions of Linux are not supported in this repo.

Alternatively, a Windows 11 machine with Ubuntu on Windows can be used to run the tools, see [Running RISC-V tools on Windows](docs/ubuntu-on-windows.md).

## Software
Download and install AMD/Xilinx
[Vitis](https://www.xilinx.com/support/download/index.html/content/xilinx/en/downloadNav/vitis.html).
Supported Vitis versions are 2021.2, 2022.1, 2022.2, 2023.1, 2023.2, 2024.1, 2024.2, 2025.1, 2025.2, 2026.1.
Vitis installation includes Vivado Design Suite - there is no need to install Vivado separately.

Nexys Video, Nexys A7 100T and Arty A7 100T are supported by free version of Vivado. KC705, VC707 and Genesys 2 require Vivado license.

If using a Digilent board, install [Vivado Board Files for Digilent FPGA Boards](https://github.com/Digilent/vivado-boards).

### Extra requirements for the native configurations
The native CVA6, NOEL-V, VexiiRiscv and NaxRiscv SoCs are tested on Genesys 2
only (VCU118 support is in progress). Besides the packages from
`make apt-install`, they need:
* All submodules, recursively: `git submodule update --init --recursive`
  (CVA6 brings its own pinned dependencies; NOEL-V uses `generators/grlib`).
  VexiiRiscv and NaxRiscv need only their `ext/SpinalHDL` and `ext/rvls`
  submodules, which the build fetches itself; a recursive clone also pulls
  their large simulator submodules, which are not used.
* JDK 17 (already used by the Rocket flow) for the VexiiRiscv and NaxRiscv
  generators; they compile SpinalHDL on first use (a few minutes, about
  8 GB of JVM heap).
* `python3` (boot ROM generators) and `patch`.
* The repository RISC-V toolchain (`workspace/gcc`, built by the normal
  flow) for the boot ROMs.
* NOEL-V only, optional: [GRMON](https://www.gaisler.com/grmon) from
  Frontgrade Gaisler for JTAG debug through the on-chip AHBJTAG (the free
  evaluation version works; stop `hw_server` first), and
  [GHDL](https://github.com/ghdl/ghdl) only for the optional simulation
  scripts in `scripts/native/`.
* NOEL-V designs contain GRLIB GPL HDL; see the license note below before
  distributing NOEL-V bitstreams.

# Usage

## Checkout the repository, install required packages and update submodules
```
sudo apt install git make
git clone https://github.com/eugene-tarassov/vivado-risc-v.git
cd vivado-risc-v
make apt-install
make update-submodules
```

## Build FPGA bitstream
```
source /opt/Xilinx/2026.1/Vivado/settings64.sh
make CONFIG=rocket64b2 BOARD=nexys-video bitstream
```
For KC705, use `BOARD=kc705`

For VC707, use `BOARD=vc707`

For Genesys 2 use `BOARD=genesys2`

For Nexys A7 100T use `BOARD=nexys-a7-100t`

For Arty A7 100T use `BOARD=arty-a7-100t`

Some of available CONFIG values (See [rocket.scala](https://github.com/eugene-tarassov/vivado-risc-v/blob/master/src/main/scala/rocket.scala)):
* 64-bit big RISC-V cores, Linux capable:
  * `rocket64b1` - 1 core
  * `rocket64b2` - 2 cores
  * `rocket64b2l2` - 2 cores with 512KB level 2 cache
  * `rocket64b2gem` - 2 cores with 512KB level 2 cache and Gemmini accelerator
  * `rocket64b4l2w` - 4 cores with 512KB level 2 cache and wide 256-bit memory bus
  * `rocket64b4` - 4 cores
  * `rocket64b8` - 8 cores
* 64-bit Sonic BOOM cores, Linux capable:
  * `rocket64w1` - 1-wide Small BOOM, 1 core
  * `rocket64x1` - 2-wide superscalar Medium BOOM, 1 core
  * `rocket64y1` - 3-wide superscalar Large BOOM, 1 core
  * `rocket64z1` - 4-wide superscalar Mega BOOM, 1 core
* 64-bit BOOM v4 development cores (Medium: bare metal only, Linux hangs, see [docs/hardware-status.md](docs/hardware-status.md)):
  * `rocket64w1v4` - Small BOOM v4, 1 core
  * `rocket64x1v4` - Medium BOOM v4, 1 core
  * `rocket64y1v4` - Large BOOM v4, 1 core
  * `rocket64z1v4` - Mega BOOM v4, 1 core

  BOOM v4 is less mature than BOOM v3. Start with `rocket64w1v4` on
  resource-constrained boards such as Genesys 2.
* 64-bit Shuttle cores (UC Berkeley, Rocket Chip tile), Linux capable:
  * `rocket64shuttle` - 2-wide in-order superscalar, 1 core (Linux tested)
  * `rocket64shuttlehp` / `rocket64shuttlehp2` - larger branch predictors,
    512 KiB L2 and a wide memory bus, 1 / 2 cores (Linux tested on one core;
    the dual-core boot hangs, so `rocket64shuttlehp2` is bare metal only)
* Native 64-bit VexiiRiscv SoCs (SpinalHDL, VexiiRiscv's own LiteX SoC
  generator: coherent L2, CLINT, PLIC, debug TAP), 50 MHz on Genesys 2:
  * `rocket64vexii` - single issue, LiteX "debian" options, 128 KiB L2 (Linux tested)
  * `rocket64vexiihp` - dual issue with all IPC options, Zba/Zbb/Zbs,
    32 KiB L1s, 256 KiB L2 (Linux tested)
  * `rocket64vexiihp2` - 2 coherent HP harts (SMP Linux tested)
* Native 64-bit NaxRiscv SoC (SpinalHDL, out of order, NaxRiscv's LiteX SoC
  generator), 50 MHz on Genesys 2:
  * `rocket64nax` - 2 decode / 2 ALU, RV64GC, 128 KiB L2 (bare metal only:
    Linux faults in early boot, see [docs/hardware-status.md](docs/hardware-status.md))
* Native 64-bit CVA6 SoCs (official OpenHW Group submodule), attached
  directly to the board AXI fabric, 1 core, 50 MHz on Genesys 2:
  * `rocket64cva6` - cv64a6_imafdc_sv39 (write-through), DDR uncached (slow;
    Linux reaches the initrd but systemd fails)
  * `rocket64cva6hp` - HPDcache write-back, cached DDR, Zicbom DMA
    maintenance (Linux tested)
  * `rocket64cva6hp2` - HP plus dual issue, larger caches and predictors,
    hardware `time` CSR (Linux tested)
* Native 64-bit NOEL-V SoCs (pinned GRLIB `noelvsys`), 50 MHz on Genesys 2:
  * `rocket64noelv` - NOEL-V GP, dual issue, FPU, 1 core (Linux tested)
  * `rocket64noelvhp` - NOEL-V HP, 1 core (Linux tested)
  * `rocket64noelvhp2` - 2 HP harts, 512 KiB L2C-Lite; too large for Genesys 2
  * `rocket64noelvhp2s` - hp2 trimmed to fit Genesys 2, 2 harts (SMP Linux
    tested)

All SoCs use the normal build interface; only `CONFIG` changes the backend.
CVA6, NOEL-V, VexiiRiscv and NaxRiscv do not use the Scala/TileLink generator
path of this repository:
```
git submodule update --init --recursive
make CONFIG=rocket64cva6 BOARD=genesys2 vivado-project
make CONFIG=rocket64noelv BOARD=genesys2 vivado-project
```
Status, CoreMark/MHz results and debug notes for these SoCs are in
[docs/hardware-status.md](docs/hardware-status.md); the architecture is in
[docs/native-axi-refactor.md](docs/native-axi-refactor.md).
See [docs/generator-dependencies.md](docs/generator-dependencies.md) for pinned
upstreams, BOOM v4 configurations, and GRLIB integration details.
* 32-bit small RISC-V cores, Linux not supported:
  * `rocket32s1` - 1 core
  * `rocket32s2` - 2 cores
  * `rocket32s4` - 4 cores
  * `rocket32s8` - 8 cores
  * `rocket32s16` - 16 cores

FPGA utilization, LUTs:
* 32-bit small RISC-V: 10,800 + 6,100 per core
* 64-bit big RISC-V: 10,800 + 27,500 per core
* 2-wide superscalar Medium BOOM, 1 core, L2 cache: 148,500
* 3-wide superscalar Large BOOM, 1 core, L2 cache: 252,700

Genesys 2 (xc7k325t, 203,800 LUTs), whole design including the board shell:

| CONFIG | LUTs | Block RAM tiles |
| --- | --- | --- |
| `rocket64cva6` | 76,100 | 46.5 |
| `rocket64cva6hp` | 77,000 | 44.5 |
| `rocket64cva6hp2` | 97,700 | 74.5 |
| `rocket64noelv` | 87,500 | 30.5 |
| `rocket64noelvhp` | 98,700 | 58 |
| `rocket64noelvhp2s` (2 harts) | 170,800 | 220 |
| `rocket64w1v4` | 103,700 | 40.5 |
| `rocket64x1` | 170,500 | - |
| `rocket64x1v4` | 168,600 | 166.5 |
| `rocket64shuttle` | 76,300 | 35.5 |
| `rocket64shuttlehp` | 89,900 | 163.5 |
| `rocket64shuttlehp2` (2 cores) | 138,800 | 192.5 |
| `rocket64vexii` | 31,500 | 84 |
| `rocket64vexiihp` | 45,200 | 141 |
| `rocket64vexiihp2` (2 harts) | 70,100 | 188 |
| `rocket64nax` | 46,400 | 79.5 |

CoreMark/MHz measured on Genesys 2 (best of 5 validated runs; bare metal with
GCC 15.1, Linux user space with GCC 11.4, so compare within a column). "Rel."
is normalized to BOOM v3 Medium (`rocket64x1`) = 1.00 on the same flags.
"base" is `-O2 -march=rv64imafdc` for every core; "tuned" is the best of the
per-core `-flto` builds using the core's full ISA and `-mtune` models.

| CONFIG (MHz) | Bare metal base | Rel. | Bare metal tuned | Rel. | Linux base | Rel. | Linux tuned | Rel. |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `rocket64cva6hp` (50) | 2.369 | 0.50 | 2.772 | 0.60 | 1.955 | 0.50 | 2.046 | 0.49 |
| `rocket64cva6hp2` (50) | 3.233 | 0.68 | 3.905 | 0.84 | 2.839 | 0.73 | 3.333 | 0.80 |
| `rocket64noelvhp` (50) | 3.591 | 0.75 | 4.653 | 1.00 | 3.148 | 0.81 | 3.537 | 0.85 |
| `rocket64noelvhp2s` (50, 1 hart) | 3.569 | 0.75 | 4.650 | 1.00 | 3.185 | 0.82 | 3.731 | 0.90 |
| `rocket64x1` (50) | 4.773 | 1.00 | 4.654 | 1.00 | 3.874 | 1.00 | 4.158 | 1.00 |
| `rocket64x1v4` (40) | 4.328 | 0.91 | 4.597 | 0.99 | - | - | - | - |
| `rocket64shuttle` (50) | 3.011 | 0.63 | 3.848 | 0.83 | 2.666 | 0.69 | 3.159 | 0.76 |
| `rocket64shuttlehp2` (50, 1 hart) | 3.022 | 0.63 | 3.883 | 0.83 | 2.719 | 0.70 | 3.266 | 0.79 |
| `rocket64vexii` (50) | 2.382 | 0.50 | 2.752 | 0.59 | 2.079 | 0.54 | 2.508 | 0.60 |
| `rocket64vexiihp` (50) | 3.545 | 0.74 | 4.535 | 0.97 | 3.189 | 0.82 | 3.802 | 0.91 |
| `rocket64nax` (50) | 4.102 | 0.86 | 4.249 | 0.91 | - | - | - | - |

Running two copies under Linux, `rocket64noelvhp2s` reaches 7.05
CoreMark/MHz in total (1.89x one copy) and `rocket64vexiihp2` 7.61 (2.01x).
BOOM v4 Medium and NaxRiscv do not boot Linux (upstream core issues);
details, per-flag results and which rows were measured on builds from
earlier source revisions are in [docs/hardware-status.md](docs/hardware-status.md).

## Prepare the SD card
Use USB SD card reader to connect SD card to the workstation, and run:
```
./mk-sd-card
```
The script looks for USB memory device and asks confirmation before using it.
Make sure to confirm right SD card device - all old data will be erased.

## Booting Linux with QEMU (optional)
In some cases when Linux runs slow on the FPGA, especially designs with lower clock speeds or no ethernet access), it might be worth it to first install the dependencies quickly before running it on FPGA.

You can run the following:
```
./qemu/boot_qemu.sh
```

The script will check for the existance of a debian image under `debian-riscv64/` and run `./mk-sd-image` as needed. Then it will clone and make a suitable version of u-boot and opensbi for QEMU before finally booting Linux.

Once Linux has booted successfully on QEMU, you can also easily ssh and scp too:
```
ssh -p2222 debian@localhost
```

Once all this is done, you can make the sd card without making the image:
```
./mk-sd-card skip_mk_img
```

## Program the FPGA flash memory
```
source /opt/Xilinx/2026.1/Vivado/settings64.sh
make CONFIG=rocket64b2 BOARD=nexys-video flash
```
Alternatively, [flash memory can be programmed using Vivado GUI](docs/vivado-flash.md).

## Linux login

Host name: debian

User login and password: debian debian

Root login and password: root root

You can login over UART console:
```
sudo miniterm /dev/ttyUSB0 115200
```
or, after Linux boot, over SSH:
```
ssh debian@debian
```

## Modding the design (optional): adding a peripheral device

### Use Vivado Block Design to add an IP

Open Vivado:
```
source /opt/Xilinx/2026.1/Vivado/settings64.sh
make CONFIG=rocket64b2 BOARD=nexys-video vivado-gui
```
The IO block in the design is the best place to add device controllers, like GPIO.
See AXI Uartlite as an example, connect your IP to AXI interconnect and interrupts.
Validate and synthesize the design, but don't build bitstream yet - device tree and RISC-V HDL need to be updated first.

Close Vivado.

### Check the device driver is enabled in patches/linux.config

For example, for AMD/Xilinx GPIO, the config should contain line:
```
CONFIG_GPIO_XILINX=y
```

If necessary, change config, then rebuild Linux kernel and bootloader:
```
make linux bootloader
./mk-sd-image -r debian-riscv64-boot
```
Copy debian-riscv64-boot/extlinux directory to the SD card.

Note: don't change files in the project submodules: linux-stable, u-boot, opensbi or rocket-chip.
Such changes are lost when the project is rebuilt.

For details on AMD/Xilinx drivers, see [Linux Drivers](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18841873/Linux%2BDrivers).

### Edit board/nexys-video/bootrom.dts

Add device description in the "io-bus {...}" section.
For example, GPIO description can look like this:
```
        gpio: gpio@60030000 {
            #gpio-cells = <2>;
            compatible = "xlnx,xps-gpio-1.00.a";
            gpio-controller ;
            interrupt-parent = <&L2>;
            interrupts = <4>;
            reg = < 0x60030000 0x10000 >;
            xlnx,all-inputs = <0x0>;
            xlnx,dout-default = <0x0>;
            xlnx,gpio-width = <0x8>;
            xlnx,interrupt-present = <0x1>;
            xlnx,is-dual = <0>;
            xlnx,tri-default = <0xffffffff>;
        };
```
Make sure the description matches your design. In particular, check addresses and interrupt numbers.

### Rebuild FPGA bitstream
```
make CONFIG=rocket64b2 BOARD=nexys-video bitstream
```
Program the FPGA or the board flash memory.

# Prebuilt images

Prebuilt FPGA bitstream and SD card image are available in the [releases area](https://github.com/eugene-tarassov/vivado-risc-v/releases).

# Notes

Rocket Chip is used as RISC-V implementation: [UC Berkeley Architecture Research - Rocket Chip Generator](https://bar.eecs.berkeley.edu/projects/rocket_chip.html).
Rocket Chip is configured to include virtual memory, instruction and data caches, coherent interconnect, floating point, and all the relevant infrastructure.
See [rocket.scala](https://github.com/eugene-tarassov/vivado-risc-v/blob/master/src/main/scala/rocket.scala) for Rocket Chip configuration classes.

RISC-V SoC in this repo contains bootrom, which differ from original Rocket Chip bootrom.
The modified bootrom contains SD card boot loader and extended device tree.

RISC-V SoC in this repo contains DDR, UART, SD and Ethernet controllers.
DDR is provided by Vivado. UART, SD and Ethernet are open source Verilog.

SD controller implements SD HS (High Speed) specs, 25MB/s read/write speed.

Ethernet controller is based on [Verilog Ethernet Components](https://github.com/alexforencich/verilog-ethernet) project,
which is a collection of Ethernet-related components for gigabit, 10G, and 25G packet processing.

Linux kernel and U-Boot use device tree, which is stored in RISC-V bootrom in FPGA.
So, same SD card should boot OK on any board or RISC-V configuration.

Nexys Video and Nexys A7 boards can be configured to [load FPGA bitstream from SD card](https://reference.digilentinc.com/reference/programmable-logic/nexys-video/reference-manual#usb_host_and_micro_sd_programming).

The device tree contains Ethernet MAC address, which is not unique.
It might be necessary to rebuild bitstream with different MAC, see Makefile for details.

CVA6 ([OpenHW Group](https://github.com/openhwgroup/cva6), Solderpad/Apache)
and NOEL-V ([Frontgrade Gaisler GRLIB GPL](https://www.gaisler.com/grlib-ip-library))
are integrated as native SoCs on the same board shell, without Rocket Chip.
NOEL-V bitstreams include GRLIB GPL-2.0-only HDL and must follow the GPL when
distributed; see [LICENSE.md](LICENSE.md). Shuttle (UC Berkeley), VexiiRiscv
and NaxRiscv (SpinalHDL, MIT) are integrated the same way: Shuttle through
the Rocket Chip flow, the SpinalHDL cores as native SoCs.

If not using provided SD card image: the bootrom loads and executes boot.elf file from SD card DOS partition.
boot.elf is regular executable ELF, it can contain any software suitable for RISC-V RV64 M mode.
In case of Linux boot, boot.elf contains OpenSBI and U-Boot.

The Makefile creates Vivado project directory, e.g. workspace/rocket64b2/vivado-nexys-video-riscv.
You can open the project in Vivado GUI to see RISC-V SoC structure, make changes, add peripherals, rebuild the bitstream.
The SoC occupies portion of FPGA, leaving plenty of space for experiments and developing additional hardware.

RISC-V SoC in this repo uses BSCAN block to support both RISC-V debugging and FPGA access over same JTAG cable.
