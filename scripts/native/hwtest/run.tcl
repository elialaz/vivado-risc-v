# Bare-metal JTAG regression for the native SoCs on a programmed board.
# Usage: xsdb run.tcl <dir with the .bin files>
# Code is loaded and DDR is checked through the "RISC-V" target, i.e. the
# debug module's system bus access, which bypasses the CPU caches (needed for
# write-back data caches such as CVA6 HPDcache).
#   order-*: pass = s4 keeps counting; fail = hart stuck in bad/park.
#   irq-timer: pass = loops and irqs both large, no exception.
#   wb-64k : pass = first evicted word in DDR is 0xc0de0000.
set dir [lindex $argv 0]
connect -url tcp:localhost:3121
proc run_test {dir t addr ms} {
  targets -set -filter {name =~ "Hart #0*"}
  catch {stop}
  targets -set -filter {name =~ "RISC-V"}
  dow -data [file join $dir $t.bin] $addr
  targets -set -filter {name =~ "Hart #0*"}
  if {[rrd -no-bits priv] != 3} { rwr priv 3 }
  rwr csr mie 0
  rwr csr mcause 0
  rwr s4 0
  rwr pc $addr
  con
  after $ms
  catch {stop}
}
foreach {t addr} {order-clint-rw 0x80200000 order-uart-rd 0x80201000 order-clint-rd 0x80202000} {
  run_test $dir $t $addr 2000
  puts "$t: passes=[rrd -no-bits s4] pc=[rrd -no-bits pc] mcause=[rrd -no-bits csr mcause]"
  flush stdout
}
run_test $dir irq-timer 0x80204000 2000
puts "irq-timer: loops=[rrd -no-bits s4] irqs=[rrd -no-bits s5] pc=[rrd -no-bits pc] mcause=[rrd -no-bits csr mcause] mepc=[rrd -no-bits csr mepc]"
flush stdout
rwr csr mie 0
run_test $dir wb-64k 0x80203000 1000
set done [rrd -no-bits s4]
targets -set -filter {name =~ "RISC-V"}
puts "wb-64k: done=$done ddr\[0x80500000\]=[format 0x%08x [mrd -value 0x80500000 1]] (expect 0xc0de0000)"
