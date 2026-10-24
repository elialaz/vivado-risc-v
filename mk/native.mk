# Native (non-Scala) SoC backends: CVA6 and NOEL-V.
#
# Each backend is synthesized on its own into an out-of-context netlist
# (NATIVE_SOC_DCP). The root Makefile then builds the normal board project
# from vivado.tcl, with the netlist in place of the Rocket Chip HDL, so the
# board shell (DDR, UART, SD, Ethernet, clocks, pins, constraints) and the
# project/bitstream/flash targets are shared with Rocket and BOOM.

NATIVE_DIR     := workspace/$(CONFIG)/native-$(BOARD)
NATIVE_SOC_DIR := $(NATIVE_DIR)/soc
NATIVE_SOC_DCP := $(NATIVE_SOC_DIR)/soc.dcp
NATIVE_VIVADO  := env XILINX_LOCAL_USER_DATA=no vivado -mode batch -nojournal -notrace
NATIVE_THREADS ?= 4

# CVA6 timebase: its CLINT counts mtime at half the core clock.
NATIVE_TIMEBASE_FREQ := $(shell echo - | awk '{printf("%.0f\n", $(ROCKET_FREQ_MHZ) * 500000)}')

.PHONY: native-soc native-program native-info

native-soc: $(NATIVE_SOC_DCP)

native-program: program

native-info:
	@echo "CONFIG=$(CONFIG) SOC_BACKEND=$(SOC_BACKEND) BOARD=$(BOARD) FREQ=$(ROCKET_FREQ_MHZ)MHz"
	@echo "netlist: $(NATIVE_SOC_DCP)"

ifeq ($(SOC_BACKEND),cva6)

# --- CVA6 ---------------------------------------------------------------

ifeq ($(CONFIG),rocket64cva6)
  CVA6_TARGET     := cv64a6_imafdc_sv39
  CVA6_CACHED_DDR := 0
else ifeq ($(CONFIG),rocket64cva6hp)
  CVA6_TARGET     := cv64a6_imafdc_sv39_hpdcache_wb
  CVA6_CACHED_DDR := 1
  # Zicbom cache-block size = HPDcache line (128 bits)
  CVA6_CBOM_BLOCK := 16
else ifeq ($(CONFIG),rocket64cva6hp2)
  # HP plus patches/cva6/hp2: dual issue with ALU bypass, 16-entry
  # scoreboard, 32 KiB 8-way I$, 64 KiB 16-way HPDcache, BTB 64, BHT 1024,
  # RAS 4, and a hardware time CSR (no OpenSBI rdtime emulation).
  CVA6_TARGET      := cv64a6_imafdc_sv39_hpdcache_wb
  CVA6_CACHED_DDR  := 1
  CVA6_CBOM_BLOCK  := 16
  CVA6_TIME_CSR    := 1
  CVA6_CFG_PATCHES := $(sort $(wildcard patches/cva6/hp2/*.patch))
else
  $(error Unknown CVA6 configuration $(CONFIG))
endif

NATIVE_MODULE   := CVA6BoardVivado
NATIVE_SOC_SHIM := src/main/resources/cva6/CVA6BoardVivado.v

# CVA6_ROOT may point at another CVA6 checkout (e.g. for bisecting). The
# stamp records the tree in use, so switching trees rebuilds the netlist.
CVA6_ROOT        ?= generators/cva6
override CVA6_ROOT := $(abspath $(CVA6_ROOT))
CVA6_ROOT_STAMP  := $(NATIVE_DIR)/cva6-root.txt
$(shell mkdir -p $(NATIVE_DIR) && [ "`cat $(CVA6_ROOT_STAMP) 2>/dev/null`" = "$(CVA6_ROOT)" ] || echo "$(CVA6_ROOT)" >$(CVA6_ROOT_STAMP))
CVA6_FPGA        := $(CVA6_ROOT)/corev_apu/fpga
CVA6_BOOTROM_DIR := $(CVA6_FPGA)/src/bootrom
CVA6_RES         := src/main/resources/cva6
CVA6_SOURCES     := $(NATIVE_DIR)/cva6-sources-$(CVA6_TARGET).tcl
# Repository fixes to CVA6 sources (patches/cva6/*.patch, -p1 from the CVA6
# root). The touched files are patched as copies; the submodule is untouched.
CVA6_PATCHES     := $(sort $(wildcard patches/cva6/*.patch)) $(CVA6_CFG_PATCHES)
CVA6_TIME_CSR    ?= 0
CVA6_PATCHED     := $(abspath $(NATIVE_DIR)/cva6-patched)
CVA6_ROM_DIR     := $(abspath $(NATIVE_DIR)/bootrom)
CVA6_ROM_DTS     := $(CVA6_ROM_DIR)/cv64a6.dts
CVA6_ROM_DTB     := $(CVA6_ROM_DIR)/cv64a6.dtb
CVA6_ROM_SV      := $(CVA6_ROM_DIR)/bootrom_64.sv
CVA6_ROM_CFLAGS  := $(if $(filter 1,$(CVA6_CACHED_DDR)),-DBOOTROM_ZICBOM=$(CVA6_CBOM_BLOCK),)

# The upstream `fpga` target needs its own boot ROM to exist before it writes
# the source manifest. It is replaced by CVA6_ROM_SV in the netlist.
$(CVA6_BOOTROM_DIR)/bootrom_64.sv:
	$(MAKE) -C $(CVA6_BOOTROM_DIR) BOARD=genesys2 XLEN=64 PLATFORM=PLAT_XILINX \
	  CC=$(CROSS_COMPILE_NO_OS_TOOLS)gcc OBJCOPY=$(CROSS_COMPILE_NO_OS_TOOLS)objcopy \
	  CFLAGS='-DCLOCK_FREQUENCY=50000000 -DUART_BITRATE=115200 -DPLAT_XILINX -DXLEN=64 -Os -ggdb -march=rv64im -mabi=lp64 -Wall -mcmodel=medany -mexplicit-relocs -ffreestanding' \
	  bootrom_64.sv

# The upstream manifest is written inside the submodule; keep a copy per
# CVA6 target so switching CONFIG never mixes source lists.
$(CVA6_SOURCES): $(CVA6_BOOTROM_DIR)/bootrom_64.sv $(CVA6_ROOT_STAMP)
	mkdir -p $(NATIVE_DIR)
	$(MAKE) -C $(CVA6_ROOT) fpga MAKE=true \
	  RISCV=$(realpath workspace/gcc/riscv) BOARD=genesys2 target=$(CVA6_TARGET)
	cp $(CVA6_FPGA)/scripts/add_sources.tcl $@

$(CVA6_ROM_DTS): $(CVA6_RES)/bootrom/genesys2.dts
	mkdir -p $(CVA6_ROM_DIR)
	cp $< $@
	sed -i "s#clock-frequency = <[0-9]*>#clock-frequency = <$(ROCKET_CLOCK_FREQ)>#g" $@
	sed -i "s#timebase-frequency = <[0-9]*>#timebase-frequency = <$(NATIVE_TIMEBASE_FREQ)>#g" $@
	if [ "$(CVA6_CACHED_DDR)" = "1" ] ; then \
	  sed -i 's#riscv,isa = "rv64imafdc";#riscv,isa = "rv64imafdc_zicbom";\n      riscv,cbom-block-size = <$(CVA6_CBOM_BLOCK)>;#' $@ ; \
	  sed -i 's#compatible = "simple-bus";#compatible = "simple-bus";\n    dma-noncoherent;#' $@ ; \
	fi
	if [ ! -z "$(ETHER_MAC)" ] ; then sed -i "s#local-mac-address = \[.*\]#local-mac-address = [$(ETHER_MAC)]#g" $@ ; fi
	if [ ! -z "$(ETHER_PHY)" ] ; then sed -i "s#phy-mode = \".*\"#phy-mode = \"$(ETHER_PHY)\"#g" $@ ; fi

$(CVA6_ROM_DTB): $(CVA6_ROM_DTS)
	dtc -I dts -O dtb -o $@ $<

# Native CVA6 reset head followed by the common repository board loader.
$(CVA6_ROM_SV): $(CVA6_RES)/bootrom/board-head.S \
    bootrom/bootrom.lds bootrom/bootrom.c bootrom/kprintf.c \
    bootrom/ff.c bootrom/ffunicode.c bootrom/common.h $(CVA6_ROM_DTB)
	cd $(CVA6_ROM_DIR) && \
	  $(CROSS_COMPILE_NO_OS_TOOLS)gcc \
	  -Os -g -march=rv64im -mabi=lp64 -mcmodel=medany -mexplicit-relocs \
	  -ffreestanding -fno-builtin -ffunction-sections -fdata-sections \
	  -DDEVICE_TREE='"cv64a6.dtb"' $(CVA6_ROM_CFLAGS) -I$(abspath bootrom) \
	  -nostdlib -nostartfiles -Wl,--gc-sections \
	  -T $(abspath bootrom/bootrom.lds) \
	  $(abspath $(CVA6_RES)/bootrom/board-head.S) \
	  $(abspath bootrom/bootrom.c) $(abspath bootrom/kprintf.c) \
	  $(abspath bootrom/ff.c) $(abspath bootrom/ffunicode.c) \
	  -o bootrom_64.elf
	$(CROSS_COMPILE_NO_OS_TOOLS)objcopy -O binary $(CVA6_ROM_DIR)/bootrom_64.elf $(CVA6_ROM_DIR)/bootrom_64.img
	cd $(CVA6_ROM_DIR) && $(CVA6_BOOTROM_DIR)/gen_rom.py bootrom_64.img

$(CVA6_PATCHED)/.stamp: $(CVA6_PATCHES) $(CVA6_ROOT_STAMP)
	rm -rf $(CVA6_PATCHED)
	mkdir -p $(CVA6_PATCHED)
	for p in $(abspath $(CVA6_PATCHES)) ; do \
	  for f in `sed -n 's#^+++ b/\([^[:space:]]*\).*#\1#p' $$p` ; do \
	    mkdir -p $(CVA6_PATCHED)/`dirname $$f` ; \
	    [ -f $(CVA6_PATCHED)/$$f ] || cp $(CVA6_ROOT)/$$f $(CVA6_PATCHED)/$$f ; \
	  done ; \
	  patch -d $(CVA6_PATCHED) -p1 --no-backup-if-mismatch <$$p || exit 1 ; \
	done
	touch $@

$(NATIVE_SOC_DCP): scripts/native/synth-cva6.tcl $(CVA6_SOURCES) $(CVA6_ROM_SV) $(CVA6_PATCHED)/.stamp \
    $(CVA6_RES)/CVA6Core.sv $(CVA6_RES)/CVA6BoardSubsystem.sv $(CVA6_RES)/CVA6BoardWrapper.sv
	mkdir -p $(NATIVE_SOC_DIR)
	echo "set repo_root $(abspath .)" >$(NATIVE_DIR)/synth-soc.tcl
	echo "set soc_part $(XILINX_PART)" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set soc_threads $(NATIVE_THREADS)" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set soc_out_dir $(abspath $(NATIVE_SOC_DIR))" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set cva6_root $(CVA6_ROOT)" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set cva6_sources $(abspath $(CVA6_SOURCES))" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set cva6_patched $(CVA6_PATCHED)" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set cva6_bootrom $(CVA6_ROM_SV)" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set cva6_cached_ddr $(CVA6_CACHED_DDR)" >>$(NATIVE_DIR)/synth-soc.tcl
	echo "set cva6_time_csr $(CVA6_TIME_CSR)" >>$(NATIVE_DIR)/synth-soc.tcl
	echo 'source [file join $$repo_root scripts native synth-cva6.tcl]' >>$(NATIVE_DIR)/synth-soc.tcl
	cd $(NATIVE_DIR) && $(NATIVE_VIVADO) -log synth-soc.log -source synth-soc.tcl
	test -f $@

else ifeq ($(SOC_BACKEND),noelv)

# --- NOEL-V -------------------------------------------------------------
#
# GRLIB noelvsys with stock presets. The GRLIB submodule stays read-only:
# its ordered library manifest is generated out-of-tree (TECHLIBS=unisim for
# the Kintex-7 BSCAN/clock wrappers), and the boot ROM is a generated AHB ROM.

ifeq ($(CONFIG),rocket64noelv)
  NOELV_CFG := 768
  NOELV_MMU := riscv,sv39
else ifeq ($(CONFIG),rocket64noelvhp)
  NOELV_CFG := 1024
  NOELV_MMU := riscv,sv48
else ifeq ($(CONFIG),rocket64noelvhp2)
  # Full-size (larger FPGAs than the Genesys 2; ~180k LUTs of SoC). Two HP harts (SMP) with the larger branch history table (custom preset,
  # 16#F00#) sharing a 512 KiB 4-way L2C-Lite in front of 512 MiB of DDR.
  NOELV_NCPU       := 2
  NOELV_CFG        := 3840
  NOELV_MMU        := riscv,sv48
  NOELV_CFG_CUSTOM := $(abspath src/main/resources/noelv/native/noelv_cpu_cfg_hp2.vhd)
  NOELV_L2_WAYS    := 4
  NOELV_L2_WAYSIZE := 128
  NOELV_MEM_SIZE   := 0x20000000
else ifeq ($(CONFIG),rocket64noelvhp2s)
  # rocket64noelvhp2 trimmed to fit the Genesys 2 (see noelv_cpu_cfg_hp2s.vhd):
  # same harts, predictor and L2, minus features Linux does not use here.
  NOELV_NCPU       := 2
  NOELV_CFG        := 3840
  NOELV_MMU        := riscv,sv48
  NOELV_CFG_CUSTOM := $(abspath src/main/resources/noelv/native/noelv_cpu_cfg_hp2s.vhd)
  NOELV_L2_WAYS    := 4
  NOELV_L2_WAYSIZE := 128
  NOELV_MEM_SIZE   := 0x20000000
else
  $(error Unknown NOEL-V configuration $(CONFIG))
endif
NOELV_NCPU       ?= 1
NOELV_L2_WAYS    ?= 4
NOELV_L2_WAYSIZE ?= 0
NOELV_MEM_SIZE   ?= 0x30000000
# 768 = 16#300# GP (dual-issue, FPU, Sv39), 1024 = 16#400# HP (Sv48, larger
# TLBs/PMP)

NATIVE_MODULE   := NOELVBoardVivado
NATIVE_SOC_SHIM := src/main/resources/noelv/native/NOELVBoardVivado.v

# NOEL-V mtime (GRLIB time-stamp counter) increments once per core clock.
NOELV_TIMEBASE_FREQ := $(ROCKET_CLOCK_FREQ)

NOELV_RES        := src/main/resources/noelv/native
NOELV_GRLIB      := $(abspath generators/grlib)
NOELV_GRLIB_REF  := $(NOELV_GRLIB)/designs/noelv-generic
NOELV_GRLIB_DIR  := $(abspath $(NATIVE_DIR)/grlib)
NOELV_MANIFEST   := $(NOELV_GRLIB_DIR)/vivado/noelvmp_vivado.tcl
NOELV_ROM_DIR    := $(abspath $(NATIVE_DIR)/bootrom)
NOELV_ROM_DTS    := $(NOELV_ROM_DIR)/noelv.dts
NOELV_ROM_DTB    := $(NOELV_ROM_DIR)/noelv.dtb
NOELV_ROM_ELF    := $(NOELV_ROM_DIR)/bootrom.elf
NOELV_ROM_IMG    := $(NOELV_ROM_DIR)/bootrom.img
NOELV_ROM_VHD    := $(NOELV_ROM_DIR)/NOELVBootRom.vhd
NOELV_VHDL       := $(NOELV_RES)/NOELVBoardSubsystem.vhd $(NOELV_RES)/NOELVBoardWrapper.vhd \
                    $(NOELV_RES)/noelv_pma_cfg.vhd $(NOELV_CFG_CUSTOM)

# GRLIB's own script generator, run in a scratch copy of the noelv-generic
# design directory so nothing is written into the submodule.
$(NOELV_MANIFEST): src/main/resources/noelv/grlib_config.vhd
	rm -rf $(NOELV_GRLIB_DIR)
	mkdir -p $(NOELV_GRLIB_DIR)/rtl/core $(NOELV_GRLIB_DIR)/tb
	cp $(NOELV_GRLIB_REF)/Makefile $(NOELV_GRLIB_REF)/.config $(NOELV_GRLIB_REF)/config.vhd $(NOELV_GRLIB_DIR)/
	cp -r $(NOELV_GRLIB_REF)/cfg $(NOELV_GRLIB_DIR)/
	cp src/main/resources/noelv/grlib_config.vhd $(NOELV_GRLIB_DIR)/
	cd $(NOELV_GRLIB_DIR) && env -u MAKEFLAGS -u MFLAGS -u MAKEOVERRIDES -u MAKELEVEL \
	  make scripts GRLIB=$(NOELV_GRLIB) TECHLIBS=unisim SKIP_SIM_TECHLIBS=1 >scriptgen.log
	test -f $@

$(NOELV_ROM_DTS): $(NOELV_RES)/genesys2.dts
	mkdir -p $(NOELV_ROM_DIR)
	cpp -P -nostdinc -undef -x assembler-with-cpp -DNOELV_NCPU=$(NOELV_NCPU) $< >$@
	sed -i "s#clock-frequency = <[0-9]*>#clock-frequency = <$(ROCKET_CLOCK_FREQ)>#g" $@
	sed -i "s#timebase-frequency = <[0-9]*>#timebase-frequency = <$(NOELV_TIMEBASE_FREQ)>#g" $@
	sed -i "s#mmu-type = \".*\"#mmu-type = \"$(NOELV_MMU)\"#g" $@
	sed -i "s#reg = <0x0 0x80000000 0x0 0x30000000>#reg = <0x0 0x80000000 0x0 $(NOELV_MEM_SIZE)>#" $@
	if [ ! -z "$(ETHER_MAC)" ] ; then sed -i "s#local-mac-address = \[.*\]#local-mac-address = [$(ETHER_MAC)]#g" $@ ; fi
	if [ ! -z "$(ETHER_PHY)" ] ; then sed -i "s#phy-mode = \".*\"#phy-mode = \"$(ETHER_PHY)\"#g" $@ ; fi

$(NOELV_ROM_DTB): $(NOELV_ROM_DTS)
	dtc -I dts -O dtb -o $@ $<

# NOEL-V early init (caches, snooping, PLIC trigger type) followed by the
# common repository board loader, linked with the stock bootrom.lds at
# 0x10000. The ROM is mapped there and at the NOEL-V reset vector.
$(NOELV_ROM_IMG): $(NOELV_RES)/board-head.S \
    bootrom/bootrom.lds bootrom/bootrom.c bootrom/kprintf.c \
    bootrom/ff.c bootrom/ffunicode.c bootrom/common.h $(NOELV_ROM_DTB)
	cd $(NOELV_ROM_DIR) && \
	  $(CROSS_COMPILE_NO_OS_TOOLS)gcc \
	  -Os -g -march=rv64im -mabi=lp64 -mcmodel=medany -mexplicit-relocs \
	  -ffreestanding -fno-builtin -ffunction-sections -fdata-sections \
	  -DDEVICE_TREE='"noelv.dtb"' -I$(abspath bootrom) \
	  -nostdlib -nostartfiles -Wl,--gc-sections \
	  -T $(abspath bootrom/bootrom.lds) \
	  $(abspath $(NOELV_RES)/board-head.S) \
	  $(abspath bootrom/bootrom.c) $(abspath bootrom/kprintf.c) \
	  $(abspath bootrom/ff.c) $(abspath bootrom/ffunicode.c) \
	  -o $(NOELV_ROM_ELF)
	$(CROSS_COMPILE_NO_OS_TOOLS)objcopy -O binary $(NOELV_ROM_ELF) $@

$(NOELV_ROM_VHD): scripts/native/gen-ahbrom.py $(NOELV_ROM_IMG)
	python3 scripts/native/gen-ahbrom.py $(NOELV_ROM_IMG) $@ NOELVBootRom

# Generated Vivado script for the netlist (RTL_ONLY=1: elaboration check).
define noelv_synth_tcl
	echo "set repo_root $(abspath .)" >$(1)
	echo "set soc_part $(XILINX_PART)" >>$(1)
	echo "set soc_threads $(NATIVE_THREADS)" >>$(1)
	echo "set soc_out_dir $(abspath $(2))" >>$(1)
	echo "set soc_clock_mhz $(ROCKET_FREQ_MHZ)" >>$(1)
	echo "set grlib_manifest $(NOELV_MANIFEST)" >>$(1)
	echo "set grlib_config $(abspath src/main/resources/noelv/grlib_config.vhd)" >>$(1)
	echo "set noelv_rom $(NOELV_ROM_VHD)" >>$(1)
	echo "set noelv_cfg $(NOELV_CFG)" >>$(1)
	echo "set noelv_cfg_custom {$(NOELV_CFG_CUSTOM)}" >>$(1)
	echo "set noelv_ncpu $(NOELV_NCPU)" >>$(1)
	echo "set noelv_l2_ways $(NOELV_L2_WAYS)" >>$(1)
	echo "set noelv_l2_waysize $(NOELV_L2_WAYSIZE)" >>$(1)
	echo "set rtl_only $(3)" >>$(1)
	echo 'source [file join $$repo_root scripts native synth-noelv.tcl]' >>$(1)
endef

$(NATIVE_SOC_DCP): scripts/native/synth-noelv.tcl scripts/native/noelv-sources.tcl \
    $(NOELV_MANIFEST) $(NOELV_ROM_VHD) $(NOELV_VHDL)
	mkdir -p $(NATIVE_SOC_DIR)
	$(call noelv_synth_tcl,$(NATIVE_DIR)/synth-soc.tcl,$(NATIVE_SOC_DIR),0)
	cd $(NATIVE_DIR) && $(NATIVE_VIVADO) -log synth-soc.log -source synth-soc.tcl
	test -f $@

.PHONY: native-rtl-check native-sim
native-rtl-check: scripts/native/synth-noelv.tcl scripts/native/noelv-sources.tcl \
    $(NOELV_MANIFEST) $(NOELV_ROM_VHD) $(NOELV_VHDL)
	mkdir -p $(NATIVE_DIR)/rtl-check
	$(call noelv_synth_tcl,$(NATIVE_DIR)/rtl-check.tcl,$(NATIVE_DIR)/rtl-check,1)
	cd $(NATIVE_DIR) && $(NATIVE_VIVADO) -log rtl-check.log -source rtl-check.tcl

# GHDL boot-ROM simulation: real wrapper + boot ROM, behavioral DDR and UART
# (GRLIB inferred technology). Full log: $(NATIVE_DIR)/sim/sim.log.
SIM_TX_BYTES ?= 28
SIM_MAX_US   ?= 20000
GHDL         ?= ghdl
native-sim: scripts/native/sim-noelv-ghdl.sh $(NOELV_ROM_VHD) $(NOELV_VHDL) $(wildcard $(NOELV_RES)/sim/*.vhd)
	GHDL=$(GHDL) scripts/native/sim-noelv-ghdl.sh $(NATIVE_DIR)/sim $(NOELV_ROM_VHD) $(NOELV_CFG) $(SIM_TX_BYTES) $(SIM_MAX_US)

endif
