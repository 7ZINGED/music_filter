% 1. 加载数据
data = load('out_data.txt');

% 2. 确保数据是列向量
data = data(:); 

% 3. 参数设置
Fs_in = 48000;
Fs_out = Fs_in * 4; 
% 使用 floor 确保是整数，且 NFFT 至少与数据等长
NFFT = 2^nextpow2(length(data)); 

% 4. 执行 FFT
H = fft(data, NFFT);

% --- 核心修正部分 ---
% 使用 floor 强制转换索引为整数，并确保不越界
stop_idx = floor(NFFT/2) + 1;
H_mag = abs(H(1:stop_idx)); 

% 归一化并转为 dB
H_mag_db = 20*log10(H_mag / max(H_mag + 1e-12)); % 加微小值防止 log(0)
% ------------------

% 5. 频率轴也需对应长度
f = Fs_out * (0:(stop_idx-1)) / NFFT;

% 6. 绘图
figure;
plot(f/1000, H_mag_db, 'LineWidth', 1.5);
grid on;
title('4x Interpolation Magnitude Response');
xlabel('Frequency (kHz)');
ylabel('Gain (dB)');
xlim([0, Fs_out/2000]); % 显示到 96kHz
ylim([-120, 5]);