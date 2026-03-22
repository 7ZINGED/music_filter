`timescale 1ns / 1ps

module Stage4_CIC_x16 #(
    parameter IN_WIDTH  = 24,
    parameter STAGES    = 4,
    parameter R         = 16,
    parameter CLK_FREQ  = 100_000_000 // 系统时钟频率
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // 频系选择，用于计算正确的 128Fs 读取速率
    input  wire                  sys_fs_sel, // 0: 48kHz系(6.144MHz), 1: 44.1kHz系(5.6448MHz)
    
    // 从 Stage 3 接收 (8x 采样率, 比如 384kHz)
    input  wire                  din_valid,
    input  wire signed [IN_WIDTH-1:0] din,
    
    // 输出到后端 DAC (128x 均匀采样率)
    output reg                   dout_valid,
    output reg signed [IN_WIDTH-1:0] dout
);

    // 计算内部所需位宽: 24 + 16 = 40 bits
    localparam ACC_WIDTH = IN_WIDTH + 16; 

    // ==========================================
    // 1. 梳状滤波器部分 (Comb Section)
    // ==========================================
    reg signed [ACC_WIDTH-1:0] din_ext;
    reg signed [ACC_WIDTH-1:0] comb_d [0:STAGES-1];
    reg signed [ACC_WIDTH-1:0] comb_c [0:STAGES-1];
    reg din_valid_d1;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            din_ext <= 0;
            din_valid_d1 <= 0;
            for (i = 0; i < STAGES; i = i + 1) begin
                comb_d[i] <= 0;
                comb_c[i] <= 0;
            end
        end else begin
            din_valid_d1 <= din_valid;
            
            if (din_valid) begin
                din_ext <= $signed(din);
                
                comb_d[0] <= din_ext;
                comb_c[0] <= din_ext - comb_d[0];
                
                comb_d[1] <= comb_c[0];
                comb_c[1] <= comb_c[0] - comb_d[1];
                
                comb_d[2] <= comb_c[1];
                comb_c[2] <= comb_c[1] - comb_d[2];
                
                comb_d[3] <= comb_c[2];
                comb_c[3] <= comb_c[2] - comb_d[3];
            end
        end
    end

  // ==========================================
    // 2. 插零与积分器状态机 (Burst Output) [已彻底修复]
    // ==========================================
    reg [4:0] count;
    reg       processing;
    reg signed [ACC_WIDTH-1:0] intg [0:STAGES-1];
    
    wire signed [ACC_WIDTH-1:0] stuffer_out = (count == 0) ? comb_c[STAGES-1] : {ACC_WIDTH{1'b0}};
    
    // ? 核心修复：使用组合逻辑构建无延迟的级联积分链
    wire signed [ACC_WIDTH-1:0] intg0_next = intg[0] + stuffer_out;
    wire signed [ACC_WIDTH-1:0] intg1_next = intg[1] + intg0_next;
    wire signed [ACC_WIDTH-1:0] intg2_next = intg[2] + intg1_next;
    wire signed [ACC_WIDTH-1:0] intg3_next = intg[3] + intg2_next;
    
    // 积分器的突发输出信号 (写 FIFO 用)
    reg        burst_valid;
    // 使用积分器 3 的最新状态输出，并进行 >> 16 归一化截位
    wire signed [IN_WIDTH-1:0] burst_data = intg[STAGES-1][ACC_WIDTH-1 : ACC_WIDTH-IN_WIDTH];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            processing <= 0;
            burst_valid <= 0;
            for (i = 0; i < STAGES; i = i + 1) begin
                intg[i] <= 0;
            end
        end else begin
            if (din_valid_d1) begin
                processing <= 1;
                count <= 0;
            end
            
            if (processing) begin
                if (count < R) begin
                    // ? 核心修复：将计算好的 Next 值同步打入寄存器
                    intg[0] <= intg0_next;
                    intg[1] <= intg1_next;
                    intg[2] <= intg2_next;
                    intg[3] <= intg3_next;
                    
                    burst_valid <= 1;
                    count <= count + 1;
                end else begin
                    processing <= 0;
                    burst_valid <= 0;
                end
            end else begin
                burst_valid <= 0;
            end
        end
    end
    // ==========================================
    // 3. 128Fs 均匀速率脉冲发生器
    // ==========================================
    // 对于 48kHz系: 128Fs = 6.144 MHz -> 分频比 = 100M / 6.144M ≈ 16.276
    // 对于 44.1kHz系: 128Fs = 5.6448 MHz -> 分频比 = 100M / 5.6448M ≈ 17.715
    // 使用小数分频 (相位累加器) 来生成精准脉冲
    
    reg [31:0] phase_acc;
    reg        rate_128fs_pulse;
    
    // 累加步进计算: (Target_Freq / CLK_FREQ) * 2^32
    localparam STEP_48K_128FS = 32'd263882790; // (6.144M / 100M) * 2^32
    localparam STEP_44K_128FS = 32'd242442436; // (5.6448M / 100M) * 2^32
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 0;
            rate_128fs_pulse <= 0;
        end else begin
            rate_128fs_pulse <= 0; // 默认拉低
            if (sys_fs_sel == 1'b0) begin
                {rate_128fs_pulse, phase_acc} <= phase_acc + STEP_48K_128FS;
            end else begin
                {rate_128fs_pulse, phase_acc} <= phase_acc + STEP_44K_128FS;
            end
        end
    end

    // ==========================================
    // 4. 简易同步 FIFO (深度 32) 与输出逻辑
    // ==========================================
    reg signed [IN_WIDTH-1:0] fifo [0:31];
    reg [4:0] wr_ptr;
    reg [4:0] rd_ptr;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            dout_valid <= 0;
            dout <= 0;
        end else begin
            // 写操作：将积分器的 Burst 数据存入 FIFO
            if (burst_valid) begin
                fifo[wr_ptr] <= burst_data;
                wr_ptr <= wr_ptr + 1;
            end
            
            // 读操作：在 128Fs 均匀脉冲到来时取出数据
            if (rate_128fs_pulse && (wr_ptr != rd_ptr)) begin
                dout <= fifo[rd_ptr];
                dout_valid <= 1;
                rd_ptr <= rd_ptr + 1;
            end else begin
                dout_valid <= 0;
            end
        end
    end

endmodule