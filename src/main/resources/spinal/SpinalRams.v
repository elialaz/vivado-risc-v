// Inferred-RAM implementations of the SpinalHDL memory black boxes used by
// the VexiiRiscv and NaxRiscv SoC netlists (byte-masked writes and
// asynchronous reads).
// Same module interface as SpinalHDL's Ram_1w_1rs / Ram_1w_1ra black boxes.

`timescale 1ns/1ps

// One write port, one synchronous read port (block RAM).
module Ram_1w_1rs #(
  parameter integer wordCount      = 0,
  parameter integer wordWidth      = 0,
  parameter         clockCrossing  = 1'b0,
  parameter         technology     = "auto",
  parameter         readUnderWrite = "dontCare",
  parameter integer wrAddressWidth = 0,
  parameter integer wrDataWidth    = 0,
  parameter integer wrMaskWidth    = 0,
  parameter         wrMaskEnable   = 1'b0,
  parameter integer rdAddressWidth = 0,
  parameter integer rdDataWidth    = 0,
  parameter integer rdLatency      = 1
) (
  input  wire                      wr_clk,
  input  wire                      wr_en,
  input  wire [wrMaskWidth-1:0]    wr_mask,
  input  wire [wrAddressWidth-1:0] wr_addr,
  input  wire [wrDataWidth-1:0]    wr_data,
  input  wire                      rd_clk,
  input  wire                      rd_en,
  input  wire                      rd_dataEn,
  input  wire [rdAddressWidth-1:0] rd_addr,
  output wire [rdDataWidth-1:0]    rd_data
);
  localparam integer COL = wrMaskEnable ? wrDataWidth / wrMaskWidth : wrDataWidth;
  localparam integer NCOL = wrMaskEnable ? wrMaskWidth : 1;

  reg [wrDataWidth-1:0] ram [0:(1 << wrAddressWidth) - 1];
  reg [rdDataWidth-1:0] q;
  integer i;

  always @(posedge wr_clk) begin
    if (wr_en) begin
      for (i = 0; i < NCOL; i = i + 1) begin
        if (!wrMaskEnable || wr_mask[i])
          ram[wr_addr][i*COL +: COL] <= wr_data[i*COL +: COL];
      end
    end
  end

  always @(posedge rd_clk) begin
    if (rd_en) q <= ram[rd_addr];
  end
  assign rd_data = q;
endmodule

// One write port, one asynchronous read port (distributed RAM).
module Ram_1w_1ra #(
  parameter integer wordCount      = 0,
  parameter integer wordWidth      = 0,
  parameter         technology     = "auto",
  parameter         readUnderWrite = "dontCare",
  parameter integer wrAddressWidth = 0,
  parameter integer wrDataWidth    = 0,
  parameter integer wrMaskWidth    = 0,
  parameter         wrMaskEnable   = 1'b0,
  parameter integer rdAddressWidth = 0,
  parameter integer rdDataWidth    = 0
) (
  input  wire                      clk,
  input  wire                      wr_en,
  input  wire [wrMaskWidth-1:0]    wr_mask,
  input  wire [wrAddressWidth-1:0] wr_addr,
  input  wire [wrDataWidth-1:0]    wr_data,
  input  wire [rdAddressWidth-1:0] rd_addr,
  output wire [rdDataWidth-1:0]    rd_data
);
  localparam integer COL = wrMaskEnable ? wrDataWidth / wrMaskWidth : wrDataWidth;
  localparam integer NCOL = wrMaskEnable ? wrMaskWidth : 1;

  (* ram_style = "distributed" *) reg [wrDataWidth-1:0] ram [0:(1 << wrAddressWidth) - 1];
  integer i;

  always @(posedge clk) begin
    if (wr_en) begin
      for (i = 0; i < NCOL; i = i + 1) begin
        if (!wrMaskEnable || wr_mask[i])
          ram[wr_addr][i*COL +: COL] <= wr_data[i*COL +: COL];
      end
    end
  end

  assign rd_data = ram[rd_addr];
endmodule
