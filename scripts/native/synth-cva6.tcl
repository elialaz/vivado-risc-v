# Synthesize the native CVA6 SoC as an isolated out-of-context netlist.
#
# The board project never sees CVA6's SystemVerilog sources or headers: it
# only gets the Verilog shim (CVA6BoardVivado.v), a black-box stub for
# CVA6BoardWrapper, and the checkpoint written here. This keeps SV-only
# headers such as common_cells/registers.svh out of the board IP runs.
#
# Inputs (set by the generated caller script):
#   repo_root, soc_part, soc_threads, soc_out_dir,
#   cva6_root      - CVA6 checkout (default generators/cva6)
#   cva6_patched   - directory of patched copies of CVA6 files (same
#                    relative paths), used in place of the originals
#   cva6_sources   - per-CONFIG copy of the upstream add_sources.tcl
#   cva6_bootrom   - backend-composed bootrom_64.sv
#   cva6_cached_ddr - 0 or 1 (CVA6BoardWrapper CachedDdr parameter)
#   cva6_time_csr   - 0 or 1 (CVA6BoardWrapper TimeCsr parameter)

set_param general.maxThreads $soc_threads
# A throwaway project, only so Vivado orders the SV packages for us.
create_project -force soc-cva6 [file join $soc_out_dir proj] -part $soc_part

if {![info exists cva6_root]} {
  set cva6_root [file join $repo_root generators cva6]
}
set cva6_fpga [file join $cva6_root corev_apu fpga]
set res_dir   [file join $repo_root src main resources cva6]

file mkdir $soc_out_dir

# Upstream reference-board files that the repository shell replaces.
set excluded [list \
  [file join $cva6_fpga src ariane_peripherals_xilinx.sv] \
  [file join $cva6_fpga src ariane_xilinx.sv] \
  [file join $cva6_fpga src fan_ctrl.sv] \
  [file join $cva6_fpga src bootrom bootrom_64.sv] \
  [file join $cva6_fpga src bootrom bootrom_32.sv]]
foreach f [glob -nocomplain -directory [file join $cva6_fpga src ariane-ethernet] *] {
  lappend excluded $f
}
set excluded [lmap f $excluded {file normalize $f}]

# Patched copies replace the original CVA6 files of the same relative path.
set replaced [dict create]
proc collect_patched {base dir} {
  upvar replaced replaced cva6_root cva6_root
  foreach f [glob -nocomplain -directory $dir *] {
    if {[file isdirectory $f]} {
      collect_patched $base $f
    } elseif {[file tail $f] ne ".stamp"} {
      set rel [string range $f [expr {[string length $base] + 1}] end]
      dict set replaced [file normalize [file join $cva6_root $rel]] $f
    }
  }
}
if {[info exists cva6_patched] && [file isdirectory $cva6_patched]} {
  collect_patched [file normalize $cva6_patched] [file normalize $cva6_patched]
}

# The manifest is a list of `read_vhdl {...}` / `read_verilog -sv {...}`
# lines. Replay it with the excluded files filtered out.
set channel [open $cva6_sources r]
set manifest [read $channel]
close $channel
foreach line [split $manifest "\n"] {
  set line [string trim $line]
  if {$line eq ""} { continue }
  if {[regexp {^read_vhdl\s+\{(.*)\}$} $line -> files]} {
    set cmd [list add_files -norecurse]
  } elseif {[regexp {^read_verilog\s+-sv\s+\{(.*)\}$} $line -> files]} {
    set cmd [list add_files -norecurse]
  } else {
    error "Unexpected CVA6 manifest line: $line"
  }
  set keep [list]
  foreach f $files {
    set n [file normalize $f]
    if {[lsearch -exact $excluded $n] >= 0} { continue }
    if {[dict exists $replaced $n]} {
      puts "CVA6 patched source: [dict get $replaced $n]"
      lappend keep [dict get $replaced $n]
      dict unset replaced $n
    } else {
      lappend keep $f
    }
  }
  if {[llength $keep] != 0} {
    {*}$cmd $keep
  }
}

if {[dict size $replaced] != 0} {
  error "Patched CVA6 files not in the source manifest: [dict keys $replaced]"
}

# Repository BSCANE2 DMI transport shared with the Rocket flow.
set vhdl_wrapper [file join $repo_root vhdl-wrapper src net largest riscv vhdl]
add_files -norecurse [list \
  [file join $vhdl_wrapper sync.vhdl] \
  [file join $vhdl_wrapper jtag.vhdl]]

# AXI ID remapper (vendored pulp AXI; not in the upstream FPGA manifest).
add_files -norecurse [file join $cva6_root vendor pulp-platform axi src axi_id_remap.sv]

add_files -norecurse [list $cva6_bootrom \
  [file join $res_dir CVA6Core.sv] \
  [file join $res_dir CVA6BoardSubsystem.sv] \
  [file join $res_dir CVA6BoardWrapper.sv]]
set sv_files [get_files -quiet *.sv]
if {[llength $sv_files] != 0} {
  set_property file_type SystemVerilog $sv_files
}

set include_dirs [list \
  [file join $cva6_fpga src axi_sd_bridge include] \
  [file join $cva6_root vendor pulp-platform common_cells include] \
  [file join $cva6_root vendor pulp-platform axi include] \
  [file join $cva6_root core cache_subsystem hpdcache rtl include] \
  [file join $cva6_root core cache_subsystem hpdcache rtl src utils ecc] \
  [file join $cva6_root corev_apu register_interface include] \
  [file join $cva6_root corev_apu instr_tracing ITI include] \
  [file join $cva6_root core include]]

set_property include_dirs $include_dirs [current_fileset]
set_property top CVA6BoardWrapper [current_fileset]
update_compile_order -fileset sources_1

synth_design -mode out_of_context -flatten_hierarchy rebuilt \
  -top CVA6BoardWrapper -part $soc_part \
  -include_dirs $include_dirs \
  -generic CachedDdr=$cva6_cached_ddr \
  -generic TimeCsr=$cva6_time_csr

report_utilization -file [file join $soc_out_dir utilization.rpt]
write_checkpoint -force [file join $soc_out_dir soc.dcp]
set stub_file [file join $soc_out_dir soc_stub.v]
write_verilog -force -mode synth_stub $stub_file
# Make the black box explicit for Vivado synthesis of the board project.
set channel [open $stub_file r]
set stub [read $channel]
close $channel
regsub {\nmodule } $stub "\n(* black_box = \"yes\" *)\nmodule " stub
set channel [open $stub_file w]
puts -nonewline $channel $stub
close $channel
puts "NATIVE_SOC_NETLIST_READY: $soc_out_dir"
