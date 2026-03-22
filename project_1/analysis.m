% 1. 读取 FPGA 仿真输出的文本数据
filename = 'out_data.txt';
data = load(filename);

% 2. 参数设置
Fs_out = 6.144e6;          % 128x 模式下的输出采样率 (48kHz * 128)
N = length(data);          % 数据点数
NFFT = 2^nextpow2(N * 4);  % 补零 (Zero-padding) 以获得更平滑的频域曲线

% 3. 执行 FFT 计算
H = fft(data, NFFT);
H_mag = abs(H(1:NFFT/2+1));           % 取单边谱
H_mag_db = 20*log10(H_mag / max(H_mag)); % 归一化并转换为 dB

% 4. 频率轴计算
f = Fs_out * (0:(NFFT/2)) / NFFT;

% 5. 绘图：全频段响应 (观察 CIC 的衰减和镜像滤除)
figure;
plot(f / 1000, H_mag_db, 'b', 'LineWidth', 1.5);
grid on;
title('128x Interpolation System Magnitude Response (Full Range)');
xlabel('Frequency (kHz)');
ylabel('Magnitude (dB)');
xlim([0, Fs_out/2000]); % 显示到 Nyquist 频率 3.072 MHz
ylim([-150, 5]);

% 6. 绘图：通带细节 (观察 Stage 3 Comp 的补偿效果)
figure;
plot(f, H_mag_db, 'r', 'LineWidth', 2);
grid on;
title('Passband Detail (0 - 24 kHz)');
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
xlim([0, 24000]); % 重点观察 0~20kHz 音频带
ylim([-0.5, 0.5]); % 观察通带纹波是否控制在 0.1dB 级别以内