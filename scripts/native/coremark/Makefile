# Bare-metal CoreMark for the Genesys 2 SoCs.
#   make CORE=<core> MODE=<base|opt|opt2>   -> build/<core>-<mode>.elf
#   make all-elfs                            -> every core and mode
# base: EEMBC-style reference build (-O2, plain RV64GC), same code for all.
# opt3: plain -O3 -flto (used for BOOM, where unrolling hurts).
# opt/opt2: aggressive GCC flags with the core's real ISA extensions and two
#           different -mtune models (the better of the two is reported).
CC      := /tools/riscv/bin/riscv64-unknown-elf-gcc
CM      := ../../../bare-metal/coremark/coremark
ITERATIONS ?= 4000
# Each mode has its own load address so images never alias in the caches.
addr_base := 0x90000000
addr_opt  := 0x92000000
addr_opt2 := 0x94000000
addr_opt3 := 0x96000000
addr_opt4 := 0x98000000
LOAD_ADDR ?= $(or $(addr_$(MODE)),0x9a000000)

# Per-core settings: ISA for the optimized builds, -mtune for opt / opt2,
# extra defines, and the core clock (MHz, only for CoreMark's 10 s check).
ZB := rv64imafdc_zicsr_zifencei_zba_zbb_zbs_zbc_zicond_zcb
march_cva6hp    := $(ZB)
tune1_cva6hp    := rocket
tune2_cva6hp    := sifive-7-series
mhz_cva6hp      := 50
defs_cva6hp     := -DCBOM -DCBOM_BLOCK=16
march_cva6hp2   := $(ZB)
tune1_cva6hp2   := sifive-7-series
tune2_cva6hp2   := rocket
mhz_cva6hp2     := 50
defs_cva6hp2    := -DCBOM -DCBOM_BLOCK=16
march_noelvhp   := $(ZB)
tune1_noelvhp   := sifive-7-series
tune2_noelvhp   := rocket
defs_noelvhp    := -DNOELV
mhz_noelvhp     := 50
march_noelvhp2s := $(ZB)
tune1_noelvhp2s := sifive-7-series
tune2_noelvhp2s := rocket
defs_noelvhp2s  := -DNOELV -DPARK_SECONDARY
mhz_noelvhp2s   := 50
march_boomx1    := rv64imafdc_zicsr_zifencei
tune1_boomx1    := generic-ooo
tune2_boomx1    := sifive-p400-series
mhz_boomx1      := 50
march_boomx1v4  := rv64imafdc_zicsr_zifencei
tune1_boomx1v4  := generic-ooo
tune2_boomx1v4  := sifive-p400-series
mhz_boomx1v4    := 40
march_boomw1v4  := rv64imafdc_zicsr_zifencei
tune1_boomw1v4  := generic-ooo
tune2_boomw1v4  := sifive-p400-series
mhz_boomw1v4    := 50
CORES := cva6hp cva6hp2 noelvhp noelvhp2s boomx1 boomx1v4 boomw1v4
MODES := base opt opt2

BASE_FLAGS := -O2 -march=rv64imafdc_zicsr_zifencei -mabi=lp64d
OPT_COMMON := -O3 -flto -funroll-all-loops -finline-limit=600 -finline-functions \
              -ftree-dominator-opts -fno-if-conversion2 -fselective-scheduling \
              -fno-code-hoisting -falign-functions=8 -falign-jumps=8 -falign-loops=8 \
              -fno-tree-loop-distribute-patterns -mabi=lp64d

COMMON := -mcmodel=medany -ffreestanding -fno-builtin -fno-common -nostdlib -nostartfiles \
          -static -Wl,--build-id=none -I. -I$(CM) -DPERFORMANCE_RUN=1 -DITERATIONS=$(ITERATIONS) \
          -DLOAD_ADDR=$(LOAD_ADDR)
SRCS   := head.S core_portme.c $(CM)/core_list_join.c $(CM)/core_main.c $(CM)/core_matrix.c \
          $(CM)/core_state.c $(CM)/core_util.c

ifneq ($(CORE),)
MARCH  := $(march_$(CORE))
TUNE1  := $(tune1_$(CORE))
TUNE2  := $(tune2_$(CORE))
DEFS   := $(defs_$(CORE))
MHZ    := $(mhz_$(CORE))
ifeq ($(MODE),base)
FLAGS  := $(BASE_FLAGS)
else ifeq ($(MODE),opt)
FLAGS  := $(OPT_COMMON) -march=$(MARCH) -mtune=$(TUNE1)
else ifeq ($(MODE),opt2)
FLAGS  := $(OPT_COMMON) -march=$(MARCH) -mtune=$(TUNE2)
else ifeq ($(MODE),opt3)
# Plain -O3 + LTO without forced unrolling/inlining (better for the
# out-of-order BOOM, whose I-cache suffers from the unrolled code).
FLAGS  := -O3 -flto -mabi=lp64d -march=$(MARCH) -mtune=$(TUNE1)
else ifeq ($(MODE),opt4)
# -O2 + LTO with the second tuning model.
FLAGS  := -O2 -flto -mabi=lp64d -march=$(MARCH) -mtune=$(TUNE2)
endif
endif

ELF := build/$(CORE)-$(MODE).elf

$(ELF): $(SRCS) core_portme.h link.ld Makefile
	mkdir -p build
	$(CC) -E -P -x c -DLOAD_ADDR=$(LOAD_ADDR) link.ld -o build/link-$(CORE)-$(MODE).ld
	$(CC) $(FLAGS) $(COMMON) $(DEFS) -DCLK_MHZ=$(MHZ) \
	  '-DCORE_NAME="$(CORE)"' '-DMODE_NAME="$(MODE)"' \
	  '-DCOMPILER_FLAGS="$(FLAGS)"' \
	  -T build/link-$(CORE)-$(MODE).ld -o $@ $(SRCS) -lgcc
	@test $$(riscv64-linux-gnu-objdump -h $@ | awk '/\.text/{print $$4}' | cut -c1-8) = $$(printf '%08x' $$(($(LOAD_ADDR) >> 32)))

all-elfs:
	for c in $(CORES); do for m in $(MODES); do $(MAKE) --no-print-directory CORE=$$c MODE=$$m || exit 1; done; done

clean:
	rm -rf build
.PHONY: all-elfs clean
