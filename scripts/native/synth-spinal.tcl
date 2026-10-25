# Synthesize a SpinalHDL LiteX-style SoC (VexiiRiscv, NaxRiscv) as an
# isolated out-of-context netlist.
#
# The board project only gets the Verilog shim (SpinalBoardVivado.v), a
# black-box stub for SpinalBoardWrapper and the checkpoint written here.
#
# Inputs (set by the generated caller script):
#   repo_root, soc_part, soc_threads, soc_out_dir,
#   spinal_netlist - SoC Verilog written by the core's LiteX SoC generator
#   spinal_inst    - directory holding the core's spinal_soc_inst.vh
#   spinal_rom_hex - boot ROM image ($readmemh, 32-bit words)
#   soc_clock_mhz  - optional; target clock for a timing estimate

set_param general.maxThreads $soc_threads
file mkdir $soc_out_dir

set res_dir [file join $repo_root src main resources]
read_verilog [list \
  $spinal_netlist \
  [file join $res_dir spinal SpinalRams.v] \
  [file join $res_dir spinal SpinalBoardWrapper.v]]

synth_design -mode out_of_context -flatten_hierarchy rebuilt \
  -top SpinalBoardWrapper -part $soc_part \
  -include_dirs [list $spinal_inst] \
  -generic "ROM_HEX=\"$spinal_rom_hex\""

report_utilization -file [file join $soc_out_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $soc_out_dir utilization-hier.rpt]
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
