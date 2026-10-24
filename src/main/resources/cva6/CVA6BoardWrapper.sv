// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Flat Vivado module-reference boundary for CVA6BoardSubsystem.  All SoC logic
// remains native SystemVerilog; this wrapper only describes the repository's
// stable board-shell contract and translates DDR's physical 0x8000_0000 base
// to the Genesys 2 MIG-local address space.

module CVA6BoardWrapper #(
  parameter bit CachedDdr = 1'b0,
  parameter bit TimeCsr   = 1'b0
) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clock CLK",
     X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn, ASSOCIATED_BUSIF MEM_AXI4:DMA_AXI4:IO_AXI4" *)
  input  logic        clock,
  input  logic        clock_ok,
  input  logic        mem_ok,
  input  logic        io_ok,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 sys_reset RST",
     X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
  input  logic        sys_reset,
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
     X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  output logic        aresetn,
  input  logic [7:0]  interrupts,

  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWREADY",
     X_INTERFACE_PARAMETER = "CLK_DOMAIN clock, PROTOCOL AXI4, ADDR_WIDTH 34, DATA_WIDTH 64, ID_WIDTH 10" *)
  input  logic        mem_axi4_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWVALID" *) output logic mem_axi4_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWID"    *) output logic [9:0] mem_axi4_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWADDR"  *) output logic [33:0] mem_axi4_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWLEN"   *) output logic [7:0] mem_axi4_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWSIZE"  *) output logic [2:0] mem_axi4_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWBURST" *) output logic [1:0] mem_axi4_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWLOCK"  *) output logic mem_axi4_awlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWCACHE" *) output logic [3:0] mem_axi4_awcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWPROT"  *) output logic [2:0] mem_axi4_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 AWQOS"   *) output logic [3:0] mem_axi4_awqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 WREADY"  *) input  logic mem_axi4_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 WVALID"  *) output logic mem_axi4_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 WDATA"   *) output logic [63:0] mem_axi4_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 WSTRB"   *) output logic [7:0] mem_axi4_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 WLAST"   *) output logic mem_axi4_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 BREADY"  *) output logic mem_axi4_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 BVALID"  *) input  logic mem_axi4_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 BID"     *) input  logic [9:0] mem_axi4_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 BRESP"   *) input  logic [1:0] mem_axi4_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARREADY" *) input  logic mem_axi4_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARVALID" *) output logic mem_axi4_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARID"    *) output logic [9:0] mem_axi4_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARADDR"  *) output logic [33:0] mem_axi4_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARLEN"   *) output logic [7:0] mem_axi4_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARSIZE"  *) output logic [2:0] mem_axi4_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARBURST" *) output logic [1:0] mem_axi4_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARLOCK"  *) output logic mem_axi4_arlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARCACHE" *) output logic [3:0] mem_axi4_arcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARPROT"  *) output logic [2:0] mem_axi4_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 ARQOS"   *) output logic [3:0] mem_axi4_arqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 RREADY"  *) output logic mem_axi4_rready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 RVALID"  *) input  logic mem_axi4_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 RID"     *) input  logic [9:0] mem_axi4_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 RDATA"   *) input  logic [63:0] mem_axi4_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 RRESP"   *) input  logic [1:0] mem_axi4_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 MEM_AXI4 RLAST"   *) input  logic mem_axi4_rlast,

  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWREADY",
     X_INTERFACE_PARAMETER = "CLK_DOMAIN clock, PROTOCOL AXI4, ADDR_WIDTH 31, DATA_WIDTH 64, ID_WIDTH 10" *)
  input  logic        io_axi4_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWVALID" *) output logic io_axi4_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWID"    *) output logic [9:0] io_axi4_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWADDR"  *) output logic [30:0] io_axi4_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWLEN"   *) output logic [7:0] io_axi4_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWSIZE"  *) output logic [2:0] io_axi4_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWBURST" *) output logic [1:0] io_axi4_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWLOCK"  *) output logic io_axi4_awlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWCACHE" *) output logic [3:0] io_axi4_awcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWPROT"  *) output logic [2:0] io_axi4_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 AWQOS"   *) output logic [3:0] io_axi4_awqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 WREADY"  *) input  logic io_axi4_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 WVALID"  *) output logic io_axi4_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 WDATA"   *) output logic [63:0] io_axi4_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 WSTRB"   *) output logic [7:0] io_axi4_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 WLAST"   *) output logic io_axi4_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 BREADY"  *) output logic io_axi4_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 BVALID"  *) input  logic io_axi4_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 BID"     *) input  logic [9:0] io_axi4_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 BRESP"   *) input  logic [1:0] io_axi4_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARREADY" *) input  logic io_axi4_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARVALID" *) output logic io_axi4_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARID"    *) output logic [9:0] io_axi4_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARADDR"  *) output logic [30:0] io_axi4_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARLEN"   *) output logic [7:0] io_axi4_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARSIZE"  *) output logic [2:0] io_axi4_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARBURST" *) output logic [1:0] io_axi4_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARLOCK"  *) output logic io_axi4_arlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARCACHE" *) output logic [3:0] io_axi4_arcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARPROT"  *) output logic [2:0] io_axi4_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 ARQOS"   *) output logic [3:0] io_axi4_arqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 RREADY"  *) output logic io_axi4_rready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 RVALID"  *) input  logic io_axi4_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 RID"     *) input  logic [9:0] io_axi4_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 RDATA"   *) input  logic [63:0] io_axi4_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 RRESP"   *) input  logic [1:0] io_axi4_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 IO_AXI4 RLAST"   *) input  logic io_axi4_rlast,

  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWREADY",
     X_INTERFACE_PARAMETER = "CLK_DOMAIN clock, PROTOCOL AXI4, ADDR_WIDTH 34, DATA_WIDTH 64, ID_WIDTH 8" *)
  output logic        dma_axi4_awready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWVALID" *) input  logic dma_axi4_awvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWID"    *) input  logic [7:0] dma_axi4_awid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWADDR"  *) input  logic [33:0] dma_axi4_awaddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWLEN"   *) input  logic [7:0] dma_axi4_awlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWSIZE"  *) input  logic [2:0] dma_axi4_awsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWBURST" *) input  logic [1:0] dma_axi4_awburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWLOCK"  *) input  logic dma_axi4_awlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWCACHE" *) input  logic [3:0] dma_axi4_awcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWPROT"  *) input  logic [2:0] dma_axi4_awprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 AWQOS"   *) input  logic [3:0] dma_axi4_awqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 WREADY"  *) output logic dma_axi4_wready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 WVALID"  *) input  logic dma_axi4_wvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 WDATA"   *) input  logic [63:0] dma_axi4_wdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 WSTRB"   *) input  logic [7:0] dma_axi4_wstrb,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 WLAST"   *) input  logic dma_axi4_wlast,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 BREADY"  *) input  logic dma_axi4_bready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 BVALID"  *) output logic dma_axi4_bvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 BID"     *) output logic [7:0] dma_axi4_bid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 BRESP"   *) output logic [1:0] dma_axi4_bresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARREADY" *) output logic dma_axi4_arready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARVALID" *) input  logic dma_axi4_arvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARID"    *) input  logic [7:0] dma_axi4_arid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARADDR"  *) input  logic [33:0] dma_axi4_araddr,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARLEN"   *) input  logic [7:0] dma_axi4_arlen,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARSIZE"  *) input  logic [2:0] dma_axi4_arsize,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARBURST" *) input  logic [1:0] dma_axi4_arburst,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARLOCK"  *) input  logic dma_axi4_arlock,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARCACHE" *) input  logic [3:0] dma_axi4_arcache,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARPROT"  *) input  logic [2:0] dma_axi4_arprot,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 ARQOS"   *) input  logic [3:0] dma_axi4_arqos,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 RREADY"  *) input  logic dma_axi4_rready,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 RVALID"  *) output logic dma_axi4_rvalid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 RID"     *) output logic [7:0] dma_axi4_rid,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 RDATA"   *) output logic [63:0] dma_axi4_rdata,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 RRESP"   *) output logic [1:0] dma_axi4_rresp,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 DMA_AXI4 RLAST"   *) output logic dma_axi4_rlast
);

  localparam logic [63:0] DdrBase = 64'h0000_0000_8000_0000;

  logic reset_inp;
  logic [2:0] reset_sync;
  logic [5:0] reset_count;
  logic       core_reset_n;
  logic [7:0] irq_meta;
  logic [7:0] irq_sync;
  logic       subsystem_reset_n;

  assign reset_inp = sys_reset | ~clock_ok | ~mem_ok | ~io_ok;

  always_ff @(posedge clock or posedge reset_inp) begin
    if (reset_inp) reset_sync <= '1;
    else           reset_sync <= {reset_sync[1:0], 1'b0};
  end

  always_ff @(posedge clock or posedge reset_sync[2]) begin
    if (reset_sync[2]) begin
      reset_count  <= '0;
      aresetn      <= 1'b0;
      core_reset_n <= 1'b0;
    end else begin
      if (reset_count != 6'h3f) reset_count <= reset_count + 1'b1;
      if (reset_count >= 6'd15) aresetn      <= 1'b1;
      if (reset_count >= 6'd31) core_reset_n <= 1'b1;
    end
  end

  always_ff @(posedge clock or negedge core_reset_n) begin
    if (!core_reset_n) begin
      irq_meta <= '0;
      irq_sync <= '0;
    end else begin
      irq_meta <= interrupts;
      irq_sync <= irq_meta;
    end
  end

  AXI_BUS #(.AXI_ADDR_WIDTH(64), .AXI_DATA_WIDTH(64),
            .AXI_ID_WIDTH(10), .AXI_USER_WIDTH(64)) mem_axi();
  AXI_BUS #(.AXI_ADDR_WIDTH(64), .AXI_DATA_WIDTH(64),
            .AXI_ID_WIDTH(10), .AXI_USER_WIDTH(64)) io_axi();
  AXI_BUS #(.AXI_ADDR_WIDTH(64), .AXI_DATA_WIDTH(64),
            .AXI_ID_WIDTH(8), .AXI_USER_WIDTH(64)) dma_axi();

  CVA6BoardSubsystem #(.CachedDdr(CachedDdr), .TimeCsr(TimeCsr)) i_subsystem (
    .clk_i         (clock),
    .rst_ni        (core_reset_n),
    .board_irq_i   (irq_sync),
    .core_reset_no (subsystem_reset_n),
    .mem_axi       (mem_axi),
    .io_axi        (io_axi),
    .dma_axi       (dma_axi)
  );

  // The AXI atomics adapter issues single-beat FIXED bursts for AMOs. The
  // Xilinx MIG does not support FIXED bursts (SmartConnect answers DECERR),
  // and a single-beat FIXED burst is equivalent to INCR, so convert it.
  function automatic logic [1:0] fix_burst(logic [1:0] burst, logic [7:0] len);
    return (burst == axi_pkg::BURST_FIXED && len == 8'd0) ? axi_pkg::BURST_INCR : burst;
  endfunction

  // Master path to the MIG.  The board shell maps the MIG from address zero.
  assign mem_axi4_awvalid = mem_axi.aw_valid;
  assign mem_axi4_awid    = mem_axi.aw_id;
  assign mem_axi4_awaddr  = mem_axi.aw_addr[33:0] - DdrBase[33:0];
  assign mem_axi4_awlen   = mem_axi.aw_len;
  assign mem_axi4_awsize  = mem_axi.aw_size;
  assign mem_axi4_awburst = fix_burst(mem_axi.aw_burst, mem_axi.aw_len);
  assign mem_axi4_awlock  = mem_axi.aw_lock;
  assign mem_axi4_awcache = mem_axi.aw_cache;
  assign mem_axi4_awprot  = mem_axi.aw_prot;
  assign mem_axi4_awqos   = mem_axi.aw_qos;
  assign mem_axi.aw_ready = mem_axi4_awready;
  assign mem_axi4_wvalid  = mem_axi.w_valid;
  assign mem_axi4_wdata   = mem_axi.w_data;
  assign mem_axi4_wstrb   = mem_axi.w_strb;
  assign mem_axi4_wlast   = mem_axi.w_last;
  assign mem_axi.w_ready  = mem_axi4_wready;
  assign mem_axi4_bready  = mem_axi.b_ready;
  assign mem_axi.b_valid  = mem_axi4_bvalid;
  assign mem_axi.b_id     = mem_axi4_bid;
  assign mem_axi.b_resp   = mem_axi4_bresp;
  assign mem_axi.b_user   = '0;
  assign mem_axi4_arvalid = mem_axi.ar_valid;
  assign mem_axi4_arid    = mem_axi.ar_id;
  assign mem_axi4_araddr  = mem_axi.ar_addr[33:0] - DdrBase[33:0];
  assign mem_axi4_arlen   = mem_axi.ar_len;
  assign mem_axi4_arsize  = mem_axi.ar_size;
  assign mem_axi4_arburst = fix_burst(mem_axi.ar_burst, mem_axi.ar_len);
  assign mem_axi4_arlock  = mem_axi.ar_lock;
  assign mem_axi4_arcache = mem_axi.ar_cache;
  assign mem_axi4_arprot  = mem_axi.ar_prot;
  assign mem_axi4_arqos   = mem_axi.ar_qos;
  assign mem_axi.ar_ready = mem_axi4_arready;
  assign mem_axi4_rready  = mem_axi.r_ready;
  assign mem_axi.r_valid  = mem_axi4_rvalid;
  assign mem_axi.r_id     = mem_axi4_rid;
  assign mem_axi.r_data   = mem_axi4_rdata;
  assign mem_axi.r_resp   = mem_axi4_rresp;
  assign mem_axi.r_last   = mem_axi4_rlast;
  assign mem_axi.r_user   = '0;

  // Master path to the repository-owned UART, SD, Ethernet and XADC fabric.
  assign io_axi4_awvalid = io_axi.aw_valid;
  assign io_axi4_awid    = io_axi.aw_id;
  assign io_axi4_awaddr  = io_axi.aw_addr[30:0];
  assign io_axi4_awlen   = io_axi.aw_len;
  assign io_axi4_awsize  = io_axi.aw_size;
  assign io_axi4_awburst = fix_burst(io_axi.aw_burst, io_axi.aw_len);
  assign io_axi4_awlock  = io_axi.aw_lock;
  assign io_axi4_awcache = io_axi.aw_cache;
  assign io_axi4_awprot  = io_axi.aw_prot;
  assign io_axi4_awqos   = io_axi.aw_qos;
  assign io_axi.aw_ready = io_axi4_awready;
  assign io_axi4_wvalid  = io_axi.w_valid;
  assign io_axi4_wdata   = io_axi.w_data;
  assign io_axi4_wstrb   = io_axi.w_strb;
  assign io_axi4_wlast   = io_axi.w_last;
  assign io_axi.w_ready  = io_axi4_wready;
  assign io_axi4_bready  = io_axi.b_ready;
  assign io_axi.b_valid  = io_axi4_bvalid;
  assign io_axi.b_id     = io_axi4_bid;
  assign io_axi.b_resp   = io_axi4_bresp;
  assign io_axi.b_user   = '0;
  assign io_axi4_arvalid = io_axi.ar_valid;
  assign io_axi4_arid    = io_axi.ar_id;
  assign io_axi4_araddr  = io_axi.ar_addr[30:0];
  assign io_axi4_arlen   = io_axi.ar_len;
  assign io_axi4_arsize  = io_axi.ar_size;
  assign io_axi4_arburst = fix_burst(io_axi.ar_burst, io_axi.ar_len);
  assign io_axi4_arlock  = io_axi.ar_lock;
  assign io_axi4_arcache = io_axi.ar_cache;
  assign io_axi4_arprot  = io_axi.ar_prot;
  assign io_axi4_arqos   = io_axi.ar_qos;
  assign io_axi.ar_ready = io_axi4_arready;
  assign io_axi4_rready  = io_axi.r_ready;
  assign io_axi.r_valid  = io_axi4_rvalid;
  assign io_axi.r_id     = io_axi4_rid;
  assign io_axi.r_data   = io_axi4_rdata;
  assign io_axi.r_resp   = io_axi4_rresp;
  assign io_axi.r_last   = io_axi4_rlast;
  assign io_axi.r_user   = '0;

  // Slave path from the repository SD and Ethernet DMA masters.  The complete
  // eight-bit board ID is retained through the native crossbar.
  assign dma_axi.aw_valid  = dma_axi4_awvalid;
  assign dma_axi.aw_id     = dma_axi4_awid;
  assign dma_axi.aw_addr   = {{30{1'b0}}, dma_axi4_awaddr};
  assign dma_axi.aw_len    = dma_axi4_awlen;
  assign dma_axi.aw_size   = dma_axi4_awsize;
  assign dma_axi.aw_burst  = dma_axi4_awburst;
  assign dma_axi.aw_lock   = dma_axi4_awlock;
  assign dma_axi.aw_cache  = dma_axi4_awcache;
  assign dma_axi.aw_prot   = dma_axi4_awprot;
  assign dma_axi.aw_qos    = dma_axi4_awqos;
  assign dma_axi.aw_region = '0;
  assign dma_axi.aw_atop   = '0;
  assign dma_axi.aw_user   = '0;
  assign dma_axi4_awready  = dma_axi.aw_ready;
  assign dma_axi.w_valid   = dma_axi4_wvalid;
  assign dma_axi.w_data    = dma_axi4_wdata;
  assign dma_axi.w_strb    = dma_axi4_wstrb;
  assign dma_axi.w_last    = dma_axi4_wlast;
  assign dma_axi.w_user    = '0;
  assign dma_axi4_wready   = dma_axi.w_ready;
  assign dma_axi.b_ready   = dma_axi4_bready;
  assign dma_axi4_bvalid   = dma_axi.b_valid;
  assign dma_axi4_bid      = dma_axi.b_id;
  assign dma_axi4_bresp    = dma_axi.b_resp;
  assign dma_axi.ar_valid  = dma_axi4_arvalid;
  assign dma_axi.ar_id     = dma_axi4_arid;
  assign dma_axi.ar_addr   = {{30{1'b0}}, dma_axi4_araddr};
  assign dma_axi.ar_len    = dma_axi4_arlen;
  assign dma_axi.ar_size   = dma_axi4_arsize;
  assign dma_axi.ar_burst  = dma_axi4_arburst;
  assign dma_axi.ar_lock   = dma_axi4_arlock;
  assign dma_axi.ar_cache  = dma_axi4_arcache;
  assign dma_axi.ar_prot   = dma_axi4_arprot;
  assign dma_axi.ar_qos    = dma_axi4_arqos;
  assign dma_axi.ar_region = '0;
  assign dma_axi.ar_user   = '0;
  assign dma_axi4_arready  = dma_axi.ar_ready;
  assign dma_axi.r_ready   = dma_axi4_rready;
  assign dma_axi4_rvalid   = dma_axi.r_valid;
  assign dma_axi4_rid      = dma_axi.r_id;
  assign dma_axi4_rdata    = dma_axi.r_data;
  assign dma_axi4_rresp    = dma_axi.r_resp;
  assign dma_axi4_rlast    = dma_axi.r_last;

endmodule
