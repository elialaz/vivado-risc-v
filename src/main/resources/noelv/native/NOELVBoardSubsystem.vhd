------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Native NOEL-V SoC for the repository board shells.
--
-- GRLIB's official NOEL-V processor subsystem (noelvsys: CPU, FPU, debug
-- module, ACLINT, PLIC, AHB/APB) plus the bridges to the repository's common
-- board contract. No Chisel, Diplomacy or TileLink is involved.
--
-- Address map (CPU view):
--   0x0001_0000  boot ROM alias at the repository-standard ROM address
--                (the common loader passes its DTB at 0x10080)
--   0x6000_0000  board I/O (UART, SD, Ethernet, XADC) -> IO AXI4, uncached
--   0x8000_0000  DDR, 768 MiB -> MEM AXI4 (noelvsys keeps its ACLINT at
--                0xB000_0000, so DDR stops at 0xB000_0000)
--   0xB000_0000  ACLINT (noelvsys)
--   0xC000_0000  boot ROM (stock NOEL-V reset vector)
--   0xE000_0000  debug module, 0xF840_0000 program buffer (noelvsys)
--   0xFC00_0000  PLIC, 0xFF90_0000 internal APB (noelvsys)
--
-- Board DMA (SD, Ethernet) enters as an AHB master on the CPU bus, so the
-- L1 data cache snoops it (enabled by the boot ROM through CSR 0x7C1).
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
library grlib;
use grlib.amba.all;
use grlib.stdlib.all;
use grlib.devices.all;
use grlib.config.all;
use grlib.config_types.all;
library techmap;
use techmap.gencomp.all;
library gaisler;
use gaisler.uart.all;
use gaisler.misc.all;
use gaisler.jtag.all;
use gaisler.axi.all;
use gaisler.l2c_lite.all;
use gaisler.noelv.all;

entity NOELVBoardSubsystem is
  generic (
    cfg     : integer := 16#300#;       -- NOEL-V preset: 16#300# GP, 16#400# HP,
                                        -- 16#F00# custom (noelv_cpu_cfg_hp2.vhd)
    -- L2C-Lite in front of DDR: way size in KiB (0 = no L2, plain bridge).
    -- With the L2, DDR is one 512 MiB window (L2C-Lite has a single
    -- memory BAR and 0xB000_0000 belongs to the noelvsys ACLINT).
    ncpu       : integer := 1;          -- harts (SMP: L1s snoop the AHB bus)
    l2_ways    : integer := 4;
    l2_waysize : integer := 0;
    fabtech : integer := kintex7;       -- simulation uses inferred
    memtech : integer := kintex7
  );
  port (
    clk        : in  std_ulogic;
    rstn       : in  std_ulogic;
    -- Board interrupts (level, already synchronized)
    board_irq  : in  std_logic_vector(7 downto 0);
    -- DDR (addresses are CPU physical, 0x8000_0000 based)
    mem_aximi  : in  axi_somi_type;
    mem_aximo  : out axi4_mosi_type;
    -- Board I/O
    io_aximi   : in  axi_somi_type;
    io_aximo   : out axi4_mosi_type;
    -- Board DMA ingress; the extension records carry the upper 4 ID bits
    dma_axisi  : in  axi4_mosi_type;
    dma_axixsi : in  extaxi_mosi_type;
    dma_axiso  : out axi_somi_type;
    dma_axixso : out extaxi_miso_type
  );
end;

architecture rtl of NOELVBoardSubsystem is

  constant nextmst : integer := 1;      -- board DMA
  constant nextslv : integer := 3;      -- DDR, ROM, board I/O
  constant ndbgmst : integer := 1;      -- AHBJTAG (GRMON)

  constant DMA_HMINDEX : integer := ncpu;
  constant MEM_HSINDEX : integer := 0;
  constant ROM_HSINDEX : integer := 1;
  constant IO_HSINDEX  : integer := 2;
  constant JTAG_DMINDEX : integer := 0;

  -- PLIC sources used by the board interrupts: board_irq(i) -> source 5+i.
  -- Sources 1-4 are taken by noelvsys (APBUART, GPTIMER, ETRACE).
  constant BOARD_IRQ_BASE : integer := 5;

  -- 256 MiB regions that accept full 64-bit bus accesses: 0x0 (ROM alias),
  -- 0x6 (board I/O), 0x8-0xA (DDR), 0xB (ACLINT), 0xC (ROM). Matches the
  -- "wide" word of the board PMA (noelv_pma_cfg.vhd overlay), which also
  -- makes 0x6 uncacheable I/O; the stock PMA would cache it.
  constant WBMASK : integer := 16#1F41#;

  signal gclk   : std_logic_vector(ncpu-1 downto 0);

  signal ahbmi  : ahb_mst_in_type;
  signal ahbmo  : ahb_mst_out_vector := (others => ahbm_none);
  signal ahbsi  : ahb_slv_in_type;
  signal ahbso  : ahb_slv_out_vector := (others => ahbs_none);
  signal io_so  : ahb_slv_out_type;
  signal dbgmi  : ahb_mst_in_vector_type(ndbgmst-1 downto 0);
  signal dbgmo  : ahb_mst_out_vector_type(ndbgmst-1 downto 0);
  signal apbi   : apb_slv_in_type;
  signal apbo   : apb_slv_out_vector := (others => apb_none);

  signal u0i    : uart_in_type;
  signal u0o    : uart_out_type;

begin

  gclk <= (others => clk);

  ----------------------------------------------------------------------------
  -- NOEL-V processor subsystem (official GRLIB)
  ----------------------------------------------------------------------------
  noelv0 : noelvsys
    generic map (
      fabtech  => fabtech,
      memtech  => memtech,
      ncpu     => ncpu,
      nextmst  => nextmst,
      nextslv  => nextslv,
      nextapb  => 0,
      ndbgmst  => ndbgmst,
      neiid    => 63,
      cached   => 0,                    -- cacheability from plug&play bars
      wbmask   => WBMASK,
      busw     => AHBDW,
      cmemconf => 2,
      rfconf   => 0,
      fpuconf  => 0,
      tcmconf  => 0,
      mulconf  => 0,
      intcconf => 0,                    -- PLIC only
      disas    => 0,
      ahbtrace => 0,
      cfg      => cfg,
      devid    => 0,
      nodbus   => 1,
      trace    => 0,
      scantest => 0)
    port map (
      clk      => clk,
      gclk     => gclk,
      rstn     => rstn,
      pwrd     => open,
      ahbmi    => ahbmi,
      ahbmo    => ahbmo(ncpu+nextmst-1 downto ncpu),
      ahbsi    => ahbsi,
      ahbso    => ahbso(nextslv-1 downto 0),
      dbgmi    => dbgmi,
      dbgmo    => dbgmo,
      apbi     => apbi,
      apbo     => apbo,
      dsuen    => '1',                  -- debug module enabled
      dsubreak => '0',                  -- boot normally, do not halt
      cpu0errn => open,
      stoptime => open,
      cpuerrn  => open,
      uarti    => u0i,
      uarto    => u0o,
      cnt      => open,
      etso     => open);

  -- The internal APBUART is not used; the console is the board UART.
  u0i.rxd    <= '1';
  u0i.ctsn   <= '0';
  u0i.extclk <= '0';

  ----------------------------------------------------------------------------
  -- DDR: AHB slave -> AXI4 master. 0x8000_0000 + 768 MiB.
  ----------------------------------------------------------------------------
  nol2 : if l2_waysize = 0 generate
    mem0 : ahb2axi4b
      generic map (
        hindex          => MEM_HSINDEX,
        aximid          => 0,
        wbuffer_num     => 8,
        rprefetch_num   => 8,
        endianness_mode => 0,
        narrow_acc_mode => 0,
        vendor          => VENDOR_GAISLER,
        device          => GAISLER_AHB2AXI,   -- GPL bridge ID (GRMON eval accepts it)
        bar0            => ahb2ahb_membar(16#800#, '1', '1', 16#E00#),  -- 512 MiB
        bar1            => ahb2ahb_membar(16#A00#, '1', '1', 16#F00#))  -- 256 MiB
      port map (
        rstn  => rstn,
        clk   => clk,
        ahbsi => ahbsi,
        ahbso => ahbso(MEM_HSINDEX),
        aximi => mem_aximi,
        aximo => mem_aximo);
  end generate;

  ----------------------------------------------------------------------------
  -- DDR behind GRLIB L2C-Lite (write-back, PLRU): 0x8000_0000 + 512 MiB.
  -- Board DMA enters on the same AHB bus, so it goes through the L2 too and
  -- stays coherent with it. Control/statistics registers in the AHB I/O
  -- area at 0xFFF0_1000 (enabled at reset).
  ----------------------------------------------------------------------------
  l2 : if l2_waysize /= 0 generate
    l2c0 : l2c_lite_axi4
      generic map (
        tech     => memtech,
        hmindex  => 0,
        hsindex  => MEM_HSINDEX,
        ways     => l2_ways,
        waysize  => l2_waysize,
        linesize => 32,
        repl     => 0,
        haddr    => 16#800#,
        hmask    => 16#E00#,
        ioaddr   => 16#010#,
        cached   => 16#0300#,               -- 256 MiB regions 0x8 and 0x9
        be_dw    => AHBDW)
      port map (
        rstn  => rstn,
        clk   => clk,
        ahbsi => ahbsi,
        ahbso => ahbso(MEM_HSINDEX),
        aximi => mem_aximi,
        aximo => mem_aximo);
  end generate;

  ----------------------------------------------------------------------------
  -- Boot ROM: 0xC000_0000 (reset vector) and 0x0001_0000 alias (1 MiB window)
  ----------------------------------------------------------------------------
  rom0 : entity work.NOELVBootRom
    generic map (
      hindex => ROM_HSINDEX,
      haddr  => 16#C00#,
      hmask  => 16#FFF#,
      haddr2 => 16#000#,
      hmask2 => 16#FFF#)
    port map (
      rst   => rstn,
      clk   => clk,
      ahbsi => ahbsi,
      ahbso => ahbso(ROM_HSINDEX));

  ----------------------------------------------------------------------------
  -- Board I/O: AHB slave -> AXI4 master, uncached, no read prefetch so that
  -- every register read is a single AXI beat. 0x6000_0000 + 1 MiB.
  --
  -- Plug&play: only device IDs used by GPL GRLIB designs are advertised
  -- (AHBROM, MIG_7SERIES, AHBJTAG). GRMON evaluation versions refuse designs
  -- with other IDs, so the I/O bridge and the DMA master below carry an empty
  -- identification; AHB decoding uses only their address bars.
  ----------------------------------------------------------------------------
  io0 : ahb2axi4b
    generic map (
      hindex          => IO_HSINDEX,
      aximid          => 0,
      wbuffer_num     => 1,
      rprefetch_num   => 1,
      endianness_mode => 0,
      narrow_acc_mode => 0,
      vendor          => 0,
      device          => 0,
      bar0            => ahb2ahb_membar(16#600#, '0', '0', 16#FFF#))
    port map (
      rstn  => rstn,
      clk   => clk,
      ahbsi => ahbsi,
      ahbso => io_so,
      aximi => io_aximi,
      aximo => io_aximo);

  -- Board interrupts enter the PLIC through this slave's AHB interrupt lines.
  io_irq : process (io_so, board_irq)
    variable v : ahb_slv_out_type;
  begin
    v := io_so;
    for i in board_irq'range loop
      v.hirq(BOARD_IRQ_BASE + i) := board_irq(i);
    end loop;
    ahbso(IO_HSINDEX) <= v;
  end process;

  ----------------------------------------------------------------------------
  -- Board DMA: AXI4 slave -> AHB master on the CPU bus (snooped by the L1)
  ----------------------------------------------------------------------------
  dma0 : axi2ahb
    generic map (
      memtech     => memtech,
      hindex      => DMA_HMINDEX,
      dbuffer     => 16,
      wordsize    => AHBDW,
      axi_endian  => 1,                 -- the board DMA masters are little-endian
      vendorid    => 0,                 -- no plug&play identification (GRMON eval)
      deviceid    => 0,
      ext_idwidth => 4)                 -- 4 + 4 = all 8 board ID bits
    port map (
      resetn => rstn,
      clk    => clk,
      axisi  => dma_axisi,
      axixsi => dma_axixsi,
      axiso  => dma_axiso,
      axixso => dma_axixso,
      ahbmi  => ahbmi,
      ahbmo  => ahbmo(DMA_HMINDEX),
      ahbmxa => open);

  ----------------------------------------------------------------------------
  -- Debug link: GRLIB AHBJTAG over the FPGA's own JTAG (BSCANE2) for GRMON3
  ----------------------------------------------------------------------------
  jtag0 : ahbjtag
    generic map (
      tech   => fabtech,
      hindex => JTAG_DMINDEX,
      nsync  => 2,
      versel => 1)
    port map (
      rst       => rstn,
      clk       => clk,
      tck       => '0',
      tms       => '0',
      tdi       => '0',
      tdo       => open,
      ahbi      => dbgmi(JTAG_DMINDEX),
      ahbo      => dbgmo(JTAG_DMINDEX),
      tapo_tck  => open,
      tapo_tdi  => open,
      tapo_inst => open,
      tapo_rst  => open,
      tapo_capt => open,
      tapo_shft => open,
      tapo_upd  => open,
      tapi_tdo  => '0',
      trst      => '1',
      tdoen     => open,
      tckn      => '0',
      tapo_tckn => open,
      tapo_ninst => open,
      tapo_iupd => open);

end;
