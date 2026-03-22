`timescale 1ns / 1ps

module tb_design_1_wrapper();

    // --- 接口信号 ---
    reg         clk;
    reg         s_axis_data_tvalid;
    reg [23:0]  signal1;
    wire        s_axis_data_tready;
    wire        m_axis_data_tvalid;
    wire [23:0] signal2;

    // --- 实例化顶层 ---
    design_1_wrapper dut (
        .clk                (clk),
        .m_axis_data_tvalid (m_axis_data_tvalid),
        .s_axis_data_tready (s_axis_data_tready),
        .s_axis_data_tvalid (s_axis_data_tvalid),
        .signal1            (signal1),
        .signal2            (signal2)
    );

    // 1. 生成 100MHz 系统时钟 (周期 10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // --- 正弦波生成与 48kHz 采样控制变量 ---
    real phase = 0.0;
    // 每次采样的相位增量: 2*pi * (1000Hz / 48000Hz)
    real phase_inc = 2.0 * 3.1415926535 * 16000.0 / 48000.0; 
    integer clk_cnt = 0;
    
    // 2. 初始化与全局复位等待
    initial begin
        s_axis_data_tvalid = 0;
        signal1 = 0;
        
        // 【关键点】Vivado 有 100ns 的全局复位(GSR)，必须等过去再给信号
        #200; 
        $display("系统初始化完成，开始持续送入 1000Hz 正弦波...");
    end

    // 3. 核心硬件行为级驱动逻辑 (严格遵守 AXI-Stream)
    always @(posedge clk) begin
        if ($time > 200) begin
            
            // 100MHz / 48kHz ≈ 2083 个时钟周期给一个点
            if (clk_cnt >= 2082) begin
                clk_cnt <= 0;
                
                // 计算当前相位的正弦值 (幅值设为最大值的 80% 防止溢出)
                signal1 <= $rtoi(0.8 * 8388607.0 * $sin(phase));
                
                // 拉高 valid，表示数据准备好
                s_axis_data_tvalid <= 1'b1;
                
                // 更新下一次的相位
                phase = phase + phase_inc;
                if (phase >= 2.0 * 3.1415926535) begin
                    phase = phase - 2.0 * 3.1415926535;
                end
                
            end else begin
                clk_cnt <= clk_cnt + 1;
                
                // 【握手成功判断】如果在时钟上升沿，valid 和 ready 都为高，说明数据被接收了
                if (s_axis_data_tvalid == 1'b1 && s_axis_data_tready == 1'b1) begin
                    s_axis_data_tvalid <= 1'b0; // 成功后立即撤销 valid
                end
            end
            
        end
    end

endmodule