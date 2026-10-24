# SPDX-License-Identifier: GPL-2.0-only
# Synthesize the native NOEL-V SoC as an isolated out-of-context netlist.
#
# The board project never sees GRLIB's VHDL libraries: it only gets the
# Verilog shim (NOELVBoardVivado.v), a black-box stub for NOELVBoardWrapper
# and the checkpoint written here.
#
# Inputs (set by the generated caller script):
#   repo_root, soc_part, soc_threads, soc_out_dir,
#   grlib_manifest - GRLIB scriptgen Vivado script (ordered library sources),
#                    generated out-of-tree with TECHLIBS=unisim
#   grlib_config   - repository GRLIB global configuration package
#   noelv_rom      - generated boot ROM VHDL (entity NOELVBootRom)
#   noelv_cfg      - NOEL-V preset (decimal), e.g. 768 = GP, 1024 = HP,
#                    3840 = custom (noelv_cfg_custom overlay)
#   noelv_ncpu     - number of harts
#   noelv_l2_ways, noelv_l2_waysize - L2C-Lite geometry (waysize 0 = no L2)
#   noelv_cfg_custom - optional overlay for noelv_cpu_cfg_custom.vhd
#   soc_clock_mhz  - optional; target clock for a timing estimate
#   rtl_only       - optional; 1 = elaborate only (synth_design -rtl)

set_param general.maxThreads $soc_threads
if {![info exists rtl_only]} { set rtl_only 0 }

# A throwaway project, only so Vivado orders the VHDL libraries for us.
create_project -force soc-noelv [file join $soc_out_dir proj] -part $soc_part
set_property target_language VHDL [current_project]
file mkdir $soc_out_dir

source [file join $repo_root scripts native noelv-sources.tcl]

set_property top NOELVBoardWrapper [current_fileset]
update_compile_order -fileset sources_1

if {$rtl_only} {
  synth_design -rtl -name rtl_1 -top NOELVBoardWrapper -part $soc_part \
    -generic cfg=$noelv_cfg -generic ncpu=$noelv_ncpu -generic l2_ways=$noelv_l2_ways -generic l2_waysize=$noelv_l2_waysize
  puts "NATIVE_NOELV_RTL_ELABORATED"
  return
}

synth_design -mode out_of_context -flatten_hierarchy rebuilt \
  -top NOELVBoardWrapper -part $soc_part \
  -generic cfg=$noelv_cfg -generic ncpu=$noelv_ncpu -generic l2_ways=$noelv_l2_ways -generic l2_waysize=$noelv_l2_waysize

report_utilization -file [file join $soc_out_dir utilization.rpt]
write_checkpoint -force [file join $soc_out_dir soc.dcp]

# Post-synthesis timing estimate at the target clock. The clock is created
# only after the checkpoint is written, so the netlist carries no clock
# constraint into the board project.
if {[info exists soc_clock_mhz]} {
  create_clock -name soc_clock -period [expr {1000.0 / $soc_clock_mhz}] [get_ports clock]
  report_timing_summary -file [file join $soc_out_dir timing-estimate.rpt]
}

# Black-box stub for the board project.
set stub [file join $soc_out_dir soc_stub.v]
write_verilog -force -mode synth_stub $stub
set channel [open $stub r]
set text [read $channel]
close $channel
if {![string match {*(\* black_box*} $text]} {
  regsub {\nmodule } $text "\n(* black_box = \"yes\" *)\nmodule " text
  set channel [open $stub w]
  puts -nonewline $channel $text
  close $channel
}
puts "NATIVE_SOC_NETLIST_READY: $soc_out_dir"
