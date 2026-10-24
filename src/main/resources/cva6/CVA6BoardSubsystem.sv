// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Native CVA6 subsystem for the repository-owned board shells.  This module
// deliberately has no Chisel, Diplomacy, TileLink, or Rocket dependencies.
// The surrounding board wrapper flattens these AXI interfaces for Vivado IP
// Integrator and owns DDR, UART, SD, Ethernet, clocks, reset, and pins.

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "register_interface/assign.svh"
`include "register_interface/typedef.svh"

module CVA6BoardSubsystem #(
  parameter int unsigned NumBoardInterrupts = 8,
  // 0: DDR is uncached (safe with the non-coherent board DMA masters).
  // 1: DDR is cached; software keeps DMA buffers coherent with Zicbom, so
  //    this requires a CVA6 target with RVZiCbom (the HPDcache configs).
  parameter bit          CachedDdr          = 1'b0,
  // 1: core and CLINT carry the time-CSR patch (patches/cva6/hp2), so rdtime
  //    reads mtime in hardware instead of trapping to OpenSBI.
  parameter bit          TimeCsr            = 1'b0
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  input  logic [NumBoardInterrupts-1:0]  board_irq_i,
  output logic                           core_reset_no,
  AXI_BUS.Master                         mem_axi,
  AXI_BUS.Master                         io_axi,
  AXI_BUS.Slave                          dma_axi
);

  localparam int unsigned AxiAddrWidth     = 64;
  localparam int unsigned AxiDataWidth     = 64;
  localparam int unsigned AxiUserWidth     = 64;
  // Preserve all eight ID bits emitted by the board SmartConnect.  CVA6 only
  // consumes the low four bits, but SD and Ethernet share the DMA ingress and
  // SmartConnect uses the complete ID to route their responses correctly.
  localparam int unsigned AxiSlaveIdWidth  = 8;
  localparam int unsigned NrSlavePorts     = 3; // CVA6, debug SBA, board DMA
  localparam int unsigned AxiMasterIdWidth =
      AxiSlaveIdWidth + $clog2(NrSlavePorts);

  localparam int unsigned DebugPort = 0;
  localparam int unsigned RomPort   = 1;
  localparam int unsigned ClintPort = 2;
  localparam int unsigned PlicPort  = 3;
  localparam int unsigned IoPort    = 4;
  localparam int unsigned MemPort   = 5;
  localparam int unsigned ErrLogPort = 6;
  localparam int unsigned NrMasterPorts = 7;

  // Same layout as the official CVA6 Genesys 2 SoC (ariane_soc_pkg).
  localparam logic [63:0] DebugBase = 64'h0000_0000_0000_0000;
  localparam logic [63:0] DebugEnd  = 64'h0000_0000_0000_1000;

  // Read-only AXI error recorder (debug aid), see "AXI error recorder".
  localparam logic [63:0] ErrLogBase = 64'h0000_0000_0000_4000;
  localparam logic [63:0] ErrLogEnd  = 64'h0000_0000_0000_5000;

  localparam logic [63:0] RomBase   = 64'h0000_0000_0001_0000;
  localparam logic [63:0] RomEnd    = 64'h0000_0000_0002_0000;
  localparam logic [63:0] ClintBase = 64'h0000_0000_0200_0000;
  localparam logic [63:0] ClintEnd  = 64'h0000_0000_020C_0000;
  localparam logic [63:0] PlicBase  = 64'h0000_0000_0C00_0000;
  localparam logic [63:0] PlicEnd   = 64'h0000_0000_1000_0000;
  localparam logic [63:0] IoBase    = 64'h0000_0000_6000_0000;
  localparam logic [63:0] IoEnd     = 64'h0000_0000_6004_0000;
  localparam logic [63:0] MemBase   = 64'h0000_0000_8000_0000;
  localparam logic [63:0] MemEnd    = 64'h0000_0000_C000_0000;

  function automatic config_pkg::cva6_user_cfg_t board_cva6_cfg();
    config_pkg::cva6_user_cfg_t cfg;
    cfg = cva6_config_pkg::cva6_cfg;
    cfg.FpgaEn = 1'b1;
    cfg.FpgaAlteraEn = 1'b0;
    cfg.NrNonIdempotentRules = unsigned'(1);
    cfg.NonIdempotentAddrBase = 1024'({64'b0});
    cfg.NonIdempotentLength = 1024'({MemBase});
    // SD and Ethernet are non-coherent DMA masters on the board fabric.
    if (CachedDdr) begin
      cfg.NrCachedRegionRules = unsigned'(1);
      cfg.CachedRegionAddrBase = 1024'({MemBase});
      cfg.CachedRegionLength = 1024'({MemEnd - MemBase});
    end else begin
      cfg.NrCachedRegionRules = unsigned'(0);
      cfg.CachedRegionAddrBase = '0;
      cfg.CachedRegionLength = '0;
    end
    return cfg;
  endfunction

  localparam config_pkg::cva6_cfg_t CVA6Cfg =
      build_config_pkg::build_config(board_cva6_cfg());

  AXI_BUS #(
    .AXI_ADDR_WIDTH (AxiAddrWidth),
    .AXI_DATA_WIDTH (AxiDataWidth),
    .AXI_ID_WIDTH   (AxiSlaveIdWidth),
    .AXI_USER_WIDTH (AxiUserWidth)
  ) cpu_axi();

  AXI_BUS #(
    .AXI_ADDR_WIDTH (AxiAddrWidth),
    .AXI_DATA_WIDTH (AxiDataWidth),
    .AXI_ID_WIDTH   (AxiSlaveIdWidth),
    .AXI_USER_WIDTH (AxiUserWidth)
  ) slave [NrSlavePorts-1:0]();

  AXI_BUS #(
    .AXI_ADDR_WIDTH (AxiAddrWidth),
    .AXI_DATA_WIDTH (AxiDataWidth),
    .AXI_ID_WIDTH   (AxiMasterIdWidth),
    .AXI_USER_WIDTH (AxiUserWidth)
  ) master [NrMasterPorts-1:0]();

  logic [1:0] plic_irq;
  logic       timer_irq;
  logic [63:0] mtime;
  logic       software_irq;

  // rst_ni is the power-on reset; it only resets the debug logic. Everything
  // else uses sys_rst_n, which the debugger can pulse through ndmreset.
  logic ndmreset;
  logic sys_rst_n;
  logic debug_req;

  rstgen i_rstgen_sys (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni & ~ndmreset),
    .test_mode_i (1'b0),
    .rst_no      (sys_rst_n),
    .init_no     ()
  );

  // CVA6Core is only a native SystemVerilog adaptation layer around the
  // official `ariane` module and its AXI atomics converter.
  CVA6Core #(.CVA6Cfg(CVA6Cfg), .TimeCsr(TimeCsr)) i_cva6 (
    .clk_i                         (clk_i),
    .rst_ni                        (sys_rst_n),
    .boot_addr_i                   (RomBase),
    .hart_id_i                     ('0),
    .irq_i                         (plic_irq),
    .ipi_i                         (software_irq),
    .time_irq_i                    (timer_irq),
    .time_i                        (mtime),
    .debug_req_i                   (debug_req),
    .axi_resp_i_aw_ready           (cpu_axi.aw_ready),
    .axi_req_o_aw_valid            (cpu_axi.aw_valid),
    .axi_req_o_aw_bits_id          (cpu_axi.aw_id),
    .axi_req_o_aw_bits_addr        (cpu_axi.aw_addr),
    .axi_req_o_aw_bits_len         (cpu_axi.aw_len),
    .axi_req_o_aw_bits_size        (cpu_axi.aw_size),
    .axi_req_o_aw_bits_burst       (cpu_axi.aw_burst),
    .axi_req_o_aw_bits_lock        (cpu_axi.aw_lock),
    .axi_req_o_aw_bits_cache       (cpu_axi.aw_cache),
    .axi_req_o_aw_bits_prot        (cpu_axi.aw_prot),
    .axi_req_o_aw_bits_qos         (cpu_axi.aw_qos),
    .axi_req_o_aw_bits_region      (cpu_axi.aw_region),
    .axi_req_o_aw_bits_atop        (cpu_axi.aw_atop),
    .axi_req_o_aw_bits_user        (cpu_axi.aw_user),
    .axi_resp_i_w_ready            (cpu_axi.w_ready),
    .axi_req_o_w_valid             (cpu_axi.w_valid),
    .axi_req_o_w_bits_data         (cpu_axi.w_data),
    .axi_req_o_w_bits_strb         (cpu_axi.w_strb),
    .axi_req_o_w_bits_last         (cpu_axi.w_last),
    .axi_req_o_w_bits_user         (cpu_axi.w_user),
    .axi_resp_i_ar_ready           (cpu_axi.ar_ready),
    .axi_req_o_ar_valid            (cpu_axi.ar_valid),
    .axi_req_o_ar_bits_id          (cpu_axi.ar_id),
    .axi_req_o_ar_bits_addr        (cpu_axi.ar_addr),
    .axi_req_o_ar_bits_len         (cpu_axi.ar_len),
    .axi_req_o_ar_bits_size        (cpu_axi.ar_size),
    .axi_req_o_ar_bits_burst       (cpu_axi.ar_burst),
    .axi_req_o_ar_bits_lock        (cpu_axi.ar_lock),
    .axi_req_o_ar_bits_cache       (cpu_axi.ar_cache),
    .axi_req_o_ar_bits_prot        (cpu_axi.ar_prot),
    .axi_req_o_ar_bits_qos         (cpu_axi.ar_qos),
    .axi_req_o_ar_bits_region      (cpu_axi.ar_region),
    .axi_req_o_ar_bits_user        (cpu_axi.ar_user),
    .axi_req_o_b_ready             (cpu_axi.b_ready),
    .axi_resp_i_b_valid            (cpu_axi.b_valid),
    .axi_resp_i_b_bits_id          (cpu_axi.b_id),
    .axi_resp_i_b_bits_resp        (cpu_axi.b_resp),
    .axi_resp_i_b_bits_user        (cpu_axi.b_user),
    .axi_req_o_r_ready             (cpu_axi.r_ready),
    .axi_resp_i_r_valid            (cpu_axi.r_valid),
    .axi_resp_i_r_bits_id          (cpu_axi.r_id),
    .axi_resp_i_r_bits_data        (cpu_axi.r_data),
    .axi_resp_i_r_bits_resp        (cpu_axi.r_resp),
    .axi_resp_i_r_bits_last        (cpu_axi.r_last),
    .axi_resp_i_r_bits_user        (cpu_axi.r_user)
  );

  `AXI_ASSIGN(slave[0], cpu_axi)
  `AXI_ASSIGN(slave[2], dma_axi)
  // RISC-V atomics (AMOs as AXI ATOPs, LR/SC) are resolved in front of DDR,
  // where the downstream answers in order (official CVA6 FPGA SoC layout).
  // The adapter keeps one LR/SC reservation per AXI ID, so first compress the
  // 10-bit crossbar IDs to the 5 bits the official SoC uses; with 10-bit IDs
  // the reservation table alone needs ~100k LUTs and stalls write streams.
  localparam int unsigned AxiMemIdWidth = 5;

  AXI_BUS #(
    .AXI_ADDR_WIDTH (AxiAddrWidth),
    .AXI_DATA_WIDTH (AxiDataWidth),
    .AXI_ID_WIDTH   (AxiMemIdWidth),
    .AXI_USER_WIDTH (AxiUserWidth)
  ) mem_remapped(), mem_atomic();

  axi_id_remap_intf #(
    .AXI_SLV_PORT_ID_WIDTH     (AxiMasterIdWidth),
    .AXI_SLV_PORT_MAX_UNIQ_IDS (16),
    .AXI_MAX_TXNS_PER_ID       (4),
    .AXI_MST_PORT_ID_WIDTH     (AxiMemIdWidth),
    .AXI_ADDR_WIDTH            (AxiAddrWidth),
    .AXI_DATA_WIDTH            (AxiDataWidth),
    .AXI_USER_WIDTH            (AxiUserWidth)
  ) i_mem_id_remap (
    .clk_i,
    .rst_ni (sys_rst_n),
    .slv    (master[MemPort]),
    .mst    (mem_remapped)
  );

  axi_riscv_atomics_wrap #(
    .AXI_ADDR_WIDTH     (AxiAddrWidth),
    .AXI_DATA_WIDTH     (AxiDataWidth),
    .AXI_ID_WIDTH       (AxiMemIdWidth),
    .AXI_USER_WIDTH     (AxiUserWidth),
    .AXI_MAX_WRITE_TXNS (1),
    .RISCV_WORD_WIDTH   (64)
  ) i_axi_riscv_atomics (
    .clk_i,
    .rst_ni (sys_rst_n),
    .slv    (mem_remapped),
    .mst    (mem_atomic)
  );

  // 5-bit IDs onto the 10-bit board MEM port (upper bits are zero).
  `AXI_ASSIGN(mem_axi, mem_atomic)
  `AXI_ASSIGN(io_axi, master[IoPort])

  axi_pkg::xbar_rule_64_t [NrMasterPorts-1:0] addr_map;
  assign addr_map = '{
    '{idx: DebugPort, start_addr: DebugBase, end_addr: DebugEnd},
    '{idx: ErrLogPort, start_addr: ErrLogBase, end_addr: ErrLogEnd},
    '{idx: RomPort,   start_addr: RomBase,   end_addr: RomEnd},
    '{idx: ClintPort, start_addr: ClintBase, end_addr: ClintEnd},
    '{idx: PlicPort,  start_addr: PlicBase,  end_addr: PlicEnd},
    '{idx: IoPort,    start_addr: IoBase,    end_addr: IoEnd},
    '{idx: MemPort,   start_addr: MemBase,   end_addr: MemEnd}
  };

  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         NrSlavePorts,
    NoMstPorts:         NrMasterPorts,
    // One outstanding transaction per port, as in the official CVA6 FPGA
    // SoC. With 2, uncached I/O reads and DDR refills from the core were
    // observed to return each other's data on hardware.
    MaxMstTrans:        1,
    MaxSlvTrans:        1,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_PORTS,
    AxiIdWidthSlvPorts: AxiSlaveIdWidth,
    AxiIdUsedSlvPorts:  AxiSlaveIdWidth,
    UniqueIds:          1'b0,
    AxiAddrWidth:       AxiAddrWidth,
    AxiDataWidth:       AxiDataWidth,
    NoAddrRules:        NrMasterPorts
  };

  axi_xbar_intf #(
    .AXI_USER_WIDTH (AxiUserWidth),
    .Cfg            (XbarCfg),
    .rule_t         (axi_pkg::xbar_rule_64_t)
  ) i_axi_xbar (
    .clk_i,
    .rst_ni (sys_rst_n),
    .test_i                (1'b0),
    .slv_ports             (slave),
    .mst_ports             (master),
    .addr_map_i            (addr_map),
    .en_default_mst_port_i ('0),
    .default_mst_port_i    ('0)
  );

  // CLINT: mtime counts at half the core clock; the generated device tree
  // advertises timebase-frequency = core clock / 2.
  logic rtc;
  always_ff @(posedge clk_i or negedge sys_rst_n) begin
    if (!sys_rst_n) rtc <= 1'b0;
    else         rtc <= ~rtc;
  end

  `AXI_TYPEDEF_ALL(clint_axi,
                   logic [AxiAddrWidth-1:0],
                   logic [AxiMasterIdWidth-1:0],
                   logic [AxiDataWidth-1:0],
                   logic [AxiDataWidth/8-1:0],
                   logic [AxiUserWidth-1:0])
  clint_axi_req_t  clint_req;
  clint_axi_resp_t clint_resp;

  if (TimeCsr) begin : g_clint_time
    clint #(
      .CVA6Cfg        (CVA6Cfg),
      .AXI_ADDR_WIDTH (AxiAddrWidth),
      .AXI_DATA_WIDTH (AxiDataWidth),
      .AXI_ID_WIDTH   (AxiMasterIdWidth),
      .NR_CORES       (1),
      .axi_req_t      (clint_axi_req_t),
      .axi_resp_t     (clint_axi_resp_t)
    ) i_clint (
      .clk_i,
      .rst_ni (sys_rst_n),
      .testmode_i  (1'b0),
      .axi_req_i   (clint_req),
      .axi_resp_o  (clint_resp),
      .rtc_i       (rtc),
      .timer_irq_o (timer_irq),
      .ipi_o       (software_irq),
      .mtime_o     (mtime)
    );
  end else begin : g_clint
    clint #(
      .CVA6Cfg        (CVA6Cfg),
      .AXI_ADDR_WIDTH (AxiAddrWidth),
      .AXI_DATA_WIDTH (AxiDataWidth),
      .AXI_ID_WIDTH   (AxiMasterIdWidth),
      .NR_CORES       (1),
      .axi_req_t      (clint_axi_req_t),
      .axi_resp_t     (clint_axi_resp_t)
    ) i_clint (
      .clk_i,
      .rst_ni (sys_rst_n),
      .testmode_i  (1'b0),
      .axi_req_i   (clint_req),
      .axi_resp_o  (clint_resp),
      .rtc_i       (rtc),
      .timer_irq_o (timer_irq),
      .ipi_o       (software_irq)
    );
    assign mtime = '0;
  end
  `AXI_ASSIGN_TO_REQ(clint_req, master[ClintPort])
  `AXI_ASSIGN_FROM_RESP(master[ClintPort], clint_resp)


  // ---------------------------------------------------------------------
  // AXI error recorder (debug aid). Watches the core's AXI port and records
  // the first and the latest SLVERR/DECERR response together with the
  // address of the request (last AR/AW address seen per ID), plus error
  // counters for the DDR and board I/O ports. Reset only by power-on, so
  // it survives ndmreset. Read-only, 64-bit registers at ErrLogBase:
  //   0x00 core error count      0x08 first error info   0x10 first address
  //   0x18 first error cycle     0x20 latest info        0x28 latest address
  //   0x30 latest cycle          0x38 cycle counter      0x40 DDR port errors
  //   0x48 board I/O port errors
  // info = {valid, is_write, 6'b0, resp[1:0], 46'b0, id[7:0]}
  // ---------------------------------------------------------------------
  logic [63:0] el_cyc_q, el_cnt_q, el_mem_cnt_q, el_io_cnt_q;
  logic [63:0] el_first_info_q, el_first_addr_q, el_first_cyc_q;
  logic [63:0] el_last_info_q, el_last_addr_q, el_last_cyc_q;
  logic [63:0] el_ar_addr_q [16];
  logic [63:0] el_aw_addr_q [16];
  logic        el_r_err, el_b_err;
  logic [63:0] el_info, el_addr;

  assign el_r_err = cpu_axi.r_valid & cpu_axi.r_ready & cpu_axi.r_resp[1];
  assign el_b_err = cpu_axi.b_valid & cpu_axi.b_ready & cpu_axi.b_resp[1];
  assign el_info  = el_b_err ? {1'b1, 1'b1, 6'b0, cpu_axi.b_resp, 46'b0, cpu_axi.b_id[7:0]}
                             : {1'b1, 1'b0, 6'b0, cpu_axi.r_resp, 46'b0, cpu_axi.r_id[7:0]};
  assign el_addr  = el_b_err ? el_aw_addr_q[cpu_axi.b_id[3:0]] : el_ar_addr_q[cpu_axi.r_id[3:0]];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      el_cyc_q <= '0; el_cnt_q <= '0; el_mem_cnt_q <= '0; el_io_cnt_q <= '0;
      el_first_info_q <= '0; el_first_addr_q <= '0; el_first_cyc_q <= '0;
      el_last_info_q <= '0; el_last_addr_q <= '0; el_last_cyc_q <= '0;
      for (int i = 0; i < 16; i++) begin
        el_ar_addr_q[i] <= '0;
        el_aw_addr_q[i] <= '0;
      end
    end else begin
      el_cyc_q <= el_cyc_q + 1;
      if (cpu_axi.ar_valid && cpu_axi.ar_ready) el_ar_addr_q[cpu_axi.ar_id[3:0]] <= cpu_axi.ar_addr;
      if (cpu_axi.aw_valid && cpu_axi.aw_ready) el_aw_addr_q[cpu_axi.aw_id[3:0]] <= cpu_axi.aw_addr;
      if (el_r_err || el_b_err) begin
        el_cnt_q       <= el_cnt_q + 1;
        el_last_info_q <= el_info;
        el_last_addr_q <= el_addr;
        el_last_cyc_q  <= el_cyc_q;
        if (!el_first_info_q[63]) begin
          el_first_info_q <= el_info;
          el_first_addr_q <= el_addr;
          el_first_cyc_q  <= el_cyc_q;
        end
      end
      if ((mem_atomic.r_valid & mem_atomic.r_ready & mem_atomic.r_resp[1]) |
          (mem_atomic.b_valid & mem_atomic.b_ready & mem_atomic.b_resp[1]))
        el_mem_cnt_q <= el_mem_cnt_q + 1;
      if ((master[IoPort].r_valid & master[IoPort].r_ready & master[IoPort].r_resp[1]) |
          (master[IoPort].b_valid & master[IoPort].b_ready & master[IoPort].b_resp[1]))
        el_io_cnt_q <= el_io_cnt_q + 1;
    end
  end

  logic                    el_req;
  logic [AxiAddrWidth-1:0] el_raddr;
  logic [AxiDataWidth-1:0] el_rdata;

  axi2mem #(
    .AXI_ID_WIDTH   (AxiMasterIdWidth),
    .AXI_ADDR_WIDTH (AxiAddrWidth),
    .AXI_DATA_WIDTH (AxiDataWidth),
    .AXI_USER_WIDTH (AxiUserWidth)
  ) i_axi2errlog (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .slave  (master[ErrLogPort]),
    .req_o  (el_req),
    .we_o   (),
    .addr_o (el_raddr),
    .be_o   (),
    .data_o (),
    .data_i (el_rdata)
  );

  always_ff @(posedge clk_i) begin
    if (el_req) begin
      unique case (el_raddr[6:3])
        4'h0: el_rdata <= el_cnt_q;
        4'h1: el_rdata <= el_first_info_q;
        4'h2: el_rdata <= el_first_addr_q;
        4'h3: el_rdata <= el_first_cyc_q;
        4'h4: el_rdata <= el_last_info_q;
        4'h5: el_rdata <= el_last_addr_q;
        4'h6: el_rdata <= el_last_cyc_q;
        4'h7: el_rdata <= el_cyc_q;
        4'h8: el_rdata <= el_mem_cnt_q;
        4'h9: el_rdata <= el_io_cnt_q;
        default: el_rdata <= '0;
      endcase
    end
  end

  // Repository boot ROM attachment.  bootrom_64 is a backend-composed image:
  // CVA6-native reset/early initialization first, followed by the common
  // repository board loader (UART, SD/FAT, BOOT.ELF, DTB and handoff ABI).
  logic                    rom_req;
  logic [AxiAddrWidth-1:0] rom_addr;
  logic [AxiDataWidth-1:0] rom_rdata;

  axi2mem #(
    .AXI_ID_WIDTH   (AxiMasterIdWidth),
    .AXI_ADDR_WIDTH (AxiAddrWidth),
    .AXI_DATA_WIDTH (AxiDataWidth),
    .AXI_USER_WIDTH (AxiUserWidth)
  ) i_axi2rom (
    .clk_i  (clk_i),
    .rst_ni (sys_rst_n),
    .slave  (master[RomPort]),
    .req_o  (rom_req),
    .we_o   (),
    .addr_o (rom_addr),
    .be_o   (),
    .data_o (),
    .data_i (rom_rdata)
  );

  bootrom_64 i_bootrom (
    .clk_i   (clk_i),
    .req_i   (rom_req),
    .addr_i  (rom_addr),
    .rdata_o (rom_rdata)
  );

  // rv_plic numbers irq_sources_i[0] as PLIC source 1 (source 0 is reserved
  // and has no input). Board interrupt bit 0 is source 1 (UART), bit 1 is
  // source 2 (SD), bit 2 is source 3 (Ethernet), matching the shared
  // Genesys 2 device tree.
  logic [ariane_soc::NumSources-1:0] irq_sources;
  always_comb begin
    irq_sources = '0;
    irq_sources[NumBoardInterrupts-1:0] = board_irq_i;
  end

  REG_BUS #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) plic_reg_bus(clk_i);
  logic        plic_penable;
  logic        plic_pwrite;
  logic [31:0] plic_paddr;
  logic        plic_psel;
  logic [31:0] plic_pwdata;
  logic [31:0] plic_prdata;
  logic        plic_pready;
  logic        plic_pslverr;

  axi2apb_64_32 #(
    .AXI4_ADDRESS_WIDTH (AxiAddrWidth),
    .AXI4_RDATA_WIDTH   (AxiDataWidth),
    .AXI4_WDATA_WIDTH   (AxiDataWidth),
    .AXI4_ID_WIDTH      (AxiMasterIdWidth),
    .AXI4_USER_WIDTH    (AxiUserWidth),
    .BUFF_DEPTH_SLAVE   (2),
    .APB_ADDR_WIDTH     (32)
  ) i_axi2apb_plic (
    .ACLK       (clk_i),
    .ARESETn    (sys_rst_n),
    .test_en_i  (1'b0),
    .AWID_i     (master[PlicPort].aw_id),
    .AWADDR_i   (master[PlicPort].aw_addr),
    .AWLEN_i    (master[PlicPort].aw_len),
    .AWSIZE_i   (master[PlicPort].aw_size),
    .AWBURST_i  (master[PlicPort].aw_burst),
    .AWLOCK_i   (master[PlicPort].aw_lock),
    .AWCACHE_i  (master[PlicPort].aw_cache),
    .AWPROT_i   (master[PlicPort].aw_prot),
    .AWREGION_i (master[PlicPort].aw_region),
    .AWUSER_i   (master[PlicPort].aw_user),
    .AWQOS_i    (master[PlicPort].aw_qos),
    .AWVALID_i  (master[PlicPort].aw_valid),
    .AWREADY_o  (master[PlicPort].aw_ready),
    .WDATA_i    (master[PlicPort].w_data),
    .WSTRB_i    (master[PlicPort].w_strb),
    .WLAST_i    (master[PlicPort].w_last),
    .WUSER_i    (master[PlicPort].w_user),
    .WVALID_i   (master[PlicPort].w_valid),
    .WREADY_o   (master[PlicPort].w_ready),
    .BID_o      (master[PlicPort].b_id),
    .BRESP_o    (master[PlicPort].b_resp),
    .BVALID_o   (master[PlicPort].b_valid),
    .BUSER_o    (master[PlicPort].b_user),
    .BREADY_i   (master[PlicPort].b_ready),
    .ARID_i     (master[PlicPort].ar_id),
    .ARADDR_i   (master[PlicPort].ar_addr),
    .ARLEN_i    (master[PlicPort].ar_len),
    .ARSIZE_i   (master[PlicPort].ar_size),
    .ARBURST_i  (master[PlicPort].ar_burst),
    .ARLOCK_i   (master[PlicPort].ar_lock),
    .ARCACHE_i  (master[PlicPort].ar_cache),
    .ARPROT_i   (master[PlicPort].ar_prot),
    .ARREGION_i (master[PlicPort].ar_region),
    .ARUSER_i   (master[PlicPort].ar_user),
    .ARQOS_i    (master[PlicPort].ar_qos),
    .ARVALID_i  (master[PlicPort].ar_valid),
    .ARREADY_o  (master[PlicPort].ar_ready),
    .RID_o      (master[PlicPort].r_id),
    .RDATA_o    (master[PlicPort].r_data),
    .RRESP_o    (master[PlicPort].r_resp),
    .RLAST_o    (master[PlicPort].r_last),
    .RUSER_o    (master[PlicPort].r_user),
    .RVALID_o   (master[PlicPort].r_valid),
    .RREADY_i   (master[PlicPort].r_ready),
    .PENABLE    (plic_penable),
    .PWRITE     (plic_pwrite),
    .PADDR      (plic_paddr),
    .PSEL       (plic_psel),
    .PWDATA     (plic_pwdata),
    .PRDATA     (plic_prdata),
    .PREADY     (plic_pready),
    .PSLVERR    (plic_pslverr)
  );

  apb_to_reg i_apb_to_reg (
    .clk_i,
    .rst_ni (sys_rst_n),
    .penable_i (plic_penable),
    .pwrite_i  (plic_pwrite),
    .paddr_i   (plic_paddr),
    .psel_i    (plic_psel),
    .pwdata_i  (plic_pwdata),
    .prdata_o  (plic_prdata),
    .pready_o  (plic_pready),
    .pslverr_o (plic_pslverr),
    .reg_o     (plic_reg_bus)
  );

  `REG_BUS_TYPEDEF_ALL(plic, logic [31:0], logic [31:0], logic [3:0])
  plic_req_t plic_req;
  plic_rsp_t plic_rsp;
  `REG_BUS_ASSIGN_TO_REQ(plic_req, plic_reg_bus)
  `REG_BUS_ASSIGN_FROM_RSP(plic_reg_bus, plic_rsp)

  plic_top #(
    .N_SOURCE  (ariane_soc::NumSources),
    .N_TARGET  (ariane_soc::NumTargets),
    .MAX_PRIO  (ariane_soc::MaxPriority),
    .reg_req_t (plic_req_t),
    .reg_rsp_t (plic_rsp_t)
  ) i_plic (
    .clk_i,
    .rst_ni (sys_rst_n),
    .req_i         (plic_req),
    .resp_o        (plic_rsp),
    .le_i          ('0),
    .irq_sources_i (irq_sources),
    .eip_targets_o (plic_irq)
  );

  // ---------------------------------------------------------------------
  // Debug: official riscv-dbg debug module (dm_top) behind the repository's
  // BSCANE2 DMI transport (JtagSeries7, the same one Rocket uses), so the
  // onboard USB-JTAG cable, xsdb/Vitis and `make jtag-boot` work unchanged.
  // ---------------------------------------------------------------------
  logic          dmi_req_valid;
  logic          dmi_req_ready;
  dm::dmi_req_t  dmi_req;
  logic          dmi_resp_valid;
  dm::dmi_resp_t dmi_resp;

  JtagSeries7 i_dmi_bscan (
    .clock       (clk_i),
    .reset       (~rst_ni),
    .dmi_o_ready (dmi_req_ready),
    .dmi_o_valid (dmi_req_valid),
    .dmi_o_addr  (dmi_req.addr),
    .dmi_o_data  (dmi_req.data),
    .dmi_o_op    (dmi_req.op),
    .dmi_i_ready (),               // always ready
    .dmi_i_valid (dmi_resp_valid),
    .dmi_i_data  (dmi_resp.data),
    .dmi_i_resp  (dmi_resp.resp)
  );

  logic                    dm_slave_req;
  logic                    dm_slave_we;
  logic [63:0]             dm_slave_addr;
  logic [7:0]              dm_slave_be;
  logic [63:0]             dm_slave_wdata;
  logic [63:0]             dm_slave_rdata;
  logic                    dm_master_req;
  logic [63:0]             dm_master_add;
  logic                    dm_master_we;
  logic [63:0]             dm_master_wdata;
  logic [7:0]              dm_master_be;
  logic                    dm_master_gnt;
  logic                    dm_master_r_valid;
  logic [63:0]             dm_master_r_rdata;

  dm_top #(
    .NrHarts         (1),
    .BusWidth        (64),
    .SelectableHarts (1'b1)
  ) i_dm_top (
    .clk_i,
    .rst_ni,                       // power-on reset, not ndmreset
    .testmode_i       (1'b0),
    .ndmreset_o       (ndmreset),
    .dmactive_o       (),
    .debug_req_o      (debug_req),
    .unavailable_i    ('0),
    .hartinfo_i       ({ariane_pkg::DebugHartInfo}),
    .slave_req_i      (dm_slave_req),
    .slave_we_i       (dm_slave_we),
    .slave_addr_i     (dm_slave_addr),
    .slave_be_i       (dm_slave_be),
    .slave_wdata_i    (dm_slave_wdata),
    .slave_rdata_o    (dm_slave_rdata),
    .master_req_o     (dm_master_req),
    .master_add_o     (dm_master_add),
    .master_we_o      (dm_master_we),
    .master_wdata_o   (dm_master_wdata),
    .master_be_o      (dm_master_be),
    .master_gnt_i     (dm_master_gnt),
    .master_r_valid_i (dm_master_r_valid),
    .master_r_rdata_i (dm_master_r_rdata),
    .dmi_rst_ni       (rst_ni),
    .dmi_req_valid_i  (dmi_req_valid),
    .dmi_req_ready_o  (dmi_req_ready),
    .dmi_req_i        (dmi_req),
    .dmi_resp_valid_o (dmi_resp_valid),
    .dmi_resp_ready_i (1'b1),
    .dmi_resp_o       (dmi_resp)
  );

  // Debug memory (program buffer, debug ROM) seen by the core.
  axi2mem #(
    .AXI_ID_WIDTH   (AxiMasterIdWidth),
    .AXI_ADDR_WIDTH (AxiAddrWidth),
    .AXI_DATA_WIDTH (AxiDataWidth),
    .AXI_USER_WIDTH (AxiUserWidth)
  ) i_dm_axi2mem (
    .clk_i,
    .rst_ni,
    .slave  (master[DebugPort]),
    .req_o  (dm_slave_req),
    .we_o   (dm_slave_we),
    .addr_o (dm_slave_addr),
    .be_o   (dm_slave_be),
    .data_o (dm_slave_wdata),
    .data_i (dm_slave_rdata)
  );

  // System bus access: the debugger reads/writes memory and MMIO directly.
  ariane_axi::req_t  dm_axi_req;
  ariane_axi::resp_t dm_axi_resp;

  axi_adapter #(
    .CVA6Cfg    (CVA6Cfg),
    .DATA_WIDTH (64),
    .axi_req_t  (ariane_axi::req_t),
    .axi_rsp_t  (ariane_axi::resp_t)
  ) i_dm_axi_master (
    .clk_i,
    .rst_ni,
    .req_i                 (dm_master_req),
    .type_i                (ariane_pkg::SINGLE_REQ),
    .amo_i                 (ariane_pkg::AMO_NONE),
    .gnt_o                 (dm_master_gnt),
    .addr_i                (dm_master_add),
    .we_i                  (dm_master_we),
    .wdata_i               (dm_master_wdata),
    .be_i                  (dm_master_be),
    .size_i                (2'b11),
    .id_i                  ('0),
    .valid_o               (dm_master_r_valid),
    .rdata_o               (dm_master_r_rdata),
    .id_o                  (),
    .critical_word_o       (),
    .critical_word_valid_o (),
    .axi_req_o             (dm_axi_req),
    .axi_resp_i            (dm_axi_resp)
  );

  `AXI_ASSIGN_FROM_REQ(slave[1], dm_axi_req)
  `AXI_ASSIGN_TO_RESP(dm_axi_resp, slave[1])

  assign core_reset_no = sys_rst_n;

endmodule
