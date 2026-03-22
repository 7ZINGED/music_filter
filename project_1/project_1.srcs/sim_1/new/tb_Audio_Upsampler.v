`timescale 1ns / 1ps

module tb_Audio_Upsampler();

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
    // 4. 动态正弦波与 I2S 发生器 (浮点计算)
    // ==========================================
    real phase = 0.0;
    real pi = 3.14159265358979323846;
    real sine_freq = 16000.0;    // 16 kHz 正弦波 (方便在 128x 高频下观察波形平滑度)
    real amplitude = 8000000;    // 24-bit 的适中幅度，留出余量防止 CIC 内部溢出

    real    current_fs;         
    integer lrclk_half_period;  

    initial begin
        i2s_lrclk = 0;
        audio_in  = 0;
        #100; 
        
        forever begin
            i2s_lrclk = 0;
            #(lrclk_half_period);
            
            i2s_lrclk = 1;
            // 计算当前相位的正弦值，并转换为整数作为音频输入
            audio_in = $rtoi(amplitude * $sin(phase));
            
            // 更新相位
            phase = phase + (2.0 * pi * sine_freq / current_fs);
            if (phase >= 2.0 * pi) phase = phase - 2.0 * pi;
            
            #(lrclk_half_period);
        end
    end

    // ==========================================
    // 5. 将输出数据写入 TXT 文件 (用于 MATLAB 验证)
    // ==========================================
    integer file_id;
    initial begin
        // 在仿真目录下生成 out_data.txt
        file_id = $fopen("out_data.txt", "w");
        if (file_id == 0) begin
            $display("错误：无法打开文件！");
            $finish;
        end
    end

    // 仅当 final_valid 为高时，将此时的 final_data 写入文件
    always @(posedge clk) begin
        if (final_valid && rst_n) begin
            // 写入十进制有符号数
            $fdisplay(file_id, "%d", final_data);
        end
    end

    // ==========================================
    // 6. 核心测试流程：遍历 4x, 8x, 128x 及频系切换
    // ==========================================
    initial begin
        // --- 阶段 1：48kHz 频系 + 4x 模式 (192kHz 输出) ---
        rst_n      = 0;
        sys_fs_sel = 0;          
        sys_mode   = 2'b00;      
        current_fs = 48000.0;
        lrclk_half_period = 10417; // 1/(48k*2) 秒转换为纳秒

        #100;
        rst_n = 1;
        $display("[%0t] 启动: 48kHz 系, 4x 上采样模式", $time);
        #2000000; // 运行 2ms

        // --- 阶段 2：48kHz 频系 + 8x 模式 (384kHz 输出) ---
        $display("[%0t] 切换: 48kHz 系, 8x 上采样模式", $time);
        rst_n = 0;               // 软复位清空流水线
        #100;
        sys_mode   = 2'b01;      // 8x 模式 (触发 Stage 3 Flat 模式)
        #100;
        rst_n = 1;               
        #2000000; // 运行 2ms

        // --- 阶段 3：48kHz 频系 + 128x 模式 (6.144MHz 输出) ---
        $display("[%0t] 切换: 48kHz 系, 128x 上采样模式", $time);
        rst_n = 0;               // 软复位清空流水线和 CIC 积分器
        #100;
        sys_mode   = 2'b10;      // 128x 模式 (触发 Stage 3 Comp + Stage 4 CIC)
        #100;
        rst_n = 1;               
        #2000000; // 运行 2ms

        // --- 阶段 4：动态切换到 44.1kHz 频系 + 128x 模式 (5.6448MHz 输出) ---
        $display("[%0t] 切换: 44.1kHz 系, 128x 上采样模式", $time);
        rst_n = 0;               // 频系切换建议同时复位
        #100;
        sys_fs_sel = 1;          
        current_fs = 44100.0;
        lrclk_half_period = 11338; // 1/(44.1k*2) 秒转换为纳秒
        #100;
        rst_n = 1;               
        #2000000; // 运行 2ms
        
        $display("[%0t] 测试完成！", $time);
        $fclose(file_id); // 关闭文件句柄
        $stop;
    end

endmodule