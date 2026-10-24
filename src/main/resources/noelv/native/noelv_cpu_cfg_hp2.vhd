------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Repository overlay of GRLIB lib/gaisler/noelv/pkg/noelv_cpu_cfg_custom.vhd,
-- used only by CONFIG=rocket64noelvhp2 (NOEL-V cfg=16#F00#, "custom").
--
-- The values are GRLIB's HP preset (noelv_cpu_cfg.vhd, cfg_a(0)) with the
-- branch history table raised from 128 to 512 entries (bhtnv allows up to
-- 1024). The other predictor sizes are already at the RTL maximum: the
-- pattern history travels in a 64-bit field, so bhtlength <= 5, and the core
-- uses the direct-mapped btbdmnv (at most 32 entries; btbsets is unused).
--
-- Two of these harts are ~163k LUTs, so with the L2 and a board shell this
-- configuration targets FPGAs larger than the Genesys 2 xc7k325t; see
-- noelv_cpu_cfg_hp2s.vhd (rocket64noelvhp2s) for the trimmed Genesys 2 fit.
--
-- L1 caches stay at the HP size (4 ways x 4 KiB, 32-byte lines): cctrl5nv
-- allows at most 4 ways and indexes with the virtual address, so a way larger
-- than the 4 KiB page would alias and break physical-address DMA snooping.
-- Extra capacity comes from the L2 (L2C-Lite) in NOELVBoardSubsystem.
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
library gaisler;
use gaisler.noelv_cfg_types.all;

package noelv_cpu_cfg_custom is

  constant noelv_cpu_cfg_custom0 : nv_cpu_cfg_type := (
    single_issue  => 0, -- Not Used
    ext_m         => 1,
    ext_a         => 1,
    ext_c         => 1,
    ext_h         => 1,
    ext_zcb       => 1,
    ext_zba       => 1,
    ext_zbb       => 1,
    ext_zbc       => 1,
    ext_zbs       => 1,
    ext_zbkb      => 1,
    ext_zbkc      => 1,
    ext_zbkx      => 1,
    ext_sscofpmf  => 1,
    ext_smcntrpmf => 1,
    ext_shlcofideleg => 1,
    ext_smcdeleg  => 1,
    ext_sstc      => 1,
    ext_smaia     => 1,
    ext_ssaia     => 1,
    ext_smstateen => 1,
    ext_smrnmi    => 1,
    ext_ssdbltrp  => 1,
    ext_smdbltrp  => 1,
    ext_smepmp    => 1,
    ext_svadu     => 1,
    ext_svpbmt    => 1,
    ext_smpmpmt   => 1,
    ext_svnapot   => 1,
    imsic         => 1,
    neiid         => 63,
    ext_capability  => 1,
    ext_diagnostics => 1,
    ext_hwassert  => 1,
    ext_noelv     => 1,
    ext_zicbom    => 1,
    ext_zicond    => 1,
    ext_zimop     => 1,
    ext_zcmop     => 1,
    ext_zicfiss   => 1,
    ext_zicfilp   => 1,
    ext_svinval   => 1,
    ext_zfa       => 1,
    ext_zfh       => 1,
    ext_zfhmin    => 1,
    ext_zfbfmin   => 1,
    mode_s        => 1,
    mode_u        => 1,
    fpulen        => 64,
    pmp_no_tor    => 0,
    pmp_entries   => 16,
    pmp_g         => 10,
    pma_entries   => 4,
    pma_masked    => 1,
    pma_readout   => 1,
    asidlen       => 8,
    vmidlen       => 4,
    perf_cnts     => 16,
    perf_evts     => 128,
    perf_bits     => 32,
    tbuf          => 4,
    trigger       => 2048*2 + 1024*1 + 32*4 + 4,
    icen          => 1,
    iways         => 4,
    iwaysize      => 4,
    ilinesize     => 8,
    dcen          => 1,
    dways         => 4,
    dwaysize      => 4,
    dlinesize     => 8,
    mmuen         => 1,
    itlbnum       => 24,
    dtlbnum       => 24,
    htlbnum       => 16,
    tlbrepl       => 1,
    riscv_mmu     => 3,
    tlb_pmp       => 0,
    div_hiperf    => 1,
    div_small     => 0,
    no_muladd     => 0,
    late_branch   => 1,
    late_alu      => 1,
    ras           => 2,
    bhtentries    => 512,
    bhtlength     => 5,
    predictor     => 2,
    btbentries    => 32,
    btbsets       => 2,
    dmen          => 1,
    pbaddr        => 16#F8400#,
    rstaddr       => 16#C0000#
  );

end;

package body noelv_cpu_cfg_custom is
end;
