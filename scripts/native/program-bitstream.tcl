if {![info exists ::env(HW_SERVER_URL)]} {
  error "HW_SERVER_URL is required"
}
if {![info exists ::env(BITSTREAM)] || ![file exists $::env(BITSTREAM)]} {
  error "BITSTREAM does not name an existing file"
}
if {![info exists ::env(FPGA_TARGET)]} {
  error "FPGA_TARGET is required"
}

connect -url $::env(HW_SERVER_URL)
set target_filter [format {name =~ "%s"} $::env(FPGA_TARGET)]
if {[catch {targets -set -filter $target_filter} target_error]} {
  error "Cannot select FPGA '$::env(FPGA_TARGET)' on $::env(HW_SERVER_URL): $target_error"
}

puts "Programming native bitstream: $::env(BITSTREAM)"
fpga $::env(BITSTREAM)
puts "NATIVE_FPGA_PROGRAMMED"
