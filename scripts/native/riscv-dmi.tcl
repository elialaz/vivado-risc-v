# RISC-V debug for the SpinalHDL SoCs (VexiiRiscv, NaxRiscv) over the
# onboard USB-JTAG cable.
#
# Their RISC-V debug TAP sits behind the BSCAN-to-JTAG bridge that vivado.tcl
# adds (debug_bridge + bscan2jtag). hw_server shows it as an unknown device
# (IDCODE 0x10002fff, IR length 5) and xsdb does not attach a RISC-V target
# to it, so this script drives the debug transport with raw JTAG scans.
#
#   xsdb scripts/native/riscv-dmi.tcl status    debug module and hart state
#   xsdb scripts/native/riscv-dmi.tcl halt      halt hart 0, print PC/trap CSRs
#   xsdb scripts/native/riscv-dmi.tcl resume    resume hart 0
#   xsdb scripts/native/riscv-dmi.tcl read <addr>   32-bit load by the hart
#
# Uses only cable serial filters of the Genesys 2 (see JTAG_BRIDGE below);
# other boards on the same hw_server are not touched. halt/read leave the
# hart halted.

set JTAG_BRIDGE "*BSCAN to JTAG bridge*Genesys*"
set DTM_IDCODE  10002fff
set HW_SERVER   [expr {[info exists env(HW_SERVER_ADDR)] ? $env(HW_SERVER_ADDR) : "localhost:3121"}]

proc dtm_select {} {
  global JTAG_BRIDGE DTM_IDCODE
  jtag targets -set -filter [list name =~ $JTAG_BRIDGE]
  catch {jtag targets -open}
  after 500
  foreach line [split [jtag targets] "\n"] {
    if {[regexp "^\\s*(\\d+)\\*?\\s+.*idcode $DTM_IDCODE" $line -> n]} { jtag targets -set $n; return $n }
  }
  error "RISC-V debug TAP not found behind the BSCAN bridge"
}
proc scan_ir {v} {
  set s [jtag sequence]
  $s irshift -state IDLE -int 5 $v
  $s run
  $s delete
}
proc scan_dr {bits v} {
  set s [jtag sequence]
  $s drshift -state IDLE -capture -int $bits $v
  $s state IDLE 32
  set r [$s run -int]
  $s delete
  return $r
}
# DMI access: addr(7) data(32) op(2); retried while the DTM reports busy.
proc dmi_op {addr data op} {
  set v [expr {(($addr & 0x7f) << 34) | (($data & 0xffffffff) << 2) | ($op & 3)}]
  for {set try 0} {$try < 50} {incr try} {
    scan_ir 0x11
    scan_dr 41 $v
    set r [scan_dr 41 0]
    set st [expr {$r & 3}]
    if {$st == 0} { return [expr {($r >> 2) & 0xffffffff}] }
    scan_ir 0x10
    scan_dr 32 [expr {1 << 16}]
    after 2
  }
  error "DMI access to 0x[format %x $addr] failed (status $st)"
}
proc dmi_read {addr} { return [dmi_op $addr 0 1] }
proc dmi_write {addr data} { dmi_op $addr $data 2; return }
proc cmd_ok {} {
  set cs [dmi_read 0x16]
  if {($cs >> 8) & 7} { dmi_write 0x16 [expr {7 << 8}]; return 0 }
  return 1
}
# GPRs through abstract commands (regno 0x1000 + n)
proc reg_read {regno} {
  dmi_write 0x17 [expr {(3 << 20) | (1 << 17) | $regno}]
  if {![cmd_ok]} { return "error" }
  return [format 0x%08x%08x [dmi_read 0x05] [dmi_read 0x04]]
}
proc reg_write {regno value} {
  dmi_write 0x04 [expr {$value & 0xffffffff}]
  dmi_write 0x05 [expr {($value >> 32) & 0xffffffff}]
  dmi_write 0x17 [expr {(3 << 20) | (1 << 17) | (1 << 16) | $regno}]
  return [cmd_ok]
}
# One instruction from the program buffer (s0 is the scratch register).
proc prog1 {insn} {
  dmi_write 0x20 $insn
  dmi_write 0x21 0x00100073
  dmi_write 0x17 [expr {(3 << 20) | (1 << 18) | 0x1008}]
  return [cmd_ok]
}
proc csr_read {csr} {
  if {![prog1 [expr {($csr << 20) | 0x2473}]]} { return "error" }
  return [reg_read 0x1008]
}
proc mem_read32 {addr} {
  reg_write 0x1008 $addr
  if {![prog1 0x00042403]} { return "fault" }
  return [reg_read 0x1008]
}
proc show_status {} {
  set s [dmi_read 0x11]
  puts [format "dmstatus=0x%08x running=%d halted=%d havereset=%d" $s \
    [expr {($s >> 11) & 1}] [expr {($s >> 9) & 1}] [expr {($s >> 19) & 1}]]
}
proc halt {} {
  dmi_write 0x10 [expr {(1 << 31) | 1}]
  after 50
  dmi_write 0x10 1
}

connect -url tcp:$HW_SERVER
dtm_select
dmi_write 0x10 1
set action [expr {[llength $argv] ? [lindex $argv 0] : "status"}]
switch -- $action {
  status { show_status }
  halt {
    halt
    show_status
    foreach {name csr} {dpc 0x7b1 mcause 0x342 mepc 0x341 mtval 0x343 mstatus 0x300 mtvec 0x305} {
      puts "$name=[csr_read $csr]"
    }
    foreach {name r} {ra 0x1001 sp 0x1002 a0 0x100a a1 0x100b} { puts "$name=[reg_read $r]" }
  }
  resume {
    dmi_write 0x10 [expr {(1 << 30) | 1}]
    show_status
  }
  read {
    halt
    puts "[lindex $argv 1]: [mem_read32 [lindex $argv 1]]"
  }
  default { error "unknown action $action (status, halt, resume, read <addr>)" }
}
