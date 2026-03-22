//Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
//Date        : Sun Mar 22 01:05:00 2026
//Host        : tianxuan4 running 64-bit major release  (build 9200)
//Command     : generate_target design_1_wrapper.bd
//Design      : design_1_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module design_1_wrapper
   (clk,
    m_axis_data_tvalid,
    s_axis_data_tready,
    s_axis_data_tvalid,
    signal1,
    signal2);
  input clk;
  output m_axis_data_tvalid;
  output s_axis_data_tready;
  input s_axis_data_tvalid;
  input [23:0]signal1;
  output [23:0]signal2;

  wire clk;
  wire m_axis_data_tvalid;
  wire s_axis_data_tready;
  wire s_axis_data_tvalid;
  wire [23:0]signal1;
  wire [23:0]signal2;

  design_1 design_1_i
       (.clk(clk),
        .m_axis_data_tvalid(m_axis_data_tvalid),
        .s_axis_data_tready(s_axis_data_tready),
        .s_axis_data_tvalid(s_axis_data_tvalid),
        .signal1(signal1),
        .signal2(signal2));
endmodule
