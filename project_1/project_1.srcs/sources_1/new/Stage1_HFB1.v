`timescale 1ns / 1ps

module Stage1_HFB1 #(
    parameter DATA_W = 24
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 sys_fs_sel, // ? 新增：频系选择信号 (0:48k, 1:44.1k)
    input  wire                 valid_in,
    input  wire signed [DATA_W-1:0] data_in,
    
    output reg                  valid_out,
    output reg signed [DATA_W-1:0] data_out
);

    // ? 统一架构：87抽头插值，低速延迟线需要 44 级 (0 到 43)
    reg signed [DATA_W-1:0] delay_line [0:43];
    integer i;

    reg [1:0] state;
    localparam IDLE = 2'd0, MAC = 2'd1;

    reg [4:0] mac_cnt; // 支持 0~21 的计数

    // ? 纯组合逻辑：双频系系数查找表
    reg signed [23:0] internal_coeff;
    always @(*) begin
        // ==========================================
        // ?? 请在这里粘贴刚才 MATLAB 生成的 if-else 代码块！
        // ==========================================
         if (sys_fs_sel == 1'b0) begin // === 48kHz 频系 ===
            case(mac_cnt)
                5'd0: internal_coeff = 24'h000000;
                5'd1: internal_coeff = 24'h000000;
                5'd2: internal_coeff = 24'h000000;
                5'd3: internal_coeff = 24'h000000;
                5'd4: internal_coeff = 24'h000000;
                5'd5: internal_coeff = 24'h000000;
                5'd6: internal_coeff = 24'h000000;
                5'd7: internal_coeff = 24'h000000;
                5'd8: internal_coeff = 24'h000000;
                5'd9: internal_coeff = 24'h001416;
                5'd10: internal_coeff = 24'hFFD226;
                5'd11: internal_coeff = 24'h005EB4;
                5'd12: internal_coeff = 24'hFF5222;
                5'd13: internal_coeff = 24'h0126C1;
                5'd14: internal_coeff = 24'hFE2813;
                5'd15: internal_coeff = 24'h02D532;
                5'd16: internal_coeff = 24'hFBC366;
                5'd17: internal_coeff = 24'h0642D1;
                5'd18: internal_coeff = 24'hF6AA43;
                5'd19: internal_coeff = 24'h0E92F6;
                5'd20: internal_coeff = 24'hE5E748;
                5'd21: internal_coeff = 24'h512067;
                default: internal_coeff = 24'd0;
            endcase
        end else begin // === 44.1kHz 频系 ===
            case(mac_cnt)
                5'd0: internal_coeff = 24'hFFEF34;
                5'd1: internal_coeff = 24'h0014FC;
                5'd2: internal_coeff = 24'hFFDE67;
                5'd3: internal_coeff = 24'h0032C2;
                5'd4: internal_coeff = 24'hFFB68B;
                5'd5: internal_coeff = 24'h0066D5;
                5'd6: internal_coeff = 24'hFF73D6;
                5'd7: internal_coeff = 24'h00BAEF;
                5'd8: internal_coeff = 24'hFF0B27;
                5'd9: internal_coeff = 24'h013BFA;
                5'd10: internal_coeff = 24'hFE6D23;
                5'd11: internal_coeff = 24'h01FCD7;
                5'd12: internal_coeff = 24'hFD819F;
                5'd13: internal_coeff = 24'h031DF0;
                5'd14: internal_coeff = 24'hFC1AC1;
                5'd15: internal_coeff = 24'h04E3F5;
                5'd16: internal_coeff = 24'hF9CAD5;
                5'd17: internal_coeff = 24'h080C45;
                5'd18: internal_coeff = 24'hF52832;
                5'd19: internal_coeff = 24'h0FB80F;
                5'd20: internal_coeff = 24'hE53026;
                5'd21: internal_coeff = 24'h515EB2;
                default: internal_coeff = 24'd0;
            endcase
        end
    end

    // 完美对齐的 DSP 流水线：首尾折叠预加 -> 乘法 
    wire signed [DATA_W:0] pre_adder = delay_line[mac_cnt] + delay_line[43 - mac_cnt];
    wire signed [48:0]     mult_res  = pre_adder * internal_coeff; 

    reg signed [48:0] acc_reg;  

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i=0; i<=43; i=i+1) delay_line[i] <= 0;
            valid_out <= 0;
            data_out  <= 0;
            state     <= IDLE;
            mac_cnt   <= 0;
            acc_reg   <= 0;
        end else begin
            valid_out <= 0;
            
            case (state)
                IDLE: begin
                    if (valid_in) begin
                        // 低速节拍：更新 44 级延迟线
                        for(i=43; i>0; i=i-1) begin
                            delay_line[i] <= delay_line[i-1];
                        end
                        delay_line[0] <= data_in;
                        
                        // 阶段 1：多相奇数相 (中心点)
                        // 87抽头的中心点位于延迟线的正中央：索引 21
                        valid_out <= 1;
                        data_out  <= delay_line[21]; 
                        
                        state     <= MAC;
                        mac_cnt   <= 0;
                        acc_reg   <= 0;
                    end
                end
                
                MAC: begin
                    if (mac_cnt <= 21) begin
                        // 阶段 2：多相偶数相 (22 次乘加)
                        acc_reg <= acc_reg + mult_res;
                        mac_cnt <= mac_cnt + 1;
                    end else begin
                        // 22 次算完，输出偶数相插值点
                        valid_out <= 1;
                        data_out  <= acc_reg[46 : 23]; 
                        state     <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule