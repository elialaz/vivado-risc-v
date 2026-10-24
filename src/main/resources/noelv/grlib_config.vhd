-- SPDX-License-Identifier: GPL-2.0-only
-- Project-local GRLIB global configuration for the common 64-bit SoC bus.

library ieee;
use ieee.std_logic_1164.all;
library grlib;
use grlib.config_types.all;

package config is
  constant CFG_AHBDW : integer := 64;
  constant CFG_AHB_ACDM : integer := 0;
  constant GRLIB_CONFIG_ARRAY : grlib_config_array_type := (
    grlib_debug_level             => 0,
    grlib_debug_mask              => 0,
    grlib_techmap_strict_ram      => 0,
    grlib_techmap_testin_extra    => 0,
    grlib_sync_reset_enable_all   => 1,
    grlib_async_reset_enable      => 0,
    grlib_amba_inc_nirq           => 1,
    grlib_little_endian           => 1,
    others                        => 0);
end package;
