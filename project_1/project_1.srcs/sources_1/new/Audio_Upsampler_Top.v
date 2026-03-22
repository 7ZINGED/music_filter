`timescale 1ns / 1ps

module Audio_Upsampler_Top #(
    parameter DATA_W = 24
)(
    input  wire                 clk,         // 系统高频主时钟 (100MHz)
    input  wire                 rst_n,       // 全局复位
    
    // --- 外部控制接口 ---
    input  wire                 sys_fs_sel,  // 0: 48kHz频系, 1: 44.1kHz频系
    input  wire [1:0]           sys_mode,    // 00: 4x, 01: 8x, 10: 128x
    
    // --- 音频数据输入接口 ---
    input  wire                 i2s_lrclk,   
    input  wire signed [DATA_W-1:0] audio_in,
    
    // --- 音频数据输出接口 (送往 DAC) ---
    output reg                  final_valid, // 均匀的 DAC 脉冲
    output reg signed [DATA_W-1:0] final_data// 均匀的 DAC 数据
);

    // ==========================================
    // 1. 基准 Fs 脉冲生成 (Edge Detector)
    // ==========================================
    reg lrclk_d1, lrclk_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lrclk_d1 <= 1'b0;
            lrclk_d2 <= 1'b0;
        end else begin
            lrclk_d1 <= i2s_lrclk;
            lrclk_d2 <= lrclk_d1;
        end
    end
    
    wire fs_valid_base = lrclk_d1 & ~lrclk_d2; 

    // ==========================================
    // 2. 内部级联数据流信号定义
    // ==========================================
    wire                 s1_valid_out;
    wire signed [DATA_W-1:0] s1_data_out;
    
    wire                 s2_valid_out; 
    wire signed [DATA_W-1:0] s2_data_out;  
    
    wire                 s3_valid_out;
    wire signed [DATA_W-1:0] s3_data_out;
    
    wire                 s4_valid_out;
    wire signed [DATA_W-1:0] s4_data_out;

    // ==========================================
    // 3. 模块例化
    // ==========================================

    // ------------------------------------------
    // [Stage 1] 1x -> 2x (硬编码版)
    // ------------------------------------------
    Stage1_HFB1 #(
        .DATA_W(DATA_W)
    ) stage1_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .sys_fs_sel  (sys_fs_sel),
        .valid_in    (fs_valid_base), 
        .data_in     (audio_in),    
        .valid_out   (s1_valid_out),
        .data_out    (s1_data_out)
    );

    // ------------------------------------------
    // [Stage 2] 2x -> 4x (硬编码 + DAC 均匀化版)
    // ------------------------------------------
    Stage2_HFB2 #(
        .DATA_W(DATA_W),
        .CLK_FREQ(100_000_000)
    ) stage2_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .sys_fs_sel  (sys_fs_sel),
        .valid_in    (s1_valid_out),  // 接收 Stage 1 的突发输出
        .data_in     (s1_data_out),
        .dac_valid   (s2_valid_out),  // 输出 192k/176.4k 均匀脉冲
        .dac_data    (s2_data_out)
    );

    // ------------------------------------------
    // [Stage 3] 4x -> 8x (多模式通用架构)
    // ------------------------------------------
    wire stage3_mode_sel = (sys_mode == 2'b10) ? 1'b1 : 1'b0; // 128x 模式下切为 Comp(1)

    Stage3_MultiMode_FIR #(
        .DATA_W(DATA_W)
    ) stage3_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .sys_fs_sel  (sys_fs_sel),
        .mode_sel    (stage3_mode_sel), // 0: Flat, 1: Comp
        .valid_in    (s2_valid_out),    // 接收 Stage 2 的均匀脉冲
        .data_in     (s2_data_out),
        .valid_out   (s3_valid_out),    // 输出 384k/352.8k 均匀脉冲
        .data_out    (s3_data_out)
    );

    // ------------------------------------------
    // [Stage 4] 8x -> 128x (CIC 滤波器 - x16 插值)
    // ------------------------------------------
Stage4_CIC_x16 #(
        .IN_WIDTH(DATA_W),
        .STAGES(4),
        .R(16),
        .CLK_FREQ(100_000_000)
    ) stage4_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .sys_fs_sel (sys_fs_sel),       // 接入系统的频系选择信号
        .din_valid  (s3_valid_out),     
        .din        (s3_data_out),
        .dout_valid (s4_valid_out),     
        .dout       (s4_data_out)
    );

    // ==========================================
    // 4. 输出路由 (MUX)
    // ==========================================
    always @(*) begin
        case (sys_mode)
            2'b00: begin // 4x 模式：直接输出 Stage 2 的数据 (192kHz/176.4kHz)
                final_valid = s2_valid_out;
                final_data  = s2_data_out;
            end
            2'b01: begin // 8x 模式：输出 Stage 3 的 Flat 数据 (384kHz/352.8kHz)
                final_valid = s3_valid_out;
                final_data  = s3_data_out;
            end
            2'b10: begin // 128x 模式：输出 Stage 4 的 CIC 数据 (6.144MHz/5.6448MHz)
                final_valid = s4_valid_out; 
                final_data  = s4_data_out;
            end
            default: begin
                final_valid = 1'b0;
                final_data  = 24'd0;
            end
        endcase
    end

endmodule