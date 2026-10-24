# SPDX-License-Identifier: GPL-2.0-only
# Vivado xsim boot-ROM simulation of the native NOEL-V board wrapper
# (GRLIB inferred technology, real boot ROM, behavioral DDR and UART).
#
# Inputs (set by the generated caller script):
#   repo_root, soc_part, sim_dir, grlib_manifest, grlib_config, noelv_rom,
#   noelv_cfg, sim_tx_bytes (stop after this many UART bytes), sim_max_us

create_project -force sim-noelv [file join $sim_dir proj] -part $soc_part
set_property target_language VHDL [current_project]

set noelv_with_sim_only 1
source [file join $repo_root scripts native noelv-sources.tcl]

set tb_dir [file join $repo_root src main resources noelv native sim]
set tb_files [list \
  [file join $tb_dir tb_axi_slave.vhd] \
  [file join $tb_dir tb_noelv.vhd]]
add_files -fileset sim_1 -norecurse $tb_files
set wrapper_lib [get_property LIBRARY [get_files -of_objects [get_filesets sources_1] *NOELVBoardWrapper.vhd]]
set_property LIBRARY $wrapper_lib [get_files $tb_files]

set_property top NOELVBoardWrapper [get_filesets sources_1]
set_property top tb_noelv [get_filesets sim_1]
set_property top_lib $wrapper_lib [get_filesets sim_1]
set_property generic "cfg=$noelv_cfg tech=0 TX_BYTES=$sim_tx_bytes MAX_US=$sim_max_us" [get_filesets sim_1]
set_property -name {xsim.elaborate.debug_level} -value {typical} -objects [get_filesets sim_1]
set_property -name {xsim.elaborate.mt_level} -value {off} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value "[expr {$sim_max_us + 100}]us" -objects [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
close_sim
puts "NATIVE_NOELV_SIM_DONE"
