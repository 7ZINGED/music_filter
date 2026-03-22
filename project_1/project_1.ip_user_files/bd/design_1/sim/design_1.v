//Copyright 1986-2018 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2018.3 (win64) Build 2405991 Thu Dec  6 23:38:27 MST 2018
//Date        : Sun Mar 22 01:05:00 2026
//Host        : tianxuan4 running 64-bit major release  (build 9200)
//Command     : generate_target design_1.bd
//Design      : design_1
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "design_1,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=design_1,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=1,numReposBlks=1,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=0,numPkgbdBlks=0,bdsource=USER,synth_mode=OOC_per_IP}" *) (* HW_HANDOFF = "design_1.hwdef" *) 
module design_1
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

  wire clk_1;
  wire [23:0]fir_compiler_0_m_axis_data_tdata;
  wire fir_compiler_0_m_axis_data_tvalid;
  wire fir_compiler_0_s_axis_data_tready;
  wire s_axis_data_tvalid_1;
  wire [23:0]signal1_1;

  assign clk_1 = clk;
  assign m_axis_data_tvalid = fir_compiler_0_m_axis_data_tvalid;
  assign s_axis_data_tready = fir_compiler_0_s_axis_data_tready;
  assign s_axis_data_tvalid_1 = s_axis_data_tvalid;
  assign signal1_1 = signal1[23:0];
  assign signal2[23:0] = fir_compiler_0_m_axis_data_tdata;
  design_1_fir_compiler_0_0 fir_compiler_0
       (.aclk(clk_1),
        .m_axis_data_tdata(fir_compiler_0_m_axis_data_tdata),
        .m_axis_data_tvalid(fir_compiler_0_m_axis_data_tvalid),
        .s_axis_data_tdata(signal1_1),
        .s_axis_data_tready(fir_compiler_0_s_axis_data_tready),
        .s_axis_data_tvalid(s_axis_data_tvalid_1));
endmodule
