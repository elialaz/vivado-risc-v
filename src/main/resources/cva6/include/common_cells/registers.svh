// Copyright 2018 ETH Zurich and University of Bologna.
//
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51.
// SPDX-License-Identifier: SHL-0.51
//
// Vivado-compatible form of the register macros pinned by CVFPU.  The CVFPU
// copy embeds preprocessor conditionals in multi-line macro definitions;
// Vivado stops parsing that header at the first such conditional and leaves
// all following macros undefined.  These definitions preserve the hardware
// behavior while omitting synthesis-pragmas that are not functionally needed.

`ifndef VIVADO_CVA6_COMMON_CELLS_REGISTERS_SVH_
`define VIVADO_CVA6_COMMON_CELLS_REGISTERS_SVH_

`define FF(__q, __d, __reset_value)                  \
  always_ff @(posedge clk_i or negedge rst_ni) begin \
    if (!rst_ni) __q <= (__reset_value);             \
    else         __q <= (__d);                       \
  end

`define FFAR(__q, __d, __reset_value, __clk, __arst)     \
  always_ff @(posedge (__clk) or posedge (__arst)) begin \
    if (__arst) __q <= (__reset_value);                   \
    else        __q <= (__d);                             \
  end

`define FFARN(__q, __d, __reset_value, __clk, __arst_n)    \
  always_ff @(posedge (__clk) or negedge (__arst_n)) begin \
    if (!__arst_n) __q <= (__reset_value);                  \
    else           __q <= (__d);                            \
  end

`define FFSR(__q, __d, __reset_value, __clk, __reset_clk) \
  always_ff @(posedge (__clk)) begin                       \
    __q <= (__reset_clk) ? (__reset_value) : (__d);        \
  end

`define FFSRN(__q, __d, __reset_value, __clk, __reset_n_clk) \
  always_ff @(posedge (__clk)) begin                          \
    __q <= (!__reset_n_clk) ? (__reset_value) : (__d);        \
  end

`define FFNR(__q, __d, __clk)        \
  always_ff @(posedge (__clk)) begin \
    __q <= (__d);                    \
  end

`define FFL(__q, __d, __load, __reset_value)         \
  always_ff @(posedge clk_i or negedge rst_ni) begin \
    if (!rst_ni) __q <= (__reset_value);             \
    else         __q <= (__load) ? (__d) : (__q);    \
  end

`define FFLAR(__q, __d, __load, __reset_value, __clk, __arst) \
  always_ff @(posedge (__clk) or posedge (__arst)) begin       \
    if (__arst) __q <= (__reset_value);                         \
    else        __q <= (__load) ? (__d) : (__q);                \
  end

`define FFLARN(__q, __d, __load, __reset_value, __clk, __arst_n) \
  always_ff @(posedge (__clk) or negedge (__arst_n)) begin        \
    if (!__arst_n) __q <= (__reset_value);                         \
    else           __q <= (__load) ? (__d) : (__q);                \
  end

`define FFLSR(__q, __d, __load, __reset_value, __clk, __reset_clk)       \
  always_ff @(posedge (__clk)) begin                                     \
    __q <= (__reset_clk) ? (__reset_value) : ((__load) ? (__d) : (__q)); \
  end

`define FFLSRN(__q, __d, __load, __reset_value, __clk, __reset_n_clk)       \
  always_ff @(posedge (__clk)) begin                                        \
    __q <= (!__reset_n_clk) ? (__reset_value) : ((__load) ? (__d) : (__q)); \
  end

`define FFLARNC(__q, __d, __load, __clear, __reset_value, __clk, __arst_n) \
  always_ff @(posedge (__clk) or negedge (__arst_n)) begin                 \
    if (!__arst_n) __q <= (__reset_value);                                 \
    else           __q <= (__clear) ? (__reset_value) :                    \
                          ((__load) ? (__d) : (__q));                       \
  end

`define FFLNR(__q, __d, __load, __clk) \
  always_ff @(posedge (__clk)) begin   \
    __q <= (__load) ? (__d) : (__q);   \
  end

`endif
