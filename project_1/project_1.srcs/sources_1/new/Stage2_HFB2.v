`timescale 1ns / 1ps

module Stage2_HFB2 #(
    parameter DATA_W = 24,
    parameter CLK_FREQ = 100_000_000
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 sys_fs_sel,   // 0: 48k系, 1: 44.1k系
    input  wire                 valid_in,     // 来自 Stage 1 的突发有效信号
    input  wire signed [DATA_W-1:0] data_in,
    
    output reg                  dac_valid,    // 给 DAC 的均匀脉冲 (192k/176.4k)
    output reg signed [DATA_W-1:0] dac_data      // 给 DAC 的均匀数据
);

    // ==========================================
    // 1. 参数与寄存器定义 (针对 19 抽头半带优化)
    // ==========================================
    localparam TAPS = 19;
    localparam DELAY_DEPTH = 10;   // 19抽头对应 10 级低速延迟线
    localparam CENTER_IDX  = 4;    // 中心点位置 (对应 87 抽头架构中的索引 21)

    reg signed [DATA_W-1:0] delay_line [0:DELAY_DEPTH-1];
    
    reg [1:0] state;
    localparam IDLE = 2'd0, MAC = 2'd1;

    reg [4:0] mac_cnt; 
    reg signed [48:0] acc_reg;
    reg signed [23:0] internal_coeff;

    // ==========================================
    // 2. 纯组合逻辑：双频系硬编码系数表 (5 对对称系数)
    // ==========================================
    always @(*) begin
        if (sys_fs_sel == 1'b0) begin // 48k 频系
            case(mac_cnt)
                5'd0: internal_coeff = 24'h007F02;
                5'd1: internal_coeff = 24'hFD8D79;
                5'd2: internal_coeff = 24'h07BBA7;
                5'd3: internal_coeff = 24'hEB0780;
                5'd4: internal_coeff = 24'h4F3761;
                default: internal_coeff = 24'd0;
            endcase
        end else begin // 44.1k 频系
            case(mac_cnt)
                5'd0: internal_coeff = 24'h006287;
                5'd1: internal_coeff = 24'hFDDCF7;
                5'd2: internal_coeff = 24'h073EF5;
                5'd3: internal_coeff = 24'hEB7F92;
                5'd4: internal_coeff = 24'h4F0547;
                default: internal_coeff = 24'd0;
            endcase
        end
    end

    // 完美对齐的 DSP 流水线：对称预加 -> 乘法
    wire signed [DATA_W:0] pre_adder = delay_line[mac_cnt] + delay_line[(DELAY_DEPTH-1) - mac_cnt];
    wire signed [48:0]     mult_res  = pre_adder * internal_coeff;

    // 内部计算完成标志及寄存器
    reg signed [DATA_W-1:0] calc_res_reg;
    reg                     calc_done_pulse;

    // ==========================================
    // 3. 多相插值计算状态机 (参考 Stage 1 结构)
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(integer k=0; k<DELAY_DEPTH; k=k+1) delay_line[k] <= 0;
            state <= IDLE;
            mac_cnt <= 0;
            acc_reg <= 0;
            calc_done_pulse <= 0;
            calc_res_reg <= 0;
        end else begin
            calc_done_pulse <= 0;
            case (state)
                IDLE: begin
                    if (valid_in) begin
                        // 更新延迟线
                        for(integer j=DELAY_DEPTH-1; j>0; j=j-1) begin
                            delay_line[j] <= delay_line[j-1];
                        end
                        delay_line[0] <= data_in;
                        
                        // --- 阶段 A：输出中心抽头 (奇数相) ---
                        calc_res_reg    <= delay_line[CENTER_IDX]; 
                        calc_done_pulse <= 1;  
                        
                        state   <= MAC;
                        mac_cnt <= 0;
                        acc_reg <= 0;
                    end
                end
                
                MAC: begin
                    if (mac_cnt <= 4) begin
                        // --- 阶段 B：对称 MAC 计算 (偶数相) ---
                        acc_reg <= acc_reg + mult_res;
                        mac_cnt <= mac_cnt + 1;
                    end else begin
                        // 计算完成，直接截位
                        calc_res_reg    <= acc_reg[46:23]; 
                        calc_done_pulse <= 1;  
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // ==========================================
    // 4. 8 深度 FIFO 与 DAC 速率匹配逻辑
    // ==========================================
    // 48k * 4 = 192kHz -> 100MHz / 192k ≈ 521
    // 44.1k * 4 = 176.4kHz -> 100MHz / 176.4k ≈ 567
    wire [15:0] dac_period = (sys_fs_sel == 1'b0) ? 16'd520 : 16'd566;
    reg  [15:0] dac_cnt;
    
    reg signed [DATA_W-1:0] fifo_mem [0:7]; 
    reg [3:0] fifo_ptr_w, fifo_ptr_r; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_ptr_w <= 0;
            fifo_ptr_r <= 0;
            dac_cnt    <= 0;
            dac_valid  <= 0;
            dac_data   <= 0;
        end else begin
            // --- 写入逻辑 (Burst 写入) ---
            if (calc_done_pulse) begin
                fifo_mem[fifo_ptr_w[2:0]] <= calc_res_reg;
                fifo_ptr_w <= fifo_ptr_w + 1;
            end

            // --- 均匀读取逻辑 (DAC 定时拉取) ---
            dac_valid <= 0;
            if (dac_cnt >= dac_period) begin
                dac_cnt <= 0;
                if (fifo_ptr_r != fifo_ptr_w) begin
                    dac_data  <= fifo_mem[fifo_ptr_r[2:0]];
                    dac_valid <= 1;
                    fifo_ptr_r <= fifo_ptr_r + 1;
                end
            end else begin
                dac_cnt <= dac_cnt + 1;
            end
        end
    end

endmodule