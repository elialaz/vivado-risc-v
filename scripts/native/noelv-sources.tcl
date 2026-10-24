# SPDX-License-Identifier: GPL-2.0-only
# Add the native NOEL-V SoC sources (GRLIB libraries in scriptgen order, the
# generated boot ROM and the repository wrapper) to the current project.
# Shared by synth-noelv.tcl and sim-noelv.tcl.
#
# Inputs: repo_root, grlib_manifest, grlib_config, noelv_rom,
#         noelv_cfg_custom (optional overlay of noelv_cpu_cfg_custom.vhd)
#         noelv_with_sim_only (optional, 1 = also add GRLIB's simulation-only
#         files, marked used_in_synthesis false; needed by xsim)

set res_dir [file join $repo_root src main resources noelv native]
set manifest_dir [file dirname [file dirname $grlib_manifest]]

proc manifest_path {dir path} {
  return [file normalize [file join $dir [string trim $path]]]
}

# Pass 1: files GRLIB marks as simulation-only.
set channel [open $grlib_manifest r]
set manifest [split [read $channel] "\n"]
close $channel
array set sim_only {}
foreach line $manifest {
  if {[regexp {^set_property used_in_synthesis false \[get_files (.+)\]$} \
      [string trim $line] -> path]} {
    set sim_only([manifest_path $manifest_dir $path]) 1
  }
}

# Pass 2: GRLIB library sources in scriptgen order. The design's own `work`
# files (GRLIB's noelvmp example top) are not used; the repository GRLIB
# configuration replaces the generated grlib_config.vhd.
array set seen {}
set nfiles 0
foreach line $manifest {
  set line [string trim $line]
  # GRLIB's only Verilog entry here is a simulation model (i2c_slave_model).
  if {![regexp {^read_vhdl -library ([^ ]+) (.+)$} $line -> library path]} {
    continue
  }
  if {$library eq "work"} { continue }
  set path [manifest_path $manifest_dir $path]
  if {[file tail $path] eq "grlib_config.vhd"} { set path $grlib_config }
  # Board PMA overlay (the upstream reset PMA assumes GRLIB's reference map).
  if {[string match */lib/gaisler/noelv/pkg/noelv_pma_cfg.vhd $path]} {
    set path [file join $repo_root src main resources noelv native noelv_pma_cfg.vhd]
  }
  # Per-CONFIG custom CPU preset (cfg=16#F00#), e.g. rocket64noelvhp2.
  if {[info exists noelv_cfg_custom] && $noelv_cfg_custom ne "" &&
      [string match */lib/gaisler/noelv/pkg/noelv_cpu_cfg_custom.vhd $path]} {
    set path $noelv_cfg_custom
  }
  if {[info exists seen($path)]} { continue }
  set is_sim_only [info exists sim_only($path)]
  if {$is_sim_only && !([info exists noelv_with_sim_only] && $noelv_with_sim_only)} { continue }
  # The SPARC disassembler defines a second grlib.cpu_disas; NOEL-V uses the
  # RISC-V one.
  if {$is_sim_only && [string match */lib/grlib/sparc/* $path]} { continue }
  set seen($path) 1
  read_vhdl -library $library $path
  if {$is_sim_only} {
    set_property used_in_synthesis false [get_files $path]
  }
  incr nfiles
}
puts "NATIVE_NOELV_GRLIB_SOURCES: $nfiles"

read_vhdl -library work [list \
  $noelv_rom \
  [file join $res_dir NOELVBoardSubsystem.vhd] \
  [file join $res_dir NOELVBoardWrapper.vhd]]

