------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Boot-ROM testbench for the native NOEL-V board wrapper: the real wrapper
-- and boot ROM image, a behavioral DDR (MEM_AXI4), an I/O slave emulating
-- the repository UART (IO_AXI4) and an idle DMA port. The UART output and
-- every I/O access are printed to the simulation log.
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_noelv is
  generic (
    cfg       : integer := 768;
    tech      : integer := 0;           -- inferred
    TX_BYTES  : natural := 28;          -- stop after this many UART bytes
    MAX_US    : natural := 20000);
end;

architecture behav of tb_noelv is
  signal clk  : std_logic := '0';
  signal done : boolean := false;
  signal sys_reset : std_logic := '1';
  signal aresetn : std_logic;
  signal tx_count : natural;

  signal m_awready, m_awvalid, m_awlock, m_wready, m_wvalid, m_wlast, m_bready, m_bvalid : std_logic;
  signal m_arready, m_arvalid, m_arlock, m_rready, m_rvalid, m_rlast : std_logic;
  signal m_awid, m_bid, m_arid, m_rid : std_logic_vector(3 downto 0);
  signal m_awaddr, m_araddr : std_logic_vector(33 downto 0);
  signal m_awlen, m_arlen : std_logic_vector(7 downto 0);
  signal m_awsize, m_arsize, m_awprot, m_arprot : std_logic_vector(2 downto 0);
  signal m_awburst, m_arburst, m_bresp, m_rresp : std_logic_vector(1 downto 0);
  signal m_awcache, m_arcache, m_awqos, m_arqos : std_logic_vector(3 downto 0);
  signal m_wdata, m_rdata : std_logic_vector(63 downto 0);
  signal m_wstrb : std_logic_vector(7 downto 0);

  signal i_awready, i_awvalid, i_awlock, i_wready, i_wvalid, i_wlast, i_bready, i_bvalid : std_logic;
  signal i_arready, i_arvalid, i_arlock, i_rready, i_rvalid, i_rlast : std_logic;
  signal i_awid, i_bid, i_arid, i_rid : std_logic_vector(3 downto 0);
  signal i_awaddr, i_araddr : std_logic_vector(30 downto 0);
  signal i_awlen, i_arlen : std_logic_vector(7 downto 0);
  signal i_awsize, i_arsize, i_awprot, i_arprot : std_logic_vector(2 downto 0);
  signal i_awburst, i_arburst, i_bresp, i_rresp : std_logic_vector(1 downto 0);
  signal i_awcache, i_arcache, i_awqos, i_arqos : std_logic_vector(3 downto 0);
  signal i_wdata, i_rdata : std_logic_vector(63 downto 0);
  signal i_wstrb : std_logic_vector(7 downto 0);

  signal d_bid, d_rid : std_logic_vector(7 downto 0);
  signal d_bresp, d_rresp : std_logic_vector(1 downto 0);
  signal d_rdata : std_logic_vector(63 downto 0);
begin
  clk <= not clk after 10 ns when not done else '0';   -- 50 MHz
  sys_reset <= '0' after 200 ns;

  dut : entity work.NOELVBoardWrapper
    generic map (cfg => cfg, fabtech => tech, memtech => tech)
    port map (
      clock => clk, clock_ok => '1', mem_ok => '1', io_ok => '1',
      sys_reset => sys_reset, aresetn => aresetn, interrupts => (others => '0'),
      mem_axi4_awready => m_awready, mem_axi4_awvalid => m_awvalid, mem_axi4_awid => m_awid,
      mem_axi4_awaddr => m_awaddr, mem_axi4_awlen => m_awlen, mem_axi4_awsize => m_awsize,
      mem_axi4_awburst => m_awburst, mem_axi4_awlock => m_awlock, mem_axi4_awcache => m_awcache,
      mem_axi4_awprot => m_awprot, mem_axi4_awqos => m_awqos, mem_axi4_wready => m_wready,
      mem_axi4_wvalid => m_wvalid, mem_axi4_wdata => m_wdata, mem_axi4_wstrb => m_wstrb,
      mem_axi4_wlast => m_wlast, mem_axi4_bready => m_bready, mem_axi4_bvalid => m_bvalid,
      mem_axi4_bid => m_bid, mem_axi4_bresp => m_bresp, mem_axi4_arready => m_arready,
      mem_axi4_arvalid => m_arvalid, mem_axi4_arid => m_arid, mem_axi4_araddr => m_araddr,
      mem_axi4_arlen => m_arlen, mem_axi4_arsize => m_arsize, mem_axi4_arburst => m_arburst,
      mem_axi4_arlock => m_arlock, mem_axi4_arcache => m_arcache, mem_axi4_arprot => m_arprot,
      mem_axi4_arqos => m_arqos, mem_axi4_rready => m_rready, mem_axi4_rvalid => m_rvalid,
      mem_axi4_rid => m_rid, mem_axi4_rdata => m_rdata, mem_axi4_rresp => m_rresp,
      mem_axi4_rlast => m_rlast,
      io_axi4_awready => i_awready, io_axi4_awvalid => i_awvalid, io_axi4_awid => i_awid,
      io_axi4_awaddr => i_awaddr, io_axi4_awlen => i_awlen, io_axi4_awsize => i_awsize,
      io_axi4_awburst => i_awburst, io_axi4_awlock => i_awlock, io_axi4_awcache => i_awcache,
      io_axi4_awprot => i_awprot, io_axi4_awqos => i_awqos, io_axi4_wready => i_wready,
      io_axi4_wvalid => i_wvalid, io_axi4_wdata => i_wdata, io_axi4_wstrb => i_wstrb,
      io_axi4_wlast => i_wlast, io_axi4_bready => i_bready, io_axi4_bvalid => i_bvalid,
      io_axi4_bid => i_bid, io_axi4_bresp => i_bresp, io_axi4_arready => i_arready,
      io_axi4_arvalid => i_arvalid, io_axi4_arid => i_arid, io_axi4_araddr => i_araddr,
      io_axi4_arlen => i_arlen, io_axi4_arsize => i_arsize, io_axi4_arburst => i_arburst,
      io_axi4_arlock => i_arlock, io_axi4_arcache => i_arcache, io_axi4_arprot => i_arprot,
      io_axi4_arqos => i_arqos, io_axi4_rready => i_rready, io_axi4_rvalid => i_rvalid,
      io_axi4_rid => i_rid, io_axi4_rdata => i_rdata, io_axi4_rresp => i_rresp,
      io_axi4_rlast => i_rlast,
      dma_axi4_awready => open, dma_axi4_awvalid => '0', dma_axi4_awid => (others => '0'),
      dma_axi4_awaddr => (others => '0'), dma_axi4_awlen => (others => '0'),
      dma_axi4_awsize => (others => '0'), dma_axi4_awburst => (others => '0'),
      dma_axi4_awlock => '0', dma_axi4_awcache => (others => '0'),
      dma_axi4_awprot => (others => '0'), dma_axi4_awqos => (others => '0'),
      dma_axi4_wready => open, dma_axi4_wvalid => '0', dma_axi4_wdata => (others => '0'),
      dma_axi4_wstrb => (others => '0'), dma_axi4_wlast => '0', dma_axi4_bready => '1',
      dma_axi4_bvalid => open, dma_axi4_bid => d_bid, dma_axi4_bresp => d_bresp,
      dma_axi4_arready => open, dma_axi4_arvalid => '0', dma_axi4_arid => (others => '0'),
      dma_axi4_araddr => (others => '0'), dma_axi4_arlen => (others => '0'),
      dma_axi4_arsize => (others => '0'), dma_axi4_arburst => (others => '0'),
      dma_axi4_arlock => '0', dma_axi4_arcache => (others => '0'),
      dma_axi4_arprot => (others => '0'), dma_axi4_arqos => (others => '0'),
      dma_axi4_rready => '1', dma_axi4_rvalid => open, dma_axi4_rid => d_rid,
      dma_axi4_rdata => d_rdata, dma_axi4_rresp => d_rresp, dma_axi4_rlast => open);

  ddr : entity work.tb_axi_slave
    generic map (KIND => 0, AWIDTH => 34, IDW => 4)
    port map (
      clk => clk, rstn => aresetn,
      awready => m_awready, awvalid => m_awvalid, awid => m_awid, awaddr => m_awaddr,
      awlen => m_awlen, awsize => m_awsize, awburst => m_awburst,
      wready => m_wready, wvalid => m_wvalid, wdata => m_wdata, wstrb => m_wstrb, wlast => m_wlast,
      bready => m_bready, bvalid => m_bvalid, bid => m_bid, bresp => m_bresp,
      arready => m_arready, arvalid => m_arvalid, arid => m_arid, araddr => m_araddr,
      arlen => m_arlen, arsize => m_arsize, arburst => m_arburst,
      rready => m_rready, rvalid => m_rvalid, rid => m_rid, rdata => m_rdata,
      rresp => m_rresp, rlast => m_rlast, tx_count => open);

  io : entity work.tb_axi_slave
    generic map (KIND => 1, AWIDTH => 31, IDW => 4)
    port map (
      clk => clk, rstn => aresetn,
      awready => i_awready, awvalid => i_awvalid, awid => i_awid, awaddr => i_awaddr,
      awlen => i_awlen, awsize => i_awsize, awburst => i_awburst,
      wready => i_wready, wvalid => i_wvalid, wdata => i_wdata, wstrb => i_wstrb, wlast => i_wlast,
      bready => i_bready, bvalid => i_bvalid, bid => i_bid, bresp => i_bresp,
      arready => i_arready, arvalid => i_arvalid, arid => i_arid, araddr => i_araddr,
      arlen => i_arlen, arsize => i_arsize, arburst => i_arburst,
      rready => i_rready, rvalid => i_rvalid, rid => i_rid, rdata => i_rdata,
      rresp => i_rresp, rlast => i_rlast, tx_count => tx_count);

  stop_sim : process
    variable ln : line;
  begin
    for i in 1 to MAX_US loop
      wait for 1 us;
      exit when tx_count >= TX_BYTES;
    end loop;
    write(ln, string'("TB_DONE uart_bytes=") & integer'image(tx_count) &
          " time_us=" & integer'image(now / 1 us));
    writeline(output, ln);
    done <= true;
    wait;
  end process;
end;
