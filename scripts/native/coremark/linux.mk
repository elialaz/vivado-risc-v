# Linux CoreMark (upstream POSIX port), static, run on the board's Debian.
#   make -f linux.mk   -> build/linux-<flavour>-<mode>
# flavour zb: CVA6/NOEL-V (Zba/Zbb/Zbs/Zbc); gc: BOOM (RV64GC only);
# b: Shuttle (Zba/Zbb/Zbs).
LCC := riscv64-linux-gnu-gcc
CM  := ../../../bare-metal/coremark/coremark
ITERATIONS ?= 4000
SRCS := $(CM)/core_list_join.c $(CM)/core_main.c $(CM)/core_matrix.c $(CM)/core_state.c \
        $(CM)/core_util.c $(CM)/posix/core_portme.c
BASE := -O2 -march=rv64gc -mabi=lp64d
OPTC := -O3 -flto -funroll-all-loops -finline-limit=600 -finline-functions \
        -ftree-dominator-opts -fno-if-conversion2 -fselective-scheduling -fno-code-hoisting \
        -falign-functions=8 -falign-jumps=8 -falign-loops=8 -fno-tree-loop-distribute-patterns -mabi=lp64d
OUT := build/linux-zb-base build/linux-zb-opt build/linux-zb-opt2 \
       build/linux-gc-base build/linux-gc-opt build/linux-gc-opt2 \
       build/linux-b-base build/linux-b-opt build/linux-b-opt2
all: $(OUT)
f_zb-base := $(BASE)
f_zb-opt  := $(OPTC) -march=rv64gc_zba_zbb_zbs_zbc -mtune=sifive-7-series
f_zb-opt2 := $(OPTC) -march=rv64gc_zba_zbb_zbs_zbc -mtune=rocket
f_gc-base := $(BASE)
f_gc-opt  := $(OPTC) -march=rv64gc -mtune=sifive-7-series
f_gc-opt2 := $(OPTC) -march=rv64gc -mtune=rocket
f_b-base  := $(BASE)
f_b-opt   := $(OPTC) -march=rv64gc_zba_zbb_zbs -mtune=sifive-7-series
f_b-opt2  := $(OPTC) -march=rv64gc_zba_zbb_zbs -mtune=rocket
build/linux-%: $(SRCS) linux.mk
	mkdir -p build
	$(LCC) $(f_$*) -static -I$(CM) -I$(CM)/posix -DPERFORMANCE_RUN=1 -DITERATIONS=$(ITERATIONS) \
	  '-DFLAGS_STR="$(f_$*)"' -o $@ $(SRCS) -lrt
