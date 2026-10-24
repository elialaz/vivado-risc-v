------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Repository overlay of GRLIB's noelv_pma_cfg package (same unit name; the
-- native NOEL-V source list substitutes it for the upstream file, which stays
-- unmodified in the GRLIB submodule).
--
-- The upstream reset PMA describes GRLIB's reference memory map (RAM at 0,
-- I/O at 0xA0000000). With it, the board I/O window at 0x60000000 is
-- cacheable RAM: uncached device registers (UART status, SD, Ethernet) are
-- served from stale cache lines. This table describes the vivado-risc-v
-- board map instead. One bit per 256 MiB region (bit n = 0xn0000000).
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
library gaisler;
use gaisler.noelv.all;

package noelv_pma_cfg is

  -- Word 0: High type   00        01  10  11
  -- Word 1: Low       unallocated I/O RAM ROM
  -- Word 2: Cacheable (if RAM/ROM)
  -- Word 3: Wide bus
  constant pma_data_mask : word64_arr(0 to PMAENTRIES-1) := (
    -- 0x00000000-0x0fffffff ROM  cacheable   wide  boot ROM alias (0x10000)
    -- 0x10000000-0x5fffffff unallocated
    -- 0x60000000-0x6fffffff I/O  uncacheable wide  board UART/SD/Ethernet/XADC
    -- 0x70000000-0x7fffffff unallocated
    -- 0x80000000-0xafffffff RAM  cacheable   wide  DDR (768 MiB)
    -- 0xb0000000-0xbfffffff I/O  uncacheable wide  ACLINT
    -- 0xc0000000-0xcfffffff ROM  cacheable   wide  boot ROM (reset vector)
    -- 0xd0000000-0xffffffff I/O  uncacheable       debug module, PLIC, APB
    x"0000000000001701",      -- High type
    x"000000000000f841",      -- Low
    x"0000000000001701",      -- Cacheable
    x"0000000000001f41",      -- Wide bus
    others => zerow64
  );

end;

package body noelv_pma_cfg is
end;
