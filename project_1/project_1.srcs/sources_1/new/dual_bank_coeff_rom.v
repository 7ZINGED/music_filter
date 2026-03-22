`timescale 1ns / 1ps

module dual_bank_coeff_rom #(
    parameter DATA_WIDTH = 24,          // 系数位宽 (由 MATLAB 定点化位宽决定)
    parameter ADDR_WIDTH = 7,           // 单频系地址位宽 (例如 7 对应单频系 128 深度)
    parameter MEM_FILE   = "coeffs.mem" // 初始化系数文件路径 (包含两个频系的数据)
)(
    input  wire                         clk,       // 系统主时钟
    input  wire                         en,        // 读使能信号 (高有效)
    input  wire                         fs_sel,    // 频系选择: 0 -> 48kHz, 1 -> 44.1kHz
    input  wire [ADDR_WIDTH-1:0]        addr,      // 滤波器抽头地址 (由外部状态机提供)
    output reg signed [DATA_WIDTH-1:0]  coeff_out  // 输出的有符号定点系数
);

    // 计算 ROM 的总物理深度
    // 单频系深度 = 2^ADDR_WIDTH
    // 双频系总深度 = 2^(ADDR_WIDTH + 1)
    localparam TOTAL_DEPTH = 1 << (ADDR_WIDTH + 1);

    // 定义存储器数组
    // 使用 reg 声明二维数组，综合工具(Vivado/Quartus)会自动将其推断为 Block RAM (BRAM) 或分布式 ROM
    reg signed [DATA_WIDTH-1:0] rom_array [0:TOTAL_DEPTH-1];

    // 读取 .mem 文件初始化 ROM
    initial begin
        $readmemh(MEM_FILE, rom_array);
    end

    // 同步读取逻辑
    always @(posedge clk) begin
        if (en) begin
            // 核心技巧：地址拼接
            // 将 fs_sel 作为最高位 (MSB) 与输入地址 addr 拼接，构成实际的物理地址。
            // 当 fs_sel = 1'b0 时，访问范围是 [0 ~ (2^ADDR_WIDTH)-1] (Bank 0: 48kHz)
            // 当 fs_sel = 1'b1 时，访问范围是 [2^ADDR_WIDTH ~ (2^(ADDR_WIDTH+1))-1] (Bank 1: 44.1kHz)
            coeff_out <= rom_array[{fs_sel, addr}];
        end
    end

endmodule