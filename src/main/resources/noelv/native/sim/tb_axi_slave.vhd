------------------------------------------------------------------------------
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Behavioral 64-bit AXI4 slave for the NOEL-V board-wrapper testbench.
--   KIND = 0: RAM (MIG model), MIG-local addresses, word-indexed, aliasing.
--   KIND = 1: board I/O window (0x6000_0000-based, 31-bit addresses):
--             repository uart.v at 0x6001_0000 (32-bit registers, 16-deep TX
--             FIFO drained one byte every TX_CYCLES clocks), everything else
--             reads as zero. 32-bit registers sit in the AXI byte lanes that
--             a 64->32 SmartConnect width converter would use.
-- One transaction at a time; INCR, WRAP and FIXED bursts; narrow sizes.
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_axi_slave is
  generic (
    KIND      : integer := 0;
    AWIDTH    : integer := 34;
    IDW       : integer := 4;
    RAM_WORDS : integer := 65536;     -- 512 KiB
    TX_CYCLES : integer := 200;
    LOG_IO    : boolean := true);
  port (
    clk     : in  std_logic;
    rstn    : in  std_logic;
    awready : out std_logic;
    awvalid : in  std_logic;
    awid    : in  std_logic_vector(IDW-1 downto 0);
    awaddr  : in  std_logic_vector(AWIDTH-1 downto 0);
    awlen   : in  std_logic_vector(7 downto 0);
    awsize  : in  std_logic_vector(2 downto 0);
    awburst : in  std_logic_vector(1 downto 0);
    wready  : out std_logic;
    wvalid  : in  std_logic;
    wdata   : in  std_logic_vector(63 downto 0);
    wstrb   : in  std_logic_vector(7 downto 0);
    wlast   : in  std_logic;
    bready  : in  std_logic;
    bvalid  : out std_logic;
    bid     : out std_logic_vector(IDW-1 downto 0);
    bresp   : out std_logic_vector(1 downto 0);
    arready : out std_logic;
    arvalid : in  std_logic;
    arid    : in  std_logic_vector(IDW-1 downto 0);
    araddr  : in  std_logic_vector(AWIDTH-1 downto 0);
    arlen   : in  std_logic_vector(7 downto 0);
    arsize  : in  std_logic_vector(2 downto 0);
    arburst : in  std_logic_vector(1 downto 0);
    rready  : in  std_logic;
    rvalid  : out std_logic;
    rid     : out std_logic_vector(IDW-1 downto 0);
    rdata   : out std_logic_vector(63 downto 0);
    rresp   : out std_logic_vector(1 downto 0);
    rlast   : out std_logic;
    tx_count: out natural);
end;

architecture behav of tb_axi_slave is
  type ram_t is array (0 to RAM_WORDS-1) of std_logic_vector(63 downto 0);
  type state_t is (idle, wr, wresp, rd);

  function next_addr(a : unsigned; size, burst, len : std_logic_vector) return unsigned is
    variable step : unsigned(a'range);
    variable n    : unsigned(a'range);
    variable wlen : unsigned(a'range);
    variable base : unsigned(a'range);
  begin
    step := shift_left(to_unsigned(1, a'length), to_integer(unsigned(size)));
    if burst = "00" then
      return a;                                   -- FIXED
    end if;
    n := a + step;
    if burst = "10" then                          -- WRAP
      wlen := resize(shift_left(resize(unsigned(len), a'length) + 1,
                                to_integer(unsigned(size))), a'length);
      base := a and not (wlen - 1);
      if (n and not (wlen - 1)) /= base then
        n := base;
      end if;
    end if;
    return n;
  end function;

  function hex(v : std_logic_vector) return string is
    constant digits : string(1 to 16) := "0123456789abcdef";
    variable r : string(1 to (v'length + 3) / 4);
    variable x : unsigned(r'length*4-1 downto 0) := resize(unsigned(v), r'length*4);
  begin
    for i in r'range loop
      r(i) := digits(to_integer(x(x'high - (i-1)*4 downto x'high - (i-1)*4 - 3)) + 1);
    end loop;
    return r;
  end function;
  signal wready_i, rvalid_i, rlast_i : std_logic := '0';
begin
  wready <= wready_i;
  rvalid <= rvalid_i;
  rlast  <= rlast_i;

  process (clk)
    variable ram    : ram_t := (others => (others => '0'));
    variable st     : state_t := idle;
    variable addr   : unsigned(AWIDTH-1 downto 0);
    variable len, beat : unsigned(7 downto 0);
    variable size   : std_logic_vector(2 downto 0);
    variable burst  : std_logic_vector(1 downto 0);
    variable id     : std_logic_vector(IDW-1 downto 0);
    variable widx   : integer;
    variable word   : std_logic_vector(63 downto 0);
    variable fifo   : natural := 0;
    variable drain  : natural := 0;
    variable txn    : natural := 0;
    variable ln     : line;
    variable c      : character;
  begin
    if rising_edge(clk) then
      awready <= '0';
      arready <= '0';
      wready_i  <= '0';

      -- UART transmitter drains the FIFO
      if KIND = 1 and fifo > 0 then
        if drain = 0 then
          fifo  := fifo - 1;
          drain := TX_CYCLES;
        else
          drain := drain - 1;
        end if;
      end if;

      if rstn = '0' then
        st := idle;
        bvalid <= '0';
        rvalid_i <= '0';
        rlast_i  <= '0';
      else
        case st is
          when idle =>
            if awvalid = '1' then
              awready <= '1';
              addr := unsigned(awaddr); len := unsigned(awlen); beat := (others => '0');
              size := awsize; burst := awburst; id := awid;
              st := wr;
            elsif arvalid = '1' then
              arready <= '1';
              addr := unsigned(araddr); len := unsigned(arlen); beat := (others => '0');
              size := arsize; burst := arburst; id := arid;
              st := rd;
            end if;

          when wr =>
            wready_i <= '1';
            if wvalid = '1' and (wready_i = '1') then
              widx := to_integer(addr(18 downto 3)) mod RAM_WORDS;
              if KIND = 0 then
                word := ram(widx);
                for b in 0 to 7 loop
                  if wstrb(b) = '1' then word(b*8+7 downto b*8) := wdata(b*8+7 downto b*8); end if;
                end loop;
                ram(widx) := word;
              else
                if LOG_IO then
                  write(ln, string'("IO WR addr=") & hex(std_logic_vector(addr)) &
                        " size=" & integer'image(to_integer(unsigned(size))) &
                        " strb=" & hex(wstrb) & " data=" & hex(wdata));
                  writeline(output, ln);
                end if;
                -- uart.v tx_fifo register at 0x6001_0004 (upper 32-bit lane)
                if addr(30 downto 3) = to_unsigned(16#6001_0000#/8, 28) and wstrb(4) = '1' then
                  c := character'val(to_integer(unsigned(wdata(39 downto 32))));
                  txn := txn + 1;
                  if fifo >= 16 then
                    write(ln, string'("UART TX OVERFLOW, dropped byte ") &
                          integer'image(character'pos(c)));
                    writeline(output, ln);
                  else
                    fifo := fifo + 1;
                    write(ln, string'("UART TX '") & c & "' (" &
                          integer'image(character'pos(c)) & ")");
                    writeline(output, ln);
                  end if;
                end if;
              end if;
              addr := next_addr(addr, size, burst, std_logic_vector(len));
              if wlast = '1' then
                wready_i <= '0';
                bvalid <= '1'; bid <= id; bresp <= "00";
                st := wresp;
              end if;
            end if;

          when wresp =>
            if bready = '1' then
              bvalid <= '0';
              st := idle;
            end if;

          when rd =>
            if rvalid_i = '0' or rready = '1' then
              if rvalid_i = '1' and rlast_i = '1' then
                rvalid_i <= '0'; rlast_i <= '0';
                st := idle;
              else
                if rvalid_i = '1' then
                  addr := next_addr(addr, size, burst, std_logic_vector(len));
                  beat := beat + 1;
                end if;
                widx := to_integer(addr(18 downto 3)) mod RAM_WORDS;
                if KIND = 0 then
                  word := ram(widx);
                else
                  word := (others => '0');
                  if addr(30 downto 3) = to_unsigned(16#6001_0008#/8, 28) then
                    -- uart.v status (lower lane): bit3 tx_full, bit2 tx_empty
                    if fifo >= 16 then word(3) := '1'; end if;
                    if fifo = 0 then word(2) := '1'; end if;
                  end if;
                  if LOG_IO then
                    write(ln, string'("IO RD addr=") & hex(std_logic_vector(addr)) &
                          " size=" & integer'image(to_integer(unsigned(size))) &
                          " len=" & integer'image(to_integer(len)) &
                          " data=" & hex(word) & " fifo=" & integer'image(fifo));
                    writeline(output, ln);
                  end if;
                end if;
                rvalid_i <= '1'; rid <= id; rdata <= word; rresp <= "00";
                if beat = len then rlast_i <= '1'; else rlast_i <= '0'; end if;
              end if;
            end if;
        end case;
      end if;
      tx_count <= txn;
    end if;
  end process;
end;
