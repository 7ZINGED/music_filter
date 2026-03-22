%% 高保真音频插值滤波器 - 双频系LUT生成与严格半带(HFB)架构
clear; clc; close all;

% 定义两种输入采样率体系 (对应论文中的双频系兼容设计)
Fs_array = [48000, 44100];
Fpass = 20000;
Astop_ideal = 70; % 统一阻带衰减，半带滤波器的通带纹波将自动被压制在极小值

% 创建结构体以存储 FPGA ROM 需要的两组定点系数
hw_rom_coeffs = struct();

%% 1. 核心系数生成与定点化循环
for i = 1:length(Fs_array)
    Fs_in = Fs_array(i);
    fprintf('\n==================================================\n');
    fprintf('正在生成 %d Hz 频系硬件系数...\n', Fs_in);
    
    % --- 过渡带计算 (逐级放宽，将资源消耗集中在第一级) ---
    TW1 = Fs_in - 2*Fpass;         % Stage 1: 最窄过渡带
    TW2 = 2 * Fpass;               % Stage 2: 显著放宽
    TW3 = 2 * (Fs_in - Fpass);     % Stage 3: 极其宽广
    
    % --- 滤波器对象设计 (强制半带特性，为 Verilog 砍 3/4 乘法器做准备) ---
    hfb1 = dsp.FIRHalfbandInterpolator('Specification', 'Transition width and stopband attenuation', ...
        'SampleRate', Fs_in, 'TransitionWidth', TW1, 'StopbandAttenuation', Astop_ideal);
        
    hfb2 = dsp.FIRHalfbandInterpolator('Specification', 'Transition width and stopband attenuation', ...
        'SampleRate', Fs_in * 2, 'TransitionWidth', TW2, 'StopbandAttenuation', Astop_ideal);
        
    hfb3_flat = dsp.FIRHalfbandInterpolator('Specification', 'Transition width and stopband attenuation', ...
        'SampleRate', Fs_in * 4, 'TransitionWidth', TW3, 'StopbandAttenuation', Astop_ideal);
    
    % 第四级 CIC 及其对应的专属第三级补偿器
    cic = dsp.CICInterpolator(16, 1, 4);
    hfb3_comp = dsp.CICCompensationInterpolator(cic, 'InterpolationFactor', 2, ...
        'PassbandFrequency', Fpass, 'StopbandFrequency', 4*Fs_in - Fpass, ...
        'StopbandAttenuation', Astop_ideal, 'PassbandRipple', 0.01, 'SampleRate', Fs_in * 4);
    
    % --- 24-bit 纯数学定点化 (模拟真实 FPGA 硬件行为) ---
    W_coeff = 24;
    scale = 2^(W_coeff - 1) - 1;
    q_hfb1      = round(tf(hfb1) * scale) / scale;
    q_hfb2      = round(tf(hfb2) * scale) / scale;
    q_hfb3_flat = round(tf(hfb3_flat) * scale) / scale;
    q_hfb3_comp = round(tf(hfb3_comp) * scale) / scale;
    
    % --- 存入结构体并打印抽头数 ---
    freq_str = sprintf('Fs_%dk', round(Fs_in/1000));
    hw_rom_coeffs.(freq_str).hfb1 = q_hfb1;
    hw_rom_coeffs.(freq_str).hfb2 = q_hfb2;
    hw_rom_coeffs.(freq_str).hfb3_flat = q_hfb3_flat;
    hw_rom_coeffs.(freq_str).hfb3_comp = q_hfb3_comp;
    
    fprintf('  [Stage 1] HFB1 抽头数: %d (Verilog中实际仅需约 %d 个乘法器)\n', length(q_hfb1), ceil(length(q_hfb1)/4));
    fprintf('  [Stage 2] HFB2 抽头数: %d (Verilog中实际仅需约 %d 个乘法器)\n', length(q_hfb2), ceil(length(q_hfb2)/4));
    fprintf('  [Stage 3] HFB3_flat 抽头数: %d\n', length(q_hfb3_flat));
    fprintf('  [Stage 3] HFB3_comp 抽头数: %d\n', length(q_hfb3_comp));
end

%% 2. 双频系系统级联频响验证 (48k & 44.1k)
% 定义需要验证的频系
validate_fs = [48000, 44100];
colors = {'b', 'm'}; % 48k用蓝色，44.1k用品红色区分

for k = 1:length(validate_fs)
    curr_fs = validate_fs(k);
    fs_str = sprintf('Fs_%dk', round(curr_fs/1000));
    fprintf('\n正在绘制 %d Hz 频系的硬件定点频响验证图...', curr_fs);
    
    % 从结构体中提取对应频系的定点系数
    q_h1 = hw_rom_coeffs.(fs_str).hfb1;
    q_h2 = hw_rom_coeffs.(fs_str).hfb2;
    q_h3_flat = hw_rom_coeffs.(fs_str).hfb3_flat;
    q_h3_comp = hw_rom_coeffs.(fs_str).hfb3_comp;
    
    % 构建级联滤波器对象 (硬件行为仿真)
    % 4x 模式: Stage1 -> Stage2
    hw_sys_4x = dsp.FilterCascade(dsp.FIRInterpolator(2, q_h1), ...
                                  dsp.FIRInterpolator(2, q_h2));
    
    % 8x 模式: Stage1 -> Stage2 -> Stage3(Flat)
    hw_sys_8x = dsp.FilterCascade(dsp.FIRInterpolator(2, q_h1), ...
                                  dsp.FIRInterpolator(2, q_h2), ...
                                  dsp.FIRInterpolator(2, q_h3_flat));
    
    % 128x 高倍模式: Stage1 -> Stage2 -> Stage3(Comp) -> CIC(16x)
    % 注意：CIC 在此处作为 16 倍插值器
    hw_sys_128x = dsp.FilterCascade(dsp.FIRInterpolator(2, q_h1), ...
                                    dsp.FIRInterpolator(2, q_h2), ...
                                    dsp.FIRInterpolator(2, q_h3_comp), ...
                                    cic);
        hw_sys_8x_comp = dsp.FilterCascade(dsp.FIRInterpolator(2, q_h1), ...
                                    dsp.FIRInterpolator(2, q_h2), ...
                                    dsp.FIRInterpolator(2, q_h3_comp));
                                
    % --- 绘图部分 ---
    fig_title = sprintf('%0.1fkHz 频系全模式输出通带验证 (24-bit Fixed)', curr_fs/1000);
    figure('Name', fig_title, 'NumberTitle', 'off', 'Position', [100 + k*50, 100 + k*50, 1200, 400]);
    
    % 子图 1: 4x 模式
    subplot(1,3,1);
    [H_4x, f_4x] = freqz(hw_sys_4x, 2^15, curr_fs*4);
    plot(f_4x, 20*log10(abs(H_4x)), colors{k}, 'LineWidth', 1.5);
    axis([0 20000 -0.06 0.06]); grid on; 
    title(sprintf('4x 模式 (%0.1fkHz)', curr_fs*4/1000));
    xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
    
    % 子图 2: 8x 模式
    subplot(1,3,2);
    [H_8x, f_8x] = freqz(hw_sys_8x, 2^15, curr_fs*8);
    plot(f_8x, 20*log10(abs(H_8x)), colors{k}, 'LineWidth', 1.5);
    axis([0 20000 -0.06 0.06]); grid on; 
    title(sprintf('8x 模式 (%0.1fkHz)', curr_fs*8/1000));
    xlabel('Frequency (Hz)');
    
    % 子图 3: 128x 模式 (重点关注音频带宽 20kHz 内的平坦度)
    subplot(1,3,3);
    [H_128x, f_128x] = freqz(hw_sys_128x, 2^17, curr_fs*128); 
    
    % // === 核心修正部分开始 ===
    % 🎯 核心问题：此处的仿真模型包含 CIC 的原生巨大增益 G = R^N = 16^4 = 65536 (+96dB)。
    % 而 FPGA 硬件通过截位 (>>16) 归一化到了 0dB。
    % 这里的分析必须手动除以该增益，绘图才能显示在 axis([-0.06 0.06]) 范围内。
    
    G_cic = cic.InterpolationFactor ^ cic.NumSections; % 计算 CIC 增益：16^4 = 65536
    H_normalized = H_128x / G_cic; % 进行幅度归一化
    
    % 仅截取 0-20kHz 范围进行缩放观察
    idx_20k = find(f_128x <= 20000, 1, 'last');
    
    % 使用归一化后的数据绘图
    plot(f_128x(1:idx_20k), 20*log10(abs(H_normalized(1:idx_20k))), colors{k}, 'LineWidth', 1.5); 
    % // === 核心修正部分结束 ===
    
    axis([0 20000 -0.06 0.06]); grid on; 
    title(sprintf('128x 模式 (%0.3fMHz)', curr_fs*128/1e6));
    xlabel('Frequency (Hz)');
end
fprintf('\n所有频系验证完成。\n');

%% 3. 导出 FPGA所需的双频系 Hex (.mem) 文件 (以下保持不变)
% ... (脚本剩余部分与原稿一致，略)

%% 3. 导出 FPGA所需的双频系 Hex (.mem) 文件 (以下保持不变)
% ... (脚本剩余部分与原稿一致，略)
%% 3. 导出 FPGA所需的双频系 Hex (.mem) 文件
disp('\n==================================================');
disp('正在导出 Verilog 初始化所需的 .mem 文件...');

% 提取系数 (由于您前面已经做了定点化，这里只需恢复为整数)
W_coeff = 24; 

% 导出 HFB1
export_dual_bank_mem('hfb1_coeffs.mem', ...
    hw_rom_coeffs.Fs_48k.hfb1, hw_rom_coeffs.Fs_44k.hfb1, W_coeff);

% 导出 HFB2
export_dual_bank_mem('hfb2_coeffs.mem', ...
    hw_rom_coeffs.Fs_48k.hfb2, hw_rom_coeffs.Fs_44k.hfb2, W_coeff);

% 导出 HFB3_flat
export_dual_bank_mem('hfb3_flat_coeffs.mem', ...
    hw_rom_coeffs.Fs_48k.hfb3_flat, hw_rom_coeffs.Fs_44k.hfb3_flat, W_coeff);

% 导出 HFB3_comp
export_dual_bank_mem('hfb3_comp_coeffs.mem', ...
    hw_rom_coeffs.Fs_48k.hfb3_comp, hw_rom_coeffs.Fs_44k.hfb3_comp, W_coeff);

disp('所有 .mem 文件已成功生成到当前工作目录！');
%% === 双频系统一架构：多相折叠系数生成 ===
c48 = hw_rom_coeffs.Fs_48k.hfb1; % 51 抽头
c44 = hw_rom_coeffs.Fs_44k.hfb1; % 87 抽头

target_taps = 87; % 统一对齐到最大抽头数
num_macs = floor((target_taps + 1) / 4); % 需要 22 次乘加 (0~21)

% 对 48kHz 进行强制偶数对称补零 (51 -> 87)
pad_total = target_taps - length(c48);
pad_front = floor(pad_total / 2);
if mod(pad_front, 2) ~= 0
    pad_front = pad_front - 1; % 确保前端补零为偶数
end
pad_back = target_taps - length(c48) - pad_front;
p48 = [zeros(1, pad_front), c48, zeros(1, pad_back)];
p44 = c44; % 44.1kHz 本身就是 87，不需要补

W_coeff = 24;
scale = 2^(W_coeff-1) - 1;

fprintf('\n// === 请将以下代码复制到 Stage1_HFB1.v 的 always @(*) 中 ===\n');
fprintf('        if (sys_fs_sel == 1''b0) begin // === 48kHz 频系 ===\n');
fprintf('            case(mac_cnt)\n');
for k = 0:(num_macs-1)
    i = k * 2 + 1; % MATLAB 的 1-based 奇数索引对应偶数物理抽头
    val = round(p48(i) * scale);
    if val > scale, val = scale; end
    if val < -scale-1, val = -scale-1; end
    if val < 0, val = val + 2^W_coeff; end
    fprintf('                5''d%d: internal_coeff = 24''h%06X;\n', k, val);
end
fprintf('                default: internal_coeff = 24''d0;\n');
fprintf('            endcase\n');

fprintf('        end else begin // === 44.1kHz 频系 ===\n');
fprintf('            case(mac_cnt)\n');
for k = 0:(num_macs-1)
    i = k * 2 + 1;
    val = round(p44(i) * scale);
    if val > scale, val = scale; end
    if val < -scale-1, val = -scale-1; end
    if val < 0, val = val + 2^W_coeff; end
    fprintf('                5''d%d: internal_coeff = 24''h%06X;\n', k, val);
end
fprintf('                default: internal_coeff = 24''d0;\n');
fprintf('            endcase\n');
fprintf('        end\n');
fprintf('// ==========================================================\n');
%% === Stage 2 (2x -> 4x) 双频系统一架构系数生成 ===
c48_2 = hw_rom_coeffs.Fs_48k.hfb2; % Stage 2 @ 48k系
c44_2 = hw_rom_coeffs.Fs_44k.hfb2; % Stage 2 @ 44.1k系

% 统一对齐（Stage 2 抽头通常较少，这里假设最大 31 抽头）
target_taps_s2 = max(length(c48_2), length(c44_2)); 
num_macs_s2 = floor((target_taps_s2 + 1) / 4); 

% 补零对齐逻辑
function p = pad_coeff(c, target)
    pad = target - length(c);
    p = [zeros(1, floor(pad/2)), c, zeros(1, ceil(pad/2))];
end

p48_2 = pad_coeff(c48_2, target_taps_s2);
p44_2 = pad_coeff(c44_2, target_taps_s2);

W_coeff = 24;
scale = 2^(W_coeff-1) - 1;

fprintf('\n// === 请复制到 Stage2_HFB2.v 的系数查找表块 ===\n');
fprintf('        if (sys_fs_sel == 1''b0) begin // 48k 系 (Output 192kHz)\n');
for k = 0:(num_macs_s2-1)
    val = round(p48_2(k*2+1) * scale);
    if val < 0, val = val + 2^W_coeff; end
    fprintf('            5''d%d: internal_coeff = 24''h%06X;\n', k, val);
end
fprintf('        end else begin // 44.1k 系 (Output 176.4kHz)\n');
for k = 0:(num_macs_s2-1)
    val = round(p44_2(k*2+1) * scale);
    if val < 0, val = val + 2^W_coeff; end
    fprintf('            5''d%d: internal_coeff = 24''h%06X;\n', k, val);
end

%% === Stage 3 (4x -> 8x) 通用多相架构系数生成 (Flat & Comp) ===
disp(' ');
disp('==================================================');
disp('正在导出 Stage 3 (多模式通用多相) Verilog 系数...');

W_coeff = 24;
scale = 2^(W_coeff-1) - 1;



% 提取所有模式和频系的子相
[f48_p0, f48_p1] = get_poly_phases(hw_rom_coeffs.Fs_48k.hfb3_flat);
[f44_p0, f44_p1] = get_poly_phases(hw_rom_coeffs.Fs_44k.hfb3_flat);
[c48_p0, c48_p1] = get_poly_phases(hw_rom_coeffs.Fs_48k.hfb3_comp);
[c44_p0, c44_p1] = get_poly_phases(hw_rom_coeffs.Fs_44k.hfb3_comp);

% 打印 Verilog LUT 逻辑
fprintf('\n// === 请复制到 Stage3_MultiMode_FIR.v 的系数 LUT 中 ===\n');
fprintf('    always @(*) begin\n');
fprintf('        case ({mode_sel, sys_fs_sel, phase_sel})\n');

% 定义打印宏函数 (处理 24-bit 补码)
print_case = @(cond_str, coeff_array) ...
    arrayfun(@(k) fprintf('                4''d%d: coeff = 24''h%06X;\n', k-1, ...
    mod(round(max(min(coeff_array(k)*scale, scale), -scale-1)), 2^24)), 1:16);

fprintf('            3''b000: case(mac_cnt) // Flat 模式, 48k频系, Phase 0\n'); print_case('000', f48_p0); fprintf('                default: coeff = 24''d0; endcase\n');
fprintf('            3''b001: case(mac_cnt) // Flat 模式, 48k频系, Phase 1\n'); print_case('001', f48_p1); fprintf('                default: coeff = 24''d0; endcase\n');
fprintf('            3''b010: case(mac_cnt) // Flat 模式, 44.1k频系, Phase 0\n'); print_case('010', f44_p0); fprintf('                default: coeff = 24''d0; endcase\n');
fprintf('            3''b011: case(mac_cnt) // Flat 模式, 44.1k频系, Phase 1\n'); print_case('011', f44_p1); fprintf('                default: coeff = 24''d0; endcase\n');

fprintf('            3''b100: case(mac_cnt) // Comp 模式, 48k频系, Phase 0\n'); print_case('100', c48_p0); fprintf('                default: coeff = 24''d0; endcase\n');
fprintf('            3''b101: case(mac_cnt) // Comp 模式, 48k频系, Phase 1\n'); print_case('101', c48_p1); fprintf('                default: coeff = 24''d0; endcase\n');
fprintf('            3''b110: case(mac_cnt) // Comp 模式, 44.1k频系, Phase 0\n'); print_case('110', c44_p0); fprintf('                default: coeff = 24''d0; endcase\n');
fprintf('            3''b111: case(mac_cnt) // Comp 模式, 44.1k频系, Phase 1\n'); print_case('111', c44_p1); fprintf('                default: coeff = 24''d0; endcase\n');

fprintf('            default: coeff = 24''d0;\n');
fprintf('        endcase\n');
fprintf('    end\n');
fprintf('// ==========================================================\n');
function export_dual_bank_mem(filename, coeff_48k, coeff_44k, W_coeff)
    % 1. 计算对齐到 2的幂次方的地址深度
    max_len = max(length(coeff_48k), length(coeff_44k));
    addr_width = ceil(log2(max_len));
    bank_depth = 2^addr_width; % 单个频系的 ROM 深度
    
    fprintf('  -> 正在生成 %s (单频系深度: %d, 需地址位宽: %d-bit)\n', ...
        filename, bank_depth, addr_width);
    
    % 2. 打开文件准备写入
    fid = fopen(filename, 'w');
    if fid == -1
        error('无法创建文件: %s', filename);
    end
    
    % 与您主代码一致的缩放因子
    scale = 2^(W_coeff - 1) - 1; 
    
    % --- Bank 0: 写入 48kHz 系数 ---
    for i = 1:length(coeff_48k)
        % 恢复为整数
        val = round(coeff_48k(i) * scale); 
        % 转换为 24-bit 补码
        if val < 0
            val = val + 2^W_coeff;
        end
        fprintf(fid, '%06X\n', val);
    end
    % 补齐 48kHz Bank 的空白地址
    for i = (length(coeff_48k)+1) : bank_depth
        fprintf(fid, '000000\n');
    end

    % --- Bank 1: 写入 44.1kHz 系数 ---
    for i = 1:length(coeff_44k)
        val = round(coeff_44k(i) * scale); 
        if val < 0
            val = val + 2^W_coeff;
        end
        fprintf(fid, '%06X\n', val);
    end
    % 补齐 44.1kHz Bank 的空白地址
    for i = (length(coeff_44k)+1) : bank_depth
        fprintf(fid, '000000\n');
    end
    
    fclose(fid);
end

% 假设 h 是你 Stage 2 的完整系数向量
h = hw_rom_coeffs.Fs_48k.hfb1;
% 提取出你写进 Verilog case 语句里的那些系数（不含 0.5 那个中心点）
% 也就是所有的 h(1), h(3), h(5) ... 
sum_val = sum(h(1:2:end)) * 2; 
fprintf('插值点总增益: %f\n', sum_val);
h = hw_rom_coeffs.Fs_48k.hfb2;
% 提取出你写进 Verilog case 语句里的那些系数（不含 0.5 那个中心点）
% 也就是所有的 h(1), h(3), h(5) ... 
sum_val = sum(h(1:2:end)) * 2; 
fprintf('插值点总增益: %f\n', sum_val);
h2 = hw_rom_coeffs.Fs_48k.hfb2;
% 看看中心点的值 (应该在最中间)
center_val = h2(ceil(length(h2)/2));
% 看看插值系数的总和
interp_sum = sum(h2(1:2:end)); 

fprintf('中心点物理值: %f (理想应为 1.0 或 0.5)\n', center_val);
fprintf('插值路径总和: %f (理想应与中心点一致)\n', interp_sum);
%% === Stage 3 (4x -> 8x) 增益与多相平衡深度分析 ===
fprintf('\n==================================================\n');
fprintf('正在分析 Stage 3 模式切换下的增益一致性 (48kHz 频系):\n');

% 1. 分析 Stage 3 Flat 模式
h3f = hw_rom_coeffs.Fs_48k.hfb3_flat;
sum_p0_f = sum(h3f(1:2:end)); % Phase 0 系数和
sum_p1_f = sum(h3f(2:2:end)); % Phase 1 系数和 (通常包含中心抽头)

fprintf('[Stage 3 Flat]\n');
fprintf('  Phase 0 (插值支路) 增益: %f\n', sum_p0_f);
fprintf('  Phase 1 (中心/延时支路) 增益: %f\n', sum_p1_f);
fprintf('  分支增益差 (Mismatch): %e\n', abs(sum_p0_f - sum_p1_f));

% 2. 分析 Stage 3 Comp (CIC补偿) 模式
h3c = hw_rom_coeffs.Fs_48k.hfb3_comp;
sum_p0_c = sum(h3c(1:2:end));
sum_p1_c = sum(h3c(2:2:end));

fprintf('[Stage 3 Comp]\n');
fprintf('  Phase 0 (补偿支路A) 增益: %f\n', sum_p0_c);
fprintf('  Phase 1 (补偿支路B) 增益: %f\n', sum_p1_c);
fprintf('  分支增益差 (Mismatch): %e\n', abs(sum_p0_c - sum_p1_c));

%% 3. 验证补偿器带来的高频预加重 (Pre-emphasis)
[H_c, W] = freqz(h3c, 1, 1024);
mag_20k = abs(H_c(round(20000 / (4*48000*2) * 2048))); % 计算在 20kHz 处的增益
fprintf('\n[补偿特性检查]\n');
fprintf('  20kHz 处的预加重幅度: %+0.4f dB\n', 20*log10(mag_20k));
if 20*log10(mag_20k) > 0
    fprintf('  结果: 正常。Stage 3 已产生高频翘起，可抵消 CIC 塌陷。\n');
else
    fprintf('  警告: Stage 3 未产生预加重，请检查 CICCompensationInterpolator 配置。\n');
end
function [p0, p1] = get_poly_phases(h)
    h = h(:)';
    
    % 1. 找到能量最大点（主峰）
    [~, max_idx] = max(abs(h));
    
    % 2. 构造一个绝对干净的 32 长度容器
    h_clean = zeros(1, 32);
    
    % 3. 暴力对齐：将主峰死死钉在 Index 17 
    % (这样 1:2:end 提取 Phase 0 时，主峰必然在第 9 个，即 Verilog 的 4'd8)
    center_target = 17;
    
    % 以 max_idx 为中心，向两边搬运数据
    for i = 1:length(h)
        target_i = center_target + (i - max_idx);
        if target_i >= 1 && target_i <= 32
            h_clean(target_i) = h(i);
        end
    end
    
    % 4. 严格按照硬件奇偶切分
    p0 = h_clean(1:2:end); % 包含主峰的 Identity 相位
    p1 = h_clean(2:2:end); % 不含主峰的 Interpolation 相位
    
    % 5. 暴力对称化与增益钳制 (解决 44.1k 不对称和重影的必杀技)
    % 针对 Phase 1 (应该是对称的低通/补偿)
    % 将它强制做一次偶数对称，消除 MATLAB 带来的奇异相移
    p1_sym = (p1 + fliplr(p1)) / 2;
    p1 = p1_sym;
    
    % 6. 增益归一化：完美适配 Verilog acc_reg[46:23] 的 1.0 满量程
    p0 = p0 / sum(p0);
    p1 = p1 / sum(p1);
end