# Bare-metal bus-ordering regression for the native SoCs (CVA6/NOEL-V).
CROSS ?= riscv64-linux-gnu-
TESTS := order-clint-rw order-uart-rd order-clint-rd wb-64k irq-timer irq-ddr irq-uart trap-ecall irq-msip frame-store irq-smode amo-ddr irq-deleg irq-deleg-nop irq-deleg-svec irq-deleg-sie irq-sie0 irq-sie0-mie0
all: $(TESTS:=.bin)
# Each test has its own address, so a stale I-cache line from the previous
# test can never be executed (code is loaded over the debug system bus).
ADDR_order-clint-rw := 0x80200000
ADDR_order-uart-rd  := 0x80201000
ADDR_order-clint-rd := 0x80202000
ADDR_wb-64k         := 0x80203000
ADDR_irq-timer      := 0x80204000
ADDR_irq-ddr        := 0x80205000
ADDR_irq-uart       := 0x80206000
ADDR_trap-ecall     := 0x80207000
ADDR_irq-msip       := 0x80208000
ADDR_frame-store    := 0x80209000
ADDR_irq-smode      := 0x8020a000
ADDR_amo-ddr        := 0x8020b000
ADDR_irq-deleg      := 0x8020c000
ADDR_irq-deleg-nop  := 0x8020d000
ADDR_irq-deleg-svec := 0x8020e000
ADDR_irq-deleg-sie  := 0x8020f000
ADDR_irq-sie0       := 0x80210000
ADDR_irq-sie0-mie0  := 0x80211000
%.bin: %.S common.inc
	$(CROSS)gcc -march=rv64ima_zicsr_zifencei -mabi=lp64 -fno-pic -no-pie -nostdlib -Wl,--build-id=none -Ttext=$(ADDR_$*) -o $*.elf $<
	$(CROSS)objcopy -O binary -j .text $*.elf $@
	@test $$(stat -c %s $@) -lt 65536 || { echo "$@ too large"; rm -f $@; exit 1; }
run: all
	xsdb run.tcl $(CURDIR)
clean:
	rm -f *.elf *.bin
.PHONY: all run clean
