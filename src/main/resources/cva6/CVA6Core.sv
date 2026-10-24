// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Thin integration wrapper around the official `ariane` top and its AXI
// atomics converter. The CPU RTL comes from generators/cva6; the CVA6
// configuration (PMA, cached regions) is owned by CVA6BoardSubsystem.

`include "axi/assign.svh"

module CVA6Core #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
  // 1 = the core has the repository time-CSR patch (patches/cva6/hp2) and
  // reads mtime from time_i instead of trapping to OpenSBI on rdtime.
  parameter bit TimeCsr = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [63:0] boot_addr_i,
  input  logic [63:0] hart_id_i,
  input  logic [1:0]  irq_i,
  input  logic        ipi_i,
  input  logic        time_irq_i,
  input  logic [63:0] time_i,
  input  logic        debug_req_i,

  input  logic        axi_resp_i_aw_ready,
  output logic        axi_req_o_aw_valid,
  output logic [3:0]  axi_req_o_aw_bits_id,
  output logic [63:0] axi_req_o_aw_bits_addr,
  output logic [7:0]  axi_req_o_aw_bits_len,
  output logic [2:0]  axi_req_o_aw_bits_size,
  output logic [1:0]  axi_req_o_aw_bits_burst,
  output logic        axi_req_o_aw_bits_lock,
  output logic [3:0]  axi_req_o_aw_bits_cache,
  output logic [2:0]  axi_req_o_aw_bits_prot,
  output logic [3:0]  axi_req_o_aw_bits_qos,
  output logic [3:0]  axi_req_o_aw_bits_region,
  output logic [5:0]  axi_req_o_aw_bits_atop,
  output logic [63:0] axi_req_o_aw_bits_user,

  input  logic        axi_resp_i_w_ready,
  output logic        axi_req_o_w_valid,
  output logic [63:0] axi_req_o_w_bits_data,
  output logic [7:0]  axi_req_o_w_bits_strb,
  output logic        axi_req_o_w_bits_last,
  output logic [63:0] axi_req_o_w_bits_user,

  input  logic        axi_resp_i_ar_ready,
  output logic        axi_req_o_ar_valid,
  output logic [3:0]  axi_req_o_ar_bits_id,
  output logic [63:0] axi_req_o_ar_bits_addr,
  output logic [7:0]  axi_req_o_ar_bits_len,
  output logic [2:0]  axi_req_o_ar_bits_size,
  output logic [1:0]  axi_req_o_ar_bits_burst,
  output logic        axi_req_o_ar_bits_lock,
  output logic [3:0]  axi_req_o_ar_bits_cache,
  output logic [2:0]  axi_req_o_ar_bits_prot,
  output logic [3:0]  axi_req_o_ar_bits_qos,
  output logic [3:0]  axi_req_o_ar_bits_region,
  output logic [63:0] axi_req_o_ar_bits_user,

  output logic        axi_req_o_b_ready,
  input  logic        axi_resp_i_b_valid,
  input  logic [3:0]  axi_resp_i_b_bits_id,
  input  logic [1:0]  axi_resp_i_b_bits_resp,
  input  logic [63:0] axi_resp_i_b_bits_user,

  output logic        axi_req_o_r_ready,
  input  logic        axi_resp_i_r_valid,
  input  logic [3:0]  axi_resp_i_r_bits_id,
  input  logic [63:0] axi_resp_i_r_bits_data,
  input  logic [1:0]  axi_resp_i_r_bits_resp,
  input  logic        axi_resp_i_r_bits_last,
  input  logic [63:0] axi_resp_i_r_bits_user
);

  ariane_axi::req_t  cva6_req;
  ariane_axi::resp_t cva6_resp;

  if (TimeCsr) begin : g_time_csr
    ariane #(.CVA6Cfg(CVA6Cfg)) i_cva6 (
      .clk_i,
      .rst_ni,
      .boot_addr_i,
      .hart_id_i,
      .irq_i,
      .ipi_i,
      .time_irq_i,
      .time_i,
      .debug_req_i,
      .rvfi_probes_o(),
      .noc_req_o(cva6_req),
      .noc_resp_i(cva6_resp)
    );
  end else begin : g_no_time_csr
    ariane #(.CVA6Cfg(CVA6Cfg)) i_cva6 (
      .clk_i,
      .rst_ni,
      .boot_addr_i,
      .hart_id_i,
      .irq_i,
      .ipi_i,
      .time_irq_i,
      .debug_req_i,
      .rvfi_probes_o(),
      .noc_req_o(cva6_req),
      .noc_resp_i(cva6_resp)
    );
  end

  AXI_BUS #(
    .AXI_ADDR_WIDTH(64),
    .AXI_DATA_WIDTH(64),
    .AXI_ID_WIDTH(4),
    .AXI_USER_WIDTH(64)
  ) cva6_axi();

  `AXI_ASSIGN_FROM_REQ(cva6_axi, cva6_req)
  `AXI_ASSIGN_TO_RESP(cva6_resp, cva6_axi)

  AXI_BUS #(
    .AXI_ADDR_WIDTH(64),
    .AXI_DATA_WIDTH(64),
    .AXI_ID_WIDTH(4),
    .AXI_USER_WIDTH(64)
  ) soc_axi();

  // AMOs leave the core as AXI5 ATOPs. They are resolved by the atomics
  // adapter on the DDR port of the SoC crossbar (as in the official CVA6
  // FPGA SoC), not here: the adapter assumes an in-order downstream slave.
  `AXI_ASSIGN(soc_axi, cva6_axi)

  assign soc_axi.aw_ready = axi_resp_i_aw_ready;
  assign axi_req_o_aw_valid = soc_axi.aw_valid;
  assign axi_req_o_aw_bits_id = soc_axi.aw_id;
  assign axi_req_o_aw_bits_addr = soc_axi.aw_addr;
  assign axi_req_o_aw_bits_len = soc_axi.aw_len;
  assign axi_req_o_aw_bits_size = soc_axi.aw_size;
  assign axi_req_o_aw_bits_burst = soc_axi.aw_burst;
  assign axi_req_o_aw_bits_lock = soc_axi.aw_lock;
  assign axi_req_o_aw_bits_cache = soc_axi.aw_cache;
  assign axi_req_o_aw_bits_prot = soc_axi.aw_prot;
  assign axi_req_o_aw_bits_qos = soc_axi.aw_qos;
  assign axi_req_o_aw_bits_region = soc_axi.aw_region;
  assign axi_req_o_aw_bits_atop = soc_axi.aw_atop;
  assign axi_req_o_aw_bits_user = soc_axi.aw_user;

  assign soc_axi.w_ready = axi_resp_i_w_ready;
  assign axi_req_o_w_valid = soc_axi.w_valid;
  assign axi_req_o_w_bits_data = soc_axi.w_data;
  assign axi_req_o_w_bits_strb = soc_axi.w_strb;
  assign axi_req_o_w_bits_last = soc_axi.w_last;
  assign axi_req_o_w_bits_user = soc_axi.w_user;

  assign soc_axi.ar_ready = axi_resp_i_ar_ready;
  assign axi_req_o_ar_valid = soc_axi.ar_valid;
  assign axi_req_o_ar_bits_id = soc_axi.ar_id;
  assign axi_req_o_ar_bits_addr = soc_axi.ar_addr;
  assign axi_req_o_ar_bits_len = soc_axi.ar_len;
  assign axi_req_o_ar_bits_size = soc_axi.ar_size;
  assign axi_req_o_ar_bits_burst = soc_axi.ar_burst;
  assign axi_req_o_ar_bits_lock = soc_axi.ar_lock;
  assign axi_req_o_ar_bits_cache = soc_axi.ar_cache;
  assign axi_req_o_ar_bits_prot = soc_axi.ar_prot;
  assign axi_req_o_ar_bits_qos = soc_axi.ar_qos;
  assign axi_req_o_ar_bits_region = soc_axi.ar_region;
  assign axi_req_o_ar_bits_user = soc_axi.ar_user;

  assign axi_req_o_b_ready = soc_axi.b_ready;
  assign soc_axi.b_valid = axi_resp_i_b_valid;
  assign soc_axi.b_id = axi_resp_i_b_bits_id;
  assign soc_axi.b_resp = axi_resp_i_b_bits_resp;
  assign soc_axi.b_user = axi_resp_i_b_bits_user;

  assign axi_req_o_r_ready = soc_axi.r_ready;
  assign soc_axi.r_valid = axi_resp_i_r_valid;
  assign soc_axi.r_id = axi_resp_i_r_bits_id;
  assign soc_axi.r_data = axi_resp_i_r_bits_data;
  assign soc_axi.r_resp = axi_resp_i_r_bits_resp;
  assign soc_axi.r_last = axi_resp_i_r_bits_last;
  assign soc_axi.r_user = axi_resp_i_r_bits_user;

endmodule
