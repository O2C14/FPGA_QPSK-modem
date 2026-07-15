% RCOSFILTER_EDR2 - EDR2 平方根升余弦滤波器系数生成
% 
% EDR2 Classic Bluetooth:
%   采样率 Fs = 64 MHz
%   符号率 Rb = 1 MHz (1 Msps)
%   过采样率 = 16 samples/symbol
%   滚降因子 alpha = 0.4 (蓝牙标准)
%   滤波器跨度 = 8 symbols (与EDR2标准一致)
%   滤波器阶数 = 8 * 16 = 128 tap
%
% 输出: rcosfilter_edr2.coe 和 rcosfilter_edr2.txt

clear all;
close all;
clc;

%% 基本参数
Fs = 16;          % 采样频率 (MHz)
Rb = 1;           % 符号率 (MHz)
sps = Fs / Rb;    % 过采样率 = 16
alpha = 0.4;      % 滚降因子
span = 8;         % 滤波器跨度 (符号数)
N = span * sps;   % 滤波器阶数 = 128

fprintf('EDR2 SRRC Filter Design:\n');
fprintf('  Fs = %.0f MHz, Rb = %.0f MHz, sps = %d\n', Fs, Rb, sps);
fprintf('  Rolloff = %.1f, Span = %d symbols, Order = %d\n', alpha, span, N);

%% 设计平方根升余弦滤波器
% 使用 rcosdesign 函数 (推荐, 替换旧的 firrcos)
% rcosdesign(beta, span, sps, shape)
% shape = 'sqrt' 表示平方根升余弦
b = rcosdesign(alpha, span, sps, 'sqrt');

% 归一化系数到满幅度
b = b / max(abs(b));  % 峰值归一化
% 进一步可量化到16-bit整数

fprintf('  Filter taps: %d\n', length(b));
fprintf('  Peak coefficient: %f\n', max(abs(b)));

%% 绘制滤波器响应
figure;

% 时域响应
subplot(2,2,1);
stem(0:length(b)-1, b, 'filled', 'MarkerSize', 3);
title('SRRC Filter Impulse Response');
xlabel('Tap Index');
ylabel('Amplitude');
grid on;

% 频率响应
subplot(2,2,2);
[H, f] = freqz(b, 1, 1024, Fs*1e6);
plot(f/1e6, 20*log10(abs(H)));
title('Frequency Response');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
grid on;
% 标记截止频率
hold on;
xline(Rb/2, 'r--', sprintf('Rb/2=%.1fMHz', Rb/2));
hold off;

% 眼图验证 - 生成随机数据并通过滤波器
subplot(2,2,3);
N_sym = 200;
data = 2*randi([0,1], 1, N_sym) - 1;  % ±1
up = upsample(data, sps);
filtered = filter(b, 1, up);
eyediagram(filtered(sps+1:end-sps), 2*sps);
title('Eye Diagram');

% 级联响应 (发送+接收滤波器)
subplot(2,2,4);
b_cascade = conv(b, b);  % 匹配滤波: 发送和接收使用相同滤波器
[Hc, fc] = freqz(b_cascade, 1, 1024, Fs*1e6);
plot(fc/1e6, 20*log10(abs(Hc)));
title('Cascade Response (Tx+Rx)');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
grid on;
hold on;
xline(Rb/2, 'r--', sprintf('Rb/2=%.1fMHz', Rb/2));
hold off;

%% 生成COE文件 (Xilinx FIR Compiler格式)
Width = 16;  % 量化位宽
b_quant = round(b * (2^(Width-1) - 1));  % 量化为16-bit有符号整数

% 确保不溢出
b_quant(b_quant > (2^(Width-1)-1)) = (2^(Width-1)-1);
b_quant(b_quant < -(2^(Width-1)-1)) = -(2^(Width-1)-1);

% 写入COE文件
fid = fopen('../coe/rcosfilter_edr2.coe', 'w');
fprintf(fid, '; XILINX FIR Compiler COE File\n');
fprintf(fid, '; EDR2 Square-Root Raised Cosine Filter\n');
fprintf(fid, '; Fs = 16 MHz, Rb = 1 MHz, alpha = 0.4\n');
fprintf(fid, '; Taps = %d, Width = %d bits\n', length(b), Width);
fprintf(fid, 'Radix = 16;\n');
fprintf(fid, 'Coefficient_Width = %d;\n', Width);
fprintf(fid, 'CoefData = ');
for k = 1:length(b_quant)
    if b_quant(k) < 0
        val = b_quant(k) + 2^Width;
    else
        val = b_quant(k);
    end
    fprintf(fid, '%04x', val);
    if k < length(b_quant)
        fprintf(fid, ',\n');
    else
        fprintf(fid, ';\n');
    end
end
fclose(fid);
fprintf('  COE file saved: ../coe/rcosfilter_edr2.coe\n');

%% 生成TXT文件 (用于仿真)
fid = fopen('../coe/rcosfilter_edr2.txt', 'w');
for k = 1:length(b_quant)
    % 输出16-bit二进制补码
    if b_quant(k) < 0
        val = b_quant(k) + 2^Width;
    else
        val = b_quant(k);
    end
    fprintf(fid, '%s\n', dec2bin(val, Width));
end
fclose(fid);
fprintf('  TXT file saved: ../coe/rcosfilter_edr2.txt\n');

%% 打印前10个系数用于验证
fprintf('\nFirst 10 coefficients (16-bit hex):\n');
for k = 1:min(10, length(b_quant))
    if b_quant(k) < 0
        val = b_quant(k) + 2^Width;
    else
        val = b_quant(k);
    end
    fprintf('  h[%2d] = 0x%04X (%d)\n', k-1, val, b_quant(k));
end

fprintf('\nDone.\n');