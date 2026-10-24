#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# GHDL boot-ROM simulation of the native NOEL-V board wrapper.
#
# GRLIB is compiled with its own generated GHDL script, using the `inferred`
# technology (no Xilinx simulation primitives needed). The repository wrapper,
# the generated boot ROM and the testbench go into library `work`.
#
# usage: sim-noelv-ghdl.sh <sim-dir> <boot-rom.vhd> <cfg> <tx-bytes> <max-us>
# GHDL selects the ghdl binary (default: ghdl in PATH). A GCC or mcode build
# is needed; the LLVM build in /tools/ghdl lacks its libLLVM-10 runtime.
set -euo pipefail
GHDL=${GHDL:-ghdl}
export PATH="$(dirname "$(command -v "$GHDL")"):$PATH"

repo=$(cd "$(dirname "$0")/../.." && pwd)
sim_dir=$(mkdir -p "$1" && cd "$1" && pwd)
rom=$2
cfg=$3
tx_bytes=$4
max_us=$5

grlib=$repo/generators/grlib
ref=$grlib/designs/noelv-generic
res=$repo/src/main/resources/noelv/native

cd "$sim_dir"
if [ ! -f make.ghdl ] ; then
  cp "$ref/Makefile" "$ref/.config" "$ref/config.vhd" .
  cp -r "$ref/cfg" .
  cp "$repo/src/main/resources/noelv/grlib_config.vhd" .
  mkdir -p rtl/core tb
  env -u MAKEFLAGS -u MFLAGS -u MAKEOVERRIDES -u MAKELEVEL \
    make scripts GRLIB="$grlib" TECHLIBS=inferred >scriptgen.log
  # Library sources only; the GRLIB example design's own `work` files are
  # replaced by the repository wrapper and testbench below.
  grep -v -- "--work=work .*\.vhd" make.ghdl |
    sed "s# [^ ]*/noelv/pkg[^ ]*/noelv_pma_cfg.vhd\$# $res/noelv_pma_cfg.vhd#" >make-libs.ghdl
  grep -q "$res/noelv_pma_cfg.vhd" make-libs.ghdl
  make -f make-libs.ghdl ghdl-import >ghdl-import.log
fi

paths=$(cat ghdl.path)
for f in "$rom" "$res/NOELVBoardSubsystem.vhd" "$res/NOELVBoardWrapper.vhd" \
         "$res/sim/tb_axi_slave.vhd" "$res/sim/tb_noelv.vhd" ; do
  ghdl -i --mb-comments --workdir=gnu/work --work=work $paths "$f"
done
ghdl -m -fexplicit --ieee=synopsys --mb-comments --warn-no-binding --warn-no-hide -O2 \
  --workdir=gnu/work --work=work $paths tb_noelv >ghdl-make.log 2>&1 || {
  tail -30 ghdl-make.log ; exit 1 ; }

./tb_noelv --assert-level=none --ieee-asserts=disable \
  -gcfg="$cfg" -gTX_BYTES="$tx_bytes" -gMAX_US="$max_us" \
  --stop-time=$((max_us + 100))us 2>&1 | tee sim.log | grep -a "UART TX\|TB_DONE\|OVERFLOW" || true
