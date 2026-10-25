// SpinalHDL LiteX-style SoCs (VexiiRiscv, NaxRiscv) on the repository board
// shell.
//
// The SoC comes from the core's own LiteX SoC generator
// (vexiiriscv.soc.litex.SocGen or naxriscv.platform.litex.NaxGen): harts,
// L1/L2 caches, TileLink coherency, CLINT, PLIC and the RISC-V debug module
// with a JTAG TAP. Both generators give the same bus ports; the per-core
// instance is in spinal_soc_inst.vh (src/main/resources/<core>/). This
// wrapper adapts the buses to the board-shell contract shared with the
// other SoCs:
//
//   mBus (AXI4, cached DDR at 0x8000_0000) -> MEM_AXI4, rebased to 0
//   pBus (AXI-Lite, 32-bit)                -> boot ROM at 0x0001_0000 or
//                                             IO_AXI4 (board devices at
//                                             0x6000_0000)
//   DMA_AXI4 (board SD/Ethernet masters)   -> coherent dma_bus (4-bit IDs)
//   interrupts[7:0]                        -> PLIC sources 1..8
//
// No core logic is changed; the generator output is used as is.

`timescale 1ns/1ps

module SpinalBoardWrapper #(
  parameter ROM_HEX = "bootrom.hex"
) (
  input         clock,
  input         clock_ok,
  input         mem_ok,
  input         io_ok,
  input         sys_reset,
  output reg    aresetn,
  input  [7:0]  interrupts,

  input         jtag_tck,
  input         jtag_tms,
  input         jtag_tdi,
  output        jtag_tdo,

  input         mem_axi4_awready,
  output        mem_axi4_awvalid,
  output [7:0]  mem_axi4_awid,
  output [33:0] mem_axi4_awaddr,
  output [7:0]  mem_axi4_awlen,
  output [2:0]  mem_axi4_awsize,
  output [1:0]  mem_axi4_awburst,
  output        mem_axi4_awlock,
  output [3:0]  mem_axi4_awcache,
  output [2:0]  mem_axi4_awprot,
  output [3:0]  mem_axi4_awqos,
  input         mem_axi4_wready,
  output        mem_axi4_wvalid,
  output [63:0] mem_axi4_wdata,
  output [7:0]  mem_axi4_wstrb,
  output        mem_axi4_wlast,
  output        mem_axi4_bready,
  input         mem_axi4_bvalid,
  input  [7:0]  mem_axi4_bid,
  input  [1:0]  mem_axi4_bresp,
  input         mem_axi4_arready,
  output        mem_axi4_arvalid,
  output [7:0]  mem_axi4_arid,
  output [33:0] mem_axi4_araddr,
  output [7:0]  mem_axi4_arlen,
  output [2:0]  mem_axi4_arsize,
  output [1:0]  mem_axi4_arburst,
  output        mem_axi4_arlock,
  output [3:0]  mem_axi4_arcache,
  output [2:0]  mem_axi4_arprot,
  output [3:0]  mem_axi4_arqos,
  output        mem_axi4_rready,
  input         mem_axi4_rvalid,
  input  [7:0]  mem_axi4_rid,
  input  [63:0] mem_axi4_rdata,
  input  [1:0]  mem_axi4_rresp,
  input         mem_axi4_rlast,

  input         io_axi4_awready,
  output        io_axi4_awvalid,
  output [3:0]  io_axi4_awid,
  output [30:0] io_axi4_awaddr,
  output [7:0]  io_axi4_awlen,
  output [2:0]  io_axi4_awsize,
  output [1:0]  io_axi4_awburst,
  output        io_axi4_awlock,
  output [3:0]  io_axi4_awcache,
  output [2:0]  io_axi4_awprot,
  output [3:0]  io_axi4_awqos,
  input         io_axi4_wready,
  output        io_axi4_wvalid,
  output [63:0] io_axi4_wdata,
  output [7:0]  io_axi4_wstrb,
  output        io_axi4_wlast,
  output        io_axi4_bready,
  input         io_axi4_bvalid,
  input  [3:0]  io_axi4_bid,
  input  [1:0]  io_axi4_bresp,
  input         io_axi4_arready,
  output        io_axi4_arvalid,
  output [3:0]  io_axi4_arid,
  output [30:0] io_axi4_araddr,
  output [7:0]  io_axi4_arlen,
  output [2:0]  io_axi4_arsize,
  output [1:0]  io_axi4_arburst,
  output        io_axi4_arlock,
  output [3:0]  io_axi4_arcache,
  output [2:0]  io_axi4_arprot,
  output [3:0]  io_axi4_arqos,
  output        io_axi4_rready,
  input         io_axi4_rvalid,
  input  [3:0]  io_axi4_rid,
  input  [63:0] io_axi4_rdata,
  input  [1:0]  io_axi4_rresp,
  input         io_axi4_rlast,

  output        dma_axi4_awready,
  input         dma_axi4_awvalid,
  input  [7:0]  dma_axi4_awid,
  input  [33:0] dma_axi4_awaddr,
  input  [7:0]  dma_axi4_awlen,
  input  [2:0]  dma_axi4_awsize,
  input  [1:0]  dma_axi4_awburst,
  input         dma_axi4_awlock,
  input  [3:0]  dma_axi4_awcache,
  input  [2:0]  dma_axi4_awprot,
  input  [3:0]  dma_axi4_awqos,
  output        dma_axi4_wready,
  input         dma_axi4_wvalid,
  input  [63:0] dma_axi4_wdata,
  input  [7:0]  dma_axi4_wstrb,
  input         dma_axi4_wlast,
  input         dma_axi4_bready,
  output        dma_axi4_bvalid,
  output [7:0]  dma_axi4_bid,
  output [1:0]  dma_axi4_bresp,
  output        dma_axi4_arready,
  input         dma_axi4_arvalid,
  input  [7:0]  dma_axi4_arid,
  input  [33:0] dma_axi4_araddr,
  input  [7:0]  dma_axi4_arlen,
  input  [2:0]  dma_axi4_arsize,
  input  [1:0]  dma_axi4_arburst,
  input         dma_axi4_arlock,
  input  [3:0]  dma_axi4_arcache,
  input  [2:0]  dma_axi4_arprot,
  input  [3:0]  dma_axi4_arqos,
  input         dma_axi4_rready,
  output        dma_axi4_rvalid,
  output [7:0]  dma_axi4_rid,
  output [63:0] dma_axi4_rdata,
  output [1:0]  dma_axi4_rresp,
  output        dma_axi4_rlast
);

  // -------------------------------------------------------------------
  // Reset sequencing (same order as the CVA6 and NOEL-V wrappers): the
  // board AXI fabric leaves reset first, the SoC 16 cycles later.
  // -------------------------------------------------------------------
  wire       reset_inp = sys_reset | ~clock_ok | ~mem_ok | ~io_ok;
  reg  [2:0] reset_sync;
  reg  [5:0] reset_count;
  reg        core_reset_n;
  reg  [7:0] irq_meta;
  reg  [7:0] irq_sync;
  wire       ndmreset;

  always @(posedge clock or posedge reset_inp) begin
    if (reset_inp) reset_sync <= 3'b111;
    else           reset_sync <= {reset_sync[1:0], 1'b0};
  end

  always @(posedge clock or posedge reset_sync[2]) begin
    if (reset_sync[2]) begin
      reset_count  <= 6'd0;
      aresetn      <= 1'b0;
      core_reset_n <= 1'b0;
    end else begin
      if (reset_count != 6'h3f) reset_count <= reset_count + 6'd1;
      if (reset_count >= 6'd15) aresetn      <= 1'b1;
      if (reset_count >= 6'd31) core_reset_n <= 1'b1;
    end
  end

  always @(posedge clock or negedge core_reset_n) begin
    if (!core_reset_n) begin
      irq_meta <= 8'd0;
      irq_sync <= 8'd0;
    end else begin
      irq_meta <= interrupts;
      irq_sync <= irq_meta;
    end
  end

  // The debug module keeps running through a debugger-requested ndmreset;
  // only the board reset clears it.
  wire soc_reset = ~core_reset_n | ndmreset;

  // -------------------------------------------------------------------
  // SoC buses
  // -------------------------------------------------------------------
  wire        p_awvalid, p_awready, p_wvalid, p_wready, p_bvalid, p_bready;
  wire        p_arvalid, p_arready, p_rvalid, p_rready;
  wire [31:0] p_awaddr, p_araddr, p_wdata;
  wire [3:0]  p_wstrb;
  reg  [31:0] p_rdata;
  reg  [1:0]  p_rresp, p_bresp;

  wire [31:0] m_awaddr, m_araddr;

  wire        d_awvalid, d_awready, d_arvalid, d_arready;
  wire        d_bvalid, d_rvalid;
  wire [3:0]  d_bid, d_rid;

  `include "spinal_soc_inst.vh"

  // -------------------------------------------------------------------
  // mBus -> MEM_AXI4: DDR is at 0x8000_0000 for the CPU and at 0 for MIG.
  // -------------------------------------------------------------------
  assign mem_axi4_awaddr  = {2'b00, m_awaddr} - 34'h0_8000_0000;
  assign mem_axi4_araddr  = {2'b00, m_araddr} - 34'h0_8000_0000;
  assign mem_axi4_awlock  = 1'b0;
  assign mem_axi4_awcache = 4'b1111;
  assign mem_axi4_awprot  = 3'b001;
  assign mem_axi4_awqos   = 4'd0;
  assign mem_axi4_arlock  = 1'b0;
  assign mem_axi4_arcache = 4'b1111;
  assign mem_axi4_arprot  = 3'b001;
  assign mem_axi4_arqos   = 4'd0;

  // -------------------------------------------------------------------
  // DMA_AXI4 -> dma_bus. The SoC's DMA port has 4-bit IDs and the board
  // fabric uses 8, so the adapter keeps one read and one write burst in
  // flight and returns the saved ID. Bursts stay in order per channel.
  // -------------------------------------------------------------------
  reg       dma_rd_busy, dma_wr_busy;
  reg [7:0] dma_rd_id,   dma_wr_id;

  assign d_arvalid        = dma_axi4_arvalid & ~dma_rd_busy;
  assign dma_axi4_arready = d_arready & ~dma_rd_busy;
  assign dma_axi4_rvalid  = d_rvalid;
  assign dma_axi4_rid     = dma_rd_id;

  assign d_awvalid        = dma_axi4_awvalid & ~dma_wr_busy;
  assign dma_axi4_awready = d_awready & ~dma_wr_busy;
  assign dma_axi4_bvalid  = d_bvalid;
  assign dma_axi4_bid     = dma_wr_id;

  always @(posedge clock or negedge core_reset_n) begin
    if (!core_reset_n) begin
      dma_rd_busy <= 1'b0;
      dma_wr_busy <= 1'b0;
      dma_rd_id   <= 8'd0;
      dma_wr_id   <= 8'd0;
    end else begin
      if (d_arvalid & d_arready) begin
        dma_rd_busy <= 1'b1;
        dma_rd_id   <= dma_axi4_arid;
      end else if (d_rvalid & dma_axi4_rready & dma_axi4_rlast) begin
        dma_rd_busy <= 1'b0;
      end
      if (d_awvalid & d_awready) begin
        dma_wr_busy <= 1'b1;
        dma_wr_id   <= dma_axi4_awid;
      end else if (d_bvalid & dma_axi4_bready) begin
        dma_wr_busy <= 1'b0;
      end
    end
  end

  // -------------------------------------------------------------------
  // pBus: boot ROM (0x0001_0000, 64 KiB) and board IO (IO_AXI4). One
  // transaction at a time; IO accesses become single 32-bit AXI4 beats
  // on the 64-bit IO bus.
  // -------------------------------------------------------------------
  (* rom_style = "block" *) reg [31:0] rom [0:16383];
  initial $readmemh(ROM_HEX, rom);
  reg [31:0] rom_q;
  reg [31:0] p_addr;
  reg [31:0] p_wdata_q;
  reg [3:0]  p_wstrb_q;

  always @(posedge clock) rom_q <= rom[p_addr[15:2]];

  localparam S_IDLE = 3'd0, S_ROM0 = 3'd1, S_ROM1 = 3'd2, S_IO_AR = 3'd3, S_IO_R = 3'd4,
             S_RRSP = 3'd5, S_IO_W = 3'd6, S_BRSP = 3'd7;
  reg [2:0] p_state;
  reg       io_aw_done, io_w_done;
  reg       io_b_wait;

  wire rd_is_rom = p_araddr[31:16] == 16'h0001;
  wire wr_is_rom = p_awaddr[31:16] == 16'h0001;
  wire take_rd   = p_state == S_IDLE && p_arvalid;
  wire take_wr   = p_state == S_IDLE && !p_arvalid && p_awvalid && p_wvalid;

  assign p_arready = take_rd;
  assign p_awready = take_wr;
  assign p_wready  = take_wr;
  assign p_rvalid  = p_state == S_RRSP;
  assign p_bvalid  = p_state == S_BRSP;

  assign io_axi4_arvalid = p_state == S_IO_AR;
  assign io_axi4_araddr  = {p_addr[30:2], 2'b00};
  assign io_axi4_arid    = 4'd0;
  assign io_axi4_arlen   = 8'd0;
  assign io_axi4_arsize  = 3'd2;
  assign io_axi4_arburst = 2'b01;
  assign io_axi4_arlock  = 1'b0;
  assign io_axi4_arcache = 4'd0;
  assign io_axi4_arprot  = 3'd0;
  assign io_axi4_arqos   = 4'd0;
  assign io_axi4_rready  = p_state == S_IO_R;

  assign io_axi4_awvalid = p_state == S_IO_W && !io_aw_done;
  assign io_axi4_awaddr  = {p_addr[30:2], 2'b00};
  assign io_axi4_awid    = 4'd0;
  assign io_axi4_awlen   = 8'd0;
  assign io_axi4_awsize  = 3'd2;
  assign io_axi4_awburst = 2'b01;
  assign io_axi4_awlock  = 1'b0;
  assign io_axi4_awcache = 4'd0;
  assign io_axi4_awprot  = 3'd0;
  assign io_axi4_awqos   = 4'd0;
  assign io_axi4_wvalid  = p_state == S_IO_W && !io_w_done;
  assign io_axi4_wdata   = {p_wdata_q, p_wdata_q};
  assign io_axi4_wstrb   = p_addr[2] ? {p_wstrb_q, 4'b0000} : {4'b0000, p_wstrb_q};
  assign io_axi4_wlast   = 1'b1;
  assign io_axi4_bready  = p_state == S_IO_W && io_aw_done && io_w_done;

  always @(posedge clock or posedge soc_reset) begin
    if (soc_reset) begin
      p_state    <= S_IDLE;
      p_addr     <= 32'd0;
      p_wdata_q  <= 32'd0;
      p_wstrb_q  <= 4'd0;
      p_rdata    <= 32'd0;
      p_rresp    <= 2'b00;
      p_bresp    <= 2'b00;
      io_aw_done <= 1'b0;
      io_w_done  <= 1'b0;
    end else begin
      case (p_state)
        S_IDLE: begin
          if (take_rd) begin
            p_addr  <= p_araddr;
            p_state <= rd_is_rom ? S_ROM0 : S_IO_AR;
          end else if (take_wr) begin
            p_addr     <= p_awaddr;
            p_wdata_q  <= p_wdata;
            p_wstrb_q  <= p_wstrb;
            io_aw_done <= 1'b0;
            io_w_done  <= 1'b0;
            p_bresp    <= 2'b00;
            p_state    <= wr_is_rom ? S_BRSP : S_IO_W;
          end
        end
        S_ROM0: p_state <= S_ROM1;   // rom_q follows p_addr
        S_ROM1: begin
          p_rdata <= rom_q;
          p_rresp <= 2'b00;
          p_state <= S_RRSP;
        end
        S_IO_AR: if (io_axi4_arready) p_state <= S_IO_R;
        S_IO_R: if (io_axi4_rvalid) begin
          p_rdata <= p_addr[2] ? io_axi4_rdata[63:32] : io_axi4_rdata[31:0];
          p_rresp <= io_axi4_rresp;
          p_state <= S_RRSP;
        end
        S_RRSP: if (p_rready) p_state <= S_IDLE;
        S_IO_W: begin
          if (io_axi4_awvalid && io_axi4_awready) io_aw_done <= 1'b1;
          if (io_axi4_wvalid && io_axi4_wready) io_w_done <= 1'b1;
          if (io_axi4_bready && io_axi4_bvalid) begin
            p_bresp <= io_axi4_bresp;
            p_state <= S_BRSP;
          end
        end
        S_BRSP: if (p_bready) p_state <= S_IDLE;
        default: p_state <= S_IDLE;
      endcase
    end
  end

endmodule
