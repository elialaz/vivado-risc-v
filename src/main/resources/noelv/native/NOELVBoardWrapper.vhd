------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Flat board-shell boundary for NOELVBoardSubsystem. Same contract as
-- CVA6BoardWrapper: reset sequencing, interrupt synchronization, the three
-- AXI4 buses, and translation of the CPU DDR base (0x8000_0000) to the
-- MIG-local address space of the board shell.
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library grlib;
use grlib.amba.all;
library techmap;
use techmap.gencomp.all;
library gaisler;
use gaisler.axi.all;

entity NOELVBoardWrapper is
  generic (
    cfg        : integer := 16#300#;
    ncpu       : integer := 1;
    l2_ways    : integer := 4;
    l2_waysize : integer := 0;          -- KiB per L2 way, 0 = no L2
    fabtech : integer := kintex7;
    memtech : integer := kintex7);
  port (
    clock            : in  std_logic;
    clock_ok         : in  std_logic;
    mem_ok           : in  std_logic;
    io_ok            : in  std_logic;
    sys_reset        : in  std_logic;
    aresetn          : out std_logic;
    interrupts       : in  std_logic_vector(7 downto 0);

    mem_axi4_awready : in  std_logic;
    mem_axi4_awvalid : out std_logic;
    mem_axi4_awid    : out std_logic_vector(3 downto 0);
    mem_axi4_awaddr  : out std_logic_vector(33 downto 0);
    mem_axi4_awlen   : out std_logic_vector(7 downto 0);
    mem_axi4_awsize  : out std_logic_vector(2 downto 0);
    mem_axi4_awburst : out std_logic_vector(1 downto 0);
    mem_axi4_awlock  : out std_logic;
    mem_axi4_awcache : out std_logic_vector(3 downto 0);
    mem_axi4_awprot  : out std_logic_vector(2 downto 0);
    mem_axi4_awqos   : out std_logic_vector(3 downto 0);
    mem_axi4_wready  : in  std_logic;
    mem_axi4_wvalid  : out std_logic;
    mem_axi4_wdata   : out std_logic_vector(63 downto 0);
    mem_axi4_wstrb   : out std_logic_vector(7 downto 0);
    mem_axi4_wlast   : out std_logic;
    mem_axi4_bready  : out std_logic;
    mem_axi4_bvalid  : in  std_logic;
    mem_axi4_bid     : in  std_logic_vector(3 downto 0);
    mem_axi4_bresp   : in  std_logic_vector(1 downto 0);
    mem_axi4_arready : in  std_logic;
    mem_axi4_arvalid : out std_logic;
    mem_axi4_arid    : out std_logic_vector(3 downto 0);
    mem_axi4_araddr  : out std_logic_vector(33 downto 0);
    mem_axi4_arlen   : out std_logic_vector(7 downto 0);
    mem_axi4_arsize  : out std_logic_vector(2 downto 0);
    mem_axi4_arburst : out std_logic_vector(1 downto 0);
    mem_axi4_arlock  : out std_logic;
    mem_axi4_arcache : out std_logic_vector(3 downto 0);
    mem_axi4_arprot  : out std_logic_vector(2 downto 0);
    mem_axi4_arqos   : out std_logic_vector(3 downto 0);
    mem_axi4_rready  : out std_logic;
    mem_axi4_rvalid  : in  std_logic;
    mem_axi4_rid     : in  std_logic_vector(3 downto 0);
    mem_axi4_rdata   : in  std_logic_vector(63 downto 0);
    mem_axi4_rresp   : in  std_logic_vector(1 downto 0);
    mem_axi4_rlast   : in  std_logic;

    io_axi4_awready  : in  std_logic;
    io_axi4_awvalid  : out std_logic;
    io_axi4_awid     : out std_logic_vector(3 downto 0);
    io_axi4_awaddr   : out std_logic_vector(30 downto 0);
    io_axi4_awlen    : out std_logic_vector(7 downto 0);
    io_axi4_awsize   : out std_logic_vector(2 downto 0);
    io_axi4_awburst  : out std_logic_vector(1 downto 0);
    io_axi4_awlock   : out std_logic;
    io_axi4_awcache  : out std_logic_vector(3 downto 0);
    io_axi4_awprot   : out std_logic_vector(2 downto 0);
    io_axi4_awqos    : out std_logic_vector(3 downto 0);
    io_axi4_wready   : in  std_logic;
    io_axi4_wvalid   : out std_logic;
    io_axi4_wdata    : out std_logic_vector(63 downto 0);
    io_axi4_wstrb    : out std_logic_vector(7 downto 0);
    io_axi4_wlast    : out std_logic;
    io_axi4_bready   : out std_logic;
    io_axi4_bvalid   : in  std_logic;
    io_axi4_bid      : in  std_logic_vector(3 downto 0);
    io_axi4_bresp    : in  std_logic_vector(1 downto 0);
    io_axi4_arready  : in  std_logic;
    io_axi4_arvalid  : out std_logic;
    io_axi4_arid     : out std_logic_vector(3 downto 0);
    io_axi4_araddr   : out std_logic_vector(30 downto 0);
    io_axi4_arlen    : out std_logic_vector(7 downto 0);
    io_axi4_arsize   : out std_logic_vector(2 downto 0);
    io_axi4_arburst  : out std_logic_vector(1 downto 0);
    io_axi4_arlock   : out std_logic;
    io_axi4_arcache  : out std_logic_vector(3 downto 0);
    io_axi4_arprot   : out std_logic_vector(2 downto 0);
    io_axi4_arqos    : out std_logic_vector(3 downto 0);
    io_axi4_rready   : out std_logic;
    io_axi4_rvalid   : in  std_logic;
    io_axi4_rid      : in  std_logic_vector(3 downto 0);
    io_axi4_rdata    : in  std_logic_vector(63 downto 0);
    io_axi4_rresp    : in  std_logic_vector(1 downto 0);
    io_axi4_rlast    : in  std_logic;

    dma_axi4_awready : out std_logic;
    dma_axi4_awvalid : in  std_logic;
    dma_axi4_awid    : in  std_logic_vector(7 downto 0);
    dma_axi4_awaddr  : in  std_logic_vector(33 downto 0);
    dma_axi4_awlen   : in  std_logic_vector(7 downto 0);
    dma_axi4_awsize  : in  std_logic_vector(2 downto 0);
    dma_axi4_awburst : in  std_logic_vector(1 downto 0);
    dma_axi4_awlock  : in  std_logic;
    dma_axi4_awcache : in  std_logic_vector(3 downto 0);
    dma_axi4_awprot  : in  std_logic_vector(2 downto 0);
    dma_axi4_awqos   : in  std_logic_vector(3 downto 0);
    dma_axi4_wready  : out std_logic;
    dma_axi4_wvalid  : in  std_logic;
    dma_axi4_wdata   : in  std_logic_vector(63 downto 0);
    dma_axi4_wstrb   : in  std_logic_vector(7 downto 0);
    dma_axi4_wlast   : in  std_logic;
    dma_axi4_bready  : in  std_logic;
    dma_axi4_bvalid  : out std_logic;
    dma_axi4_bid     : out std_logic_vector(7 downto 0);
    dma_axi4_bresp   : out std_logic_vector(1 downto 0);
    dma_axi4_arready : out std_logic;
    dma_axi4_arvalid : in  std_logic;
    dma_axi4_arid    : in  std_logic_vector(7 downto 0);
    dma_axi4_araddr  : in  std_logic_vector(33 downto 0);
    dma_axi4_arlen   : in  std_logic_vector(7 downto 0);
    dma_axi4_arsize  : in  std_logic_vector(2 downto 0);
    dma_axi4_arburst : in  std_logic_vector(1 downto 0);
    dma_axi4_arlock  : in  std_logic;
    dma_axi4_arcache : in  std_logic_vector(3 downto 0);
    dma_axi4_arprot  : in  std_logic_vector(2 downto 0);
    dma_axi4_arqos   : in  std_logic_vector(3 downto 0);
    dma_axi4_rready  : in  std_logic;
    dma_axi4_rvalid  : out std_logic;
    dma_axi4_rid     : out std_logic_vector(7 downto 0);
    dma_axi4_rdata   : out std_logic_vector(63 downto 0);
    dma_axi4_rresp   : out std_logic_vector(1 downto 0);
    dma_axi4_rlast   : out std_logic);
end;

architecture rtl of NOELVBoardWrapper is

  signal reset_inp    : std_logic;
  signal reset_sync   : std_logic_vector(2 downto 0);
  signal reset_count  : unsigned(5 downto 0);
  signal aresetn_r    : std_logic;
  signal core_reset_n : std_logic;
  signal irq_meta     : std_logic_vector(7 downto 0);
  signal irq_sync     : std_logic_vector(7 downto 0);

  signal mem_mo  : axi4_mosi_type;
  signal mem_mi  : axi_somi_type;
  signal io_mo   : axi4_mosi_type;
  signal io_mi   : axi_somi_type;
  signal dma_si  : axi4_mosi_type;
  signal dma_xsi : extaxi_mosi_type;
  signal dma_so  : axi_somi_type;
  signal dma_xso : extaxi_miso_type;

begin

  ----------------------------------------------------------------------------
  -- Reset: wait for clocks, DDR and I/O; release the fabric after 16 cycles
  -- and the CPU after 32 (same sequence as CVA6BoardWrapper).
  ----------------------------------------------------------------------------
  reset_inp <= sys_reset or not clock_ok or not mem_ok or not io_ok;

  process (clock, reset_inp)
  begin
    if reset_inp = '1' then
      reset_sync <= (others => '1');
    elsif rising_edge(clock) then
      reset_sync <= reset_sync(1 downto 0) & '0';
    end if;
  end process;

  process (clock, reset_sync(2))
  begin
    if reset_sync(2) = '1' then
      reset_count  <= (others => '0');
      aresetn_r    <= '0';
      core_reset_n <= '0';
    elsif rising_edge(clock) then
      if reset_count /= 63 then reset_count <= reset_count + 1; end if;
      if reset_count >= 15 then aresetn_r <= '1'; end if;
      if reset_count >= 31 then core_reset_n <= '1'; end if;
    end if;
  end process;

  aresetn <= aresetn_r;

  process (clock, core_reset_n)
  begin
    if core_reset_n = '0' then
      irq_meta <= (others => '0');
      irq_sync <= (others => '0');
    elsif rising_edge(clock) then
      irq_meta <= interrupts;
      irq_sync <= irq_meta;
    end if;
  end process;

  soc : entity work.NOELVBoardSubsystem
    generic map (cfg => cfg, ncpu => ncpu, l2_ways => l2_ways, l2_waysize => l2_waysize,
                 fabtech => fabtech, memtech => memtech)
    port map (
      clk        => clock,
      rstn       => core_reset_n,
      board_irq  => irq_sync,
      mem_aximi  => mem_mi,
      mem_aximo  => mem_mo,
      io_aximi   => io_mi,
      io_aximo   => io_mo,
      dma_axisi  => dma_si,
      dma_axixsi => dma_xsi,
      dma_axiso  => dma_so,
      dma_axixso => dma_xso);

  ----------------------------------------------------------------------------
  -- DDR master. The board shell maps the MIG from address zero.
  ----------------------------------------------------------------------------
  mem_axi4_awvalid <= mem_mo.aw.valid;
  mem_axi4_awid    <= mem_mo.aw.id;
  -- DDR is 0x8000_0000-0xAFFF_FFFF, so subtracting the base clears bit 31.
  mem_axi4_awaddr  <= "000" & mem_mo.aw.addr(30 downto 0);
  mem_axi4_awlen   <= mem_mo.aw.len;
  mem_axi4_awsize  <= mem_mo.aw.size;
  mem_axi4_awburst <= mem_mo.aw.burst;
  mem_axi4_awlock  <= mem_mo.aw.lock;
  mem_axi4_awcache <= mem_mo.aw.cache;
  mem_axi4_awprot  <= mem_mo.aw.prot;
  mem_axi4_awqos   <= mem_mo.aw.qos;
  mem_mi.aw.ready  <= mem_axi4_awready;
  mem_axi4_wvalid  <= mem_mo.w.valid;
  mem_axi4_wdata   <= mem_mo.w.data;
  mem_axi4_wstrb   <= mem_mo.w.strb;
  mem_axi4_wlast   <= mem_mo.w.last;
  mem_mi.w.ready   <= mem_axi4_wready;
  mem_axi4_bready  <= mem_mo.b.ready;
  mem_mi.b.valid   <= mem_axi4_bvalid;
  mem_mi.b.id      <= mem_axi4_bid;
  mem_mi.b.resp    <= mem_axi4_bresp;
  mem_axi4_arvalid <= mem_mo.ar.valid;
  mem_axi4_arid    <= mem_mo.ar.id;
  mem_axi4_araddr  <= "000" & mem_mo.ar.addr(30 downto 0);
  mem_axi4_arlen   <= mem_mo.ar.len;
  mem_axi4_arsize  <= mem_mo.ar.size;
  mem_axi4_arburst <= mem_mo.ar.burst;
  mem_axi4_arlock  <= mem_mo.ar.lock;
  mem_axi4_arcache <= mem_mo.ar.cache;
  mem_axi4_arprot  <= mem_mo.ar.prot;
  mem_axi4_arqos   <= mem_mo.ar.qos;
  mem_mi.ar.ready  <= mem_axi4_arready;
  mem_axi4_rready  <= mem_mo.r.ready;
  mem_mi.r.valid   <= mem_axi4_rvalid;
  mem_mi.r.id      <= mem_axi4_rid;
  mem_mi.r.data    <= mem_axi4_rdata;
  mem_mi.r.resp    <= mem_axi4_rresp;
  mem_mi.r.last    <= mem_axi4_rlast;

  ----------------------------------------------------------------------------
  -- Board I/O master (UART, SD, Ethernet, XADC at 0x6000_0000)
  ----------------------------------------------------------------------------
  io_axi4_awvalid <= io_mo.aw.valid;
  io_axi4_awid    <= io_mo.aw.id;
  io_axi4_awaddr  <= io_mo.aw.addr(30 downto 0);
  io_axi4_awlen   <= io_mo.aw.len;
  io_axi4_awsize  <= io_mo.aw.size;
  io_axi4_awburst <= io_mo.aw.burst;
  io_axi4_awlock  <= io_mo.aw.lock;
  io_axi4_awcache <= io_mo.aw.cache;
  io_axi4_awprot  <= io_mo.aw.prot;
  io_axi4_awqos   <= io_mo.aw.qos;
  io_mi.aw.ready  <= io_axi4_awready;
  io_axi4_wvalid  <= io_mo.w.valid;
  io_axi4_wdata   <= io_mo.w.data;
  io_axi4_wstrb   <= io_mo.w.strb;
  io_axi4_wlast   <= io_mo.w.last;
  io_mi.w.ready   <= io_axi4_wready;
  io_axi4_bready  <= io_mo.b.ready;
  io_mi.b.valid   <= io_axi4_bvalid;
  io_mi.b.id      <= io_axi4_bid;
  io_mi.b.resp    <= io_axi4_bresp;
  io_axi4_arvalid <= io_mo.ar.valid;
  io_axi4_arid    <= io_mo.ar.id;
  io_axi4_araddr  <= io_mo.ar.addr(30 downto 0);
  io_axi4_arlen   <= io_mo.ar.len;
  io_axi4_arsize  <= io_mo.ar.size;
  io_axi4_arburst <= io_mo.ar.burst;
  io_axi4_arlock  <= io_mo.ar.lock;
  io_axi4_arcache <= io_mo.ar.cache;
  io_axi4_arprot  <= io_mo.ar.prot;
  io_axi4_arqos   <= io_mo.ar.qos;
  io_mi.ar.ready  <= io_axi4_arready;
  io_axi4_rready  <= io_mo.r.ready;
  io_mi.r.valid   <= io_axi4_rvalid;
  io_mi.r.id      <= io_axi4_rid;
  io_mi.r.data    <= io_axi4_rdata;
  io_mi.r.resp    <= io_axi4_rresp;
  io_mi.r.last    <= io_axi4_rlast;

  ----------------------------------------------------------------------------
  -- Board DMA slave (SD, Ethernet). The low 4 ID bits travel in the AXI
  -- record, the high 4 in the GRLIB extension record, so all 8 bits that the
  -- board SmartConnect uses for response routing are returned unchanged.
  -- DMA addresses are CPU physical (DDR at 0x8000_0000), 32 bits suffice.
  ----------------------------------------------------------------------------
  dma_si.aw.id    <= dma_axi4_awid(3 downto 0);
  dma_xsi.aw.id   <= dma_axi4_awid(7 downto 4);
  dma_si.aw.addr  <= dma_axi4_awaddr(31 downto 0);
  dma_xsi.aw.addr <= (others => '0');
  dma_si.aw.len   <= dma_axi4_awlen;
  dma_si.aw.size  <= dma_axi4_awsize;
  dma_si.aw.burst <= dma_axi4_awburst;
  dma_si.aw.lock  <= dma_axi4_awlock;
  dma_si.aw.cache <= dma_axi4_awcache;
  dma_si.aw.prot  <= dma_axi4_awprot;
  dma_si.aw.qos   <= dma_axi4_awqos;
  dma_si.aw.valid <= dma_axi4_awvalid;
  dma_axi4_awready <= dma_so.aw.ready;
  dma_si.w.data   <= dma_axi4_wdata;
  dma_si.w.strb   <= dma_axi4_wstrb;
  dma_si.w.last   <= dma_axi4_wlast;
  dma_si.w.valid  <= dma_axi4_wvalid;
  dma_xsi.w.id    <= (others => '0');
  dma_axi4_wready <= dma_so.w.ready;
  dma_si.b.ready  <= dma_axi4_bready;
  dma_axi4_bvalid <= dma_so.b.valid;
  dma_axi4_bid    <= dma_xso.b.id & dma_so.b.id;
  dma_axi4_bresp  <= dma_so.b.resp;
  dma_si.ar.id    <= dma_axi4_arid(3 downto 0);
  dma_xsi.ar.id   <= dma_axi4_arid(7 downto 4);
  dma_si.ar.addr  <= dma_axi4_araddr(31 downto 0);
  dma_xsi.ar.addr <= (others => '0');
  dma_si.ar.len   <= dma_axi4_arlen;
  dma_si.ar.size  <= dma_axi4_arsize;
  dma_si.ar.burst <= dma_axi4_arburst;
  dma_si.ar.lock  <= dma_axi4_arlock;
  dma_si.ar.cache <= dma_axi4_arcache;
  dma_si.ar.prot  <= dma_axi4_arprot;
  dma_si.ar.qos   <= dma_axi4_arqos;
  dma_si.ar.valid <= dma_axi4_arvalid;
  dma_axi4_arready <= dma_so.ar.ready;
  dma_si.r.ready  <= dma_axi4_rready;
  dma_axi4_rvalid <= dma_so.r.valid;
  dma_axi4_rid    <= dma_xso.r.id & dma_so.r.id;
  dma_axi4_rdata  <= dma_so.r.data;
  dma_axi4_rresp  <= dma_so.r.resp;
  dma_axi4_rlast  <= dma_so.r.last;

end;
