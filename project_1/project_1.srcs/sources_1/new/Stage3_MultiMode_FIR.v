`timescale 1ns / 1ps

module Stage3_MultiMode_FIR #(
    parameter DATA_W = 24
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 sys_fs_sel,   // 0: 48k系, 1: 44.1k系
    input  wire                 mode_sel,     // 0: Flat (半带), 1: Comp (补偿)
    input  wire                 valid_in,     // 来自 Stage 2
    input  wire signed [DATA_W-1:0] data_in,
    
    output reg                  valid_out,    // 给 Stage 4 的均匀脉冲 (384k/352.8k)
    output reg signed [DATA_W-1:0] data_out   // 均匀音频数据
);

    // 内部计算位宽设定
    localparam ACC_W = 49;
    localparam TAPS_PER_PHASE = 16; // 每相最大 16 抽头

    // ==========================================================
    // 轨道 A: Flat 半带滤波器 (mode_sel == 0)
    // ==========================================================
    reg signed [DATA_W-1:0] delay_flat [0:15];
    reg [3:0] mac_cnt_flat;
    reg [1:0] state_flat;
    reg signed [ACC_W-1:0] acc_flat;
    reg signed [23:0] coeff_flat;
    
    wire phase_sel_flat = (state_flat == 2'd2); // 1: Phase0, 2: Phase1

    // [请将 MATLAB 生成的 Stage3_Flat_FIR LUT 粘贴在此处]
// [Flat 模式系数 LUT]
    always @(*) begin
        case ({sys_fs_sel, phase_sel_flat})
            2'b00: case(mac_cnt_flat) // 48k, Phase 0
                4'd0: coeff_flat = 24'h000000;
                4'd1: coeff_flat = 24'h004371;
                4'd2: coeff_flat = 24'hFF0AD4;
                4'd3: coeff_flat = 24'h02836D;
                4'd4: coeff_flat = 24'hFA7502;
                4'd5: coeff_flat = 24'h0B4832;
                4'd6: coeff_flat = 24'hE82772;
                4'd7: coeff_flat = 24'h504E61;
                4'd8: coeff_flat = 24'h504E61;
                4'd9: coeff_flat = 24'hE82772;
                4'd10: coeff_flat = 24'h0B4832;
                4'd11: coeff_flat = 24'hFA7502;
                4'd12: coeff_flat = 24'h02836D;
                4'd13: coeff_flat = 24'hFF0AD4;
                4'd14: coeff_flat = 24'h004371;
                4'd15: coeff_flat = 24'h000000;
                default: coeff_flat = 24'd0; endcase
            2'b01: case(mac_cnt_flat) // 48k, Phase 1
                4'd0: coeff_flat = 24'h000000;
                4'd1: coeff_flat = 24'h000000;
                4'd2: coeff_flat = 24'h000000;
                4'd3: coeff_flat = 24'h000000;
                4'd4: coeff_flat = 24'h000000;
                4'd5: coeff_flat = 24'h000000;
                4'd6: coeff_flat = 24'h000000;
                4'd7: coeff_flat = 24'h7FF68B;
                4'd8: coeff_flat = 24'h000000;
                4'd9: coeff_flat = 24'h000000;
                4'd10: coeff_flat = 24'h000000;
                4'd11: coeff_flat = 24'h000000;
                4'd12: coeff_flat = 24'h000000;
                4'd13: coeff_flat = 24'h000000;
                4'd14: coeff_flat = 24'h000000;
                4'd15: coeff_flat = 24'h000000;
                default: coeff_flat = 24'd0; endcase
            2'b10: case(mac_cnt_flat) // 44.1k, Phase 0
                4'd0: coeff_flat = 24'hFFD7E2;
                4'd1: coeff_flat = 24'h00907B;
                4'd2: coeff_flat = 24'hFE8620;
                4'd3: coeff_flat = 24'h0339F7;
                4'd4: coeff_flat = 24'hF9A3D2;
                4'd5: coeff_flat = 24'h0C0DC7;
                4'd6: coeff_flat = 24'hE797EA;
                4'd7: coeff_flat = 24'h508B22;
                4'd8: coeff_flat = 24'h508B22;
                4'd9: coeff_flat = 24'hE797EA;
                4'd10: coeff_flat = 24'h0C0DC7;
                4'd11: coeff_flat = 24'hF9A3D2;
                4'd12: coeff_flat = 24'h0339F7;
                4'd13: coeff_flat = 24'hFE8620;
                4'd14: coeff_flat = 24'h00907B;
                4'd15: coeff_flat = 24'hFFD7E2;
                default: coeff_flat = 24'd0; endcase
            2'b11: case(mac_cnt_flat) // 44.1k, Phase 1
                4'd0: coeff_flat = 24'h000000;
                4'd1: coeff_flat = 24'h000000;
                4'd2: coeff_flat = 24'h000000;
                4'd3: coeff_flat = 24'h000000;
                4'd4: coeff_flat = 24'h000000;
                4'd5: coeff_flat = 24'h000000;
                4'd6: coeff_flat = 24'h000000;
                4'd7: coeff_flat = 24'h7FFFFF;
                4'd8: coeff_flat = 24'h000000;
                4'd9: coeff_flat = 24'h000000;
                4'd10: coeff_flat = 24'h000000;
                4'd11: coeff_flat = 24'h000000;
                4'd12: coeff_flat = 24'h000000;
                4'd13: coeff_flat = 24'h000000;
                4'd14: coeff_flat = 24'h000000;
                4'd15: coeff_flat = 24'h000000;
                default: coeff_flat = 24'd0; endcase
            default: coeff_flat = 24'd0;
        endcase
    end
            // (粘贴 Flat 系数)
    wire signed [ACC_W-1:0] mult_flat = delay_flat[mac_cnt_flat] * coeff_flat;
    reg signed [DATA_W-1:0] res_flat;
    reg done_flat;

    // Flat 独立状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(integer i=0; i<16; i=i+1) delay_flat[i] <= 0;
            state_flat <= 0; mac_cnt_flat <= 0; acc_flat <= 0; done_flat <= 0; res_flat <= 0;
        end else begin
            done_flat <= 0;
            case (state_flat)
                0: if (valid_in) begin
                    for(integer i=15; i>0; i=i-1) delay_flat[i] <= delay_flat[i-1];
                    delay_flat[0] <= data_in;
                    state_flat <= 1; mac_cnt_flat <= 0; acc_flat <= 0;
                end
                1: begin // Phase 0
                    acc_flat <= acc_flat + mult_flat;
                    if (mac_cnt_flat == 15) begin
                        res_flat <= (acc_flat + mult_flat + 49'h400000) >>> 23; // 四舍五入截位
                        done_flat <= 1; state_flat <= 2; mac_cnt_flat <= 0; acc_flat <= 0;
                    end else mac_cnt_flat <= mac_cnt_flat + 1;
                end
                2: begin // Phase 1
                    acc_flat <= acc_flat + mult_flat;
                    if (mac_cnt_flat == 15) begin
                        res_flat <= (acc_flat + mult_flat + 49'h400000) >>> 23;
                        done_flat <= 1; state_flat <= 0;
                    end else mac_cnt_flat <= mac_cnt_flat + 1;
                end
            endcase
        end
    end

    // ==========================================================
    // 轨道 B: Comp 通用滤波器 (mode_sel == 1)
    // ==========================================================
    reg signed [DATA_W-1:0] delay_comp [0:15];
    reg [3:0] mac_cnt_comp;
    reg [1:0] state_comp;
    reg signed [ACC_W-1:0] acc_comp;
    reg signed [23:0] coeff_comp;
    
    wire phase_sel_comp = (state_comp == 2'd2); // 1: Phase0, 2: Phase1

    // [请将 MATLAB 生成的 Stage3_Comp_FIR LUT 粘贴在此处]
// [Comp 模式系数 LUT]
    always @(*) begin
        case ({sys_fs_sel, phase_sel_comp})
            2'b00: case(mac_cnt_comp) // 48k, Phase 0
                4'd0: coeff_comp = 24'hFB7196;
                4'd1: coeff_comp = 24'h0AC977;
                4'd2: coeff_comp = 24'h738F54;
                4'd3: coeff_comp = 24'h0AC977;
                4'd4: coeff_comp = 24'hFB7196;
                4'd5: coeff_comp = 24'h000000;
                4'd6: coeff_comp = 24'h000000;
                4'd7: coeff_comp = 24'h000000;
                4'd8: coeff_comp = 24'h000000;
                4'd9: coeff_comp = 24'h000000;
                4'd10: coeff_comp = 24'h000000;
                4'd11: coeff_comp = 24'h000000;
                4'd12: coeff_comp = 24'h000000;
                4'd13: coeff_comp = 24'h000000;
                4'd14: coeff_comp = 24'h000000;
                4'd15: coeff_comp = 24'h000000;
                default: coeff_comp = 24'd0; endcase
            2'b01: case(mac_cnt_comp) // 48k, Phase 1
                4'd0: coeff_comp = 24'hF46108;
                4'd1: coeff_comp = 24'h4B9C41;
                4'd2: coeff_comp = 24'h4B9C41;
                4'd3: coeff_comp = 24'hF46108;
                4'd4: coeff_comp = 24'h000000;
                4'd5: coeff_comp = 24'h000000;
                4'd6: coeff_comp = 24'h000000;
                4'd7: coeff_comp = 24'h000000;
                4'd8: coeff_comp = 24'h000000;
                4'd9: coeff_comp = 24'h000000;
                4'd10: coeff_comp = 24'h000000;
                4'd11: coeff_comp = 24'h000000;
                4'd12: coeff_comp = 24'h000000;
                4'd13: coeff_comp = 24'h000000;
                4'd14: coeff_comp = 24'h000000;
                4'd15: coeff_comp = 24'h000000;
                default: coeff_comp = 24'd0; endcase
            2'b10: case(mac_cnt_comp) // 44.1k, Phase 0
                4'd0: coeff_comp = 24'h0055D4;
                4'd1: coeff_comp = 24'hF36D8D;
                4'd2: coeff_comp = 24'h4C4169;
                4'd3: coeff_comp = 24'h4C4169;
                4'd4: coeff_comp = 24'hF36D8D;
                4'd5: coeff_comp = 24'h0055D4;
                4'd6: coeff_comp = 24'h000000;
                4'd7: coeff_comp = 24'h000000;
                4'd8: coeff_comp = 24'h000000;
                4'd9: coeff_comp = 24'h000000;
                4'd10: coeff_comp = 24'h000000;
                4'd11: coeff_comp = 24'h000000;
                4'd12: coeff_comp = 24'h000000;
                4'd13: coeff_comp = 24'h000000;
                4'd14: coeff_comp = 24'h000000;
                4'd15: coeff_comp = 24'h000000;
                default: coeff_comp = 24'd0; endcase
            2'b11: case(mac_cnt_comp) // 44.1k, Phase 1
                4'd0: coeff_comp = 24'hFB9078;
                4'd1: coeff_comp = 24'h09D219;
                4'd2: coeff_comp = 24'h753148;
                4'd3: coeff_comp = 24'h09D219;
                4'd4: coeff_comp = 24'hFB9078;
                4'd5: coeff_comp = 24'h000000;
                4'd6: coeff_comp = 24'h000000;
                4'd7: coeff_comp = 24'h000000;
                4'd8: coeff_comp = 24'h000000;
                4'd9: coeff_comp = 24'h000000;
                4'd10: coeff_comp = 24'h000000;
                4'd11: coeff_comp = 24'h000000;
                4'd12: coeff_comp = 24'h000000;
                4'd13: coeff_comp = 24'h000000;
                4'd14: coeff_comp = 24'h000000;
                4'd15: coeff_comp = 24'h000000;
                default: coeff_comp = 24'd0; endcase
            default: coeff_comp = 24'd0;
        endcase
    end
     wire signed [ACC_W-1:0] mult_comp = delay_comp[mac_cnt_comp] * coeff_comp;
    reg signed [DATA_W-1:0] res_comp;
    reg done_comp;

    // Comp 独立状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(integer i=0; i<16; i=i+1) delay_comp[i] <= 0;
            state_comp <= 0; mac_cnt_comp <= 0; acc_comp <= 0; done_comp <= 0; res_comp <= 0;
        end else begin
            done_comp <= 0;
            case (state_comp)
                0: if (valid_in) begin
                    for(integer i=15; i>0; i=i-1) delay_comp[i] <= delay_comp[i-1];
                    delay_comp[0] <= data_in;
                    state_comp <= 1; mac_cnt_comp <= 0; acc_comp <= 0;
                end
                1: begin // Phase 0
                    acc_comp <= acc_comp + mult_comp;
                    if (mac_cnt_comp == 15) begin
                        res_comp <= (acc_comp + mult_comp + 49'h400000) >>> 23; // 四舍五入截位
                        done_comp <= 1; state_comp <= 2; mac_cnt_comp <= 0; acc_comp <= 0;
                    end else mac_cnt_comp <= mac_cnt_comp + 1;
                end
                2: begin // Phase 1
                    acc_comp <= acc_comp + mult_comp;
                    if (mac_cnt_comp == 15) begin
                        res_comp <= (acc_comp + mult_comp + 49'h400000) >>> 23;
                        done_comp <= 1; state_comp <= 0;
                    end else mac_cnt_comp <= mac_cnt_comp + 1;
                end
            endcase
        end
    end

    // ==========================================================
    // 交叉选择 (MUX) 与 共享 FIFO 节拍器
    // ==========================================================
    // 动态选择当前模式的计算结果打入 FIFO
    wire select_done = (mode_sel == 1'b0) ? done_flat : done_comp;
    wire signed [DATA_W-1:0] select_res = (mode_sel == 1'b0) ? res_flat : res_comp;

    // 48k * 8 = 384kHz -> 100MHz / 384k ≈ 260
    // 44.1k * 8 = 352.8kHz -> 100MHz / 352.8k ≈ 283
    wire [15:0] dac_period = (sys_fs_sel == 1'b0) ? 16'd260 : 16'd283;
    reg  [15:0] dac_cnt;
    
    reg signed [DATA_W-1:0] fifo_mem [0:7]; 
    reg [3:0] fifo_ptr_w, fifo_ptr_r; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_ptr_w <= 0; fifo_ptr_r <= 0; dac_cnt <= 0;
            valid_out <= 0; data_out <= 0;
        end else begin
            // Burst 写入 FIFO
            if (select_done) begin
                fifo_mem[fifo_ptr_w[2:0]] <= select_res;
                fifo_ptr_w <= fifo_ptr_w + 1;
            end

            // 均匀吐出节拍
            valid_out <= 0;
            if (dac_cnt >= dac_period) begin
                dac_cnt <= 0;
                if (fifo_ptr_r != fifo_ptr_w) begin
                    data_out  <= fifo_mem[fifo_ptr_r[2:0]];
                    valid_out <= 1;
                    fifo_ptr_r <= fifo_ptr_r + 1;
                end
            end else begin
                dac_cnt <= dac_cnt + 1;
            end
        end
    end

endmodule