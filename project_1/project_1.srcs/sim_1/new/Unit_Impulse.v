`timescale 1ns / 1ps

module Unit_Impulse();

    // ==========================================
    // 1. 信号声明与参数定义
    // ==========================================
    parameter DATA_W = 24;

    reg                 clk;
    reg                 rst_n;
    reg                 sys_fs_sel;
    reg  [1:0]          sys_mode;
    reg                 i2s_lrclk;
    reg  signed [DATA_W-1:0] audio_in;

    wire                final_valid;
    wire signed [DATA_W-1:0] final_data;

    // ==========================================
    // 2. 例化顶层模块 (DUT)
    // ==========================================
    Audio_Upsampler_Top #(
        .DATA_W(DATA_W)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sys_fs_sel  (sys_fs_sel),
        .sys_mode    (sys_mode), 
        .i2s_lrclk   (i2s_lrclk),
        .audio_in    (audio_in),
        .final_valid (final_valid),
        .final_data  (final_data)
    );

    // ==========================================
    // 3. 时钟生成 (100MHz 主频)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

// ==========================================
    // 4. 冲激信号发生器 (Impulse Generator)
    // ==========================================
    integer sample_cnt = 0;
    real    current_fs = 48000.0;
    integer lrclk_half_period = 10417; 

    initial begin
        i2s_lrclk = 0;
        audio_in  = 0;
        #100; 
        
        forever begin
            i2s_lrclk = 0;
            #(lrclk_half_period);
            
            i2s_lrclk = 1;
            
            // 产生冲激：第 10 个采样点给最大幅值，其余全为 0
            if (sample_cnt == 10) begin
                audio_in = 24'h700FFF; // 24-bit 最大正值
            end else begin
                audio_in = 24'd0;
            end
            sample_cnt = sample_cnt + 1;
            
            #(lrclk_half_period);
        end
    end
// ==========================================
// 5. 8 类探针信号导出逻辑
// ==========================================
integer f[1:8];
reg [3:0] active_file; 

initial begin
    f[1] = $fopen("data_48k_s2_4x.txt",      "w"); // Stage 2 输出
    f[2] = $fopen("data_48k_s3_8x_flat.txt", "w"); // Stage 3 直出 (8x)
    f[3] = $fopen("data_48k_s3_8x_comp.txt", "w"); // Stage 3 补偿 (给Stage 4的输入)
    f[4] = $fopen("data_48k_s4_128x.txt",    "w"); // Stage 4 最终输出
    
    f[5] = $fopen("data_44k_s2_4x.txt",      "w");
    f[6] = $fopen("data_44k_s3_8x_flat.txt", "w");
    f[7] = $fopen("data_44k_s3_8x_comp.txt", "w");
    f[8] = $fopen("data_44k_s4_128x.txt",    "w");
end

always @(posedge clk) begin
    if (final_valid && rst_n) begin
        if (active_file >= 1 && active_file <= 8)
            $fdisplay(f[active_file], "%d", final_data);
    end
end

// ==========================================
// 6. 自动化测试流程：8 个信号精准捕获
// ==========================================
initial begin
    active_file = 0; rst_n = 0; sys_fs_sel = 0; audio_in = 0; #100;

    // --- [阶段 A: 48kHz 频系] ---
    sys_fs_sel = 0; lrclk_half_period = 10417;

    // A1: Stage 2 输出 (4x)
    sample_cnt = 0; sys_mode = 2'b00; active_file = 1; rst_n = 1; #20000000; rst_n = 0; #500;
    
    // A2: Stage 3 直出 (8x Flat)
    sample_cnt = 0; sys_mode = 2'b01; active_file = 2; rst_n = 1; 
    force dut.stage3_inst.mode_sel = 1'b0; #40000000; release dut.stage3_inst.mode_sel; rst_n = 0; #500;
    
    // A3: Stage 3 补偿 (8x Comp - 进入 Stage 4 的前级信号)
    sample_cnt = 0; sys_mode = 2'b01; active_file = 3; rst_n = 1;
    force dut.stage3_inst.mode_sel = 1'b1; #40000000; release dut.stage3_inst.mode_sel; rst_n = 0; #500;
    
    // A4: Stage 4 输出 (128x 最终结果)
    sample_cnt = 0; sys_mode = 2'b10; active_file = 4; rst_n = 1;
     #10000000000; 
     rst_n = 0; #500;

// --- [阶段 B: 44.1kHz 频系] ---
    sys_fs_sel = 1; lrclk_half_period = 11338;

    // B1: Stage 2 输出 (4x) - 统一增加一个 0
    sample_cnt = 0; sys_mode = 2'b00; active_file = 5; rst_n = 1; 
    #20000000; // 确保时间足够（两千万）
    rst_n = 0; #5000; // 增加复位缓冲时间

    // B2: Stage 3 直出 (8x Flat)
    sample_cnt = 0; sys_mode = 2'b01; active_file = 6; rst_n = 1; 
    force dut.stage3_inst.mode_sel = 1'b0; 
    #40000000; 
    release dut.stage3_inst.mode_sel; rst_n = 0; #5000;

    // B3: Stage 3 补偿
    sample_cnt = 0; sys_mode = 2'b01; active_file = 7; rst_n = 1;
    force dut.stage3_inst.mode_sel = 1'b1; 
    #40000000; 
    release dut.stage3_inst.mode_sel; rst_n = 0; #5000;

    // B4: Stage 4 输出 (128x)
    sample_cnt = 0; sys_mode = 2'b10; active_file = 8; rst_n = 1; 
    #10000000000; // 128x 模式一定要给足时间
    rst_n = 0; #5000;

    $display("8 类探针信号提取完成！正在停止仿真...");
    $stop;
end
endmodule