% EDR2 π/4-DQPSK 调制解调仿真 (带Costas环路滤波)
%
% 基于 qpsk_modem_costas.m 的鉴相器和抽样判决逻辑
% 输入数据来自 edrsym.txt (dibit 符号值 0/1/2/3)
%
% EDR2 参数:
%   载波频率: 1 MHz
%   采样频率: 16 MHz
%   符号速率: 1 Msps
%   比特速率: 2 Mbps
%   采样/符号: 16

clear all;
close all;
clc;

%% ===== 基本参数 =====
Fc = 1e6;                    % 载波频率 1 MHz
Fs = 16e6;                   % 采样频率 16 MHz
Rb = 1e6;                    % 符号速率 1 Msps
sps = Fs / Rb;               % 采样/符号 = 16
L = sps;                     % 每个符号采样点数
M = 133;                     % 符号数 (edrsym.txt 中的符号数量)
TotalT = M / Rb;             % 总时间
dt = 1 / Fs;                 % 采样间隔
%t = 0:dt:TotalT-dt;          % 时间向量

flocal = 1.001e6;            % 接收端本地载波频率 (引入1kHz频偏测试Costas环)
C1 = 2^(-5);                 % Costas环滤波器系数 c1 (调大以适应更快的采样率)
C2 = C1 * 2^(-3);            % Costas环滤波器系数 c2

fprintf('EDR2 π/4-DQPSK 仿真参数:\n');
fprintf('  Fc = %.3f MHz, Fs = %.0f MHz, Rb = %.0f Msps\n', Fc/1e6, Fs/1e6, Rb/1e6);
fprintf('  sps = %d, 符号数 = %d\n', sps, M);
fprintf('  flocal = %.6f MHz (频偏 = %.1f kHz)\n', flocal/1e6, (flocal-Fc)/1e3);
fprintf('  C1 = 2^(-%d), C2 = 2^(-%d)\n', -log2(C1), -log2(C2));

%% ===== 读取输入符号 (dibit 0/1/2/3) =====
edrSym = load('edrsym.txt');
M = length(edrSym);
fprintf('  读取 %d 个符号\n', M);

% 将 dibit 转换为 2-bit 格雷编码的比特对
% 0 -> 00, 1 -> 01, 2 -> 10, 3 -> 11
bitPairs = zeros(M, 2);
for k = 1:M
    switch edrSym(k)
        case 0, bitPairs(k,:) = [0 0];
        case 1, bitPairs(k,:) = [0 1];
        case 2, bitPairs(k,:) = [1 0];
        case 3, bitPairs(k,:) = [1 1];
    end
end

% 计算期望的比特误码率 (用于参照)
fprintf('  期望的比特对数: %d 对\n', M);

%% ===== π/4-DQPSK 调制 =====

% 差分相位编码
% dibit -> del_phi (格雷码):
%   00 ->  pi/4 ( 45°)
%   01 -> 3pi/4 (135°)
%   11 -> 5pi/4 (225°)
%   10 -> 7pi/4 (315°)
del_phi = zeros(1, M);
for k = 1:M
    dibit_val = bitPairs(k,1)*2 + bitPairs(k,2);
    switch dibit_val
        case 0, del_phi(k) = pi/4;    % 00
        case 1, del_phi(k) = 3*pi/4;  % 01
        case 2, del_phi(k) = 7*pi/4;  % 10
        case 3, del_phi(k) = 5*pi/4;  % 11
    end
end

% 绝对相位累加
phi = zeros(1, M);
phi(1) = 0;  % 初始相位
for k = 2:M
    phi(k) = mod(phi(k-1) + del_phi(k-1), 2*pi);
end

% I/Q 基带信号 (每符号保持 sps 个采样)
I_base = zeros(1, M*sps);
Q_base = zeros(1, M*sps);
for k = 1:M
    I_k = cos(phi(k));
    Q_k = sin(phi(k));
    idx = (k-1)*sps + (1:sps);
    I_base(idx) = I_k;
    Q_base(idx) = Q_k;
end

%% ===== 成形滤波 (SRRC) =====
% 使用 MATLAB 的 rcosdesign 设计平方根升余弦滤波器
alpha = 0.4;   % 滚降因子 (蓝牙标准)
span = 8;      % 滤波器跨度 (符号数)
b_srrc = rcosdesign(alpha, span, sps, 'sqrt');
b_srrc = b_srrc / max(abs(b_srrc));  % 峰值归一化

I_filtered_tx = filter(b_srrc, 1, [I_base,zeros(1, round((length(b_srrc)-1)/2))]);
Q_filtered_tx = filter(b_srrc, 1, [Q_base,zeros(1, round((length(b_srrc)-1)/2))]);


t = 0:dt:((length(I_filtered_tx)-1)*dt);          % 时间向量


%% ===== 校准参考幅值 =====
% 对于 π/4-DQPSK，星座图有 8 个点:
%   轴上点 (0°/90°/180°/270°): I=±full, Q=0 或 I=0, Q=±full
%   45°点 (45°/135°/225°/315°): I=±0.707*full, Q=±0.707*full
%
% 需要从接收信号中自动校准 full_level 和 point_7_level
% 方法: 搜索第一个 45° 符号 (I 和 Q 幅值接近且均非零)

full_level = 0;
point_7_level = 0;
start_sample = round(L/2);  % 默认起始抽样位置

% 对滤波后信号取绝对值用于幅值判断
I_abs = abs(I_filtered_tx);
Q_abs = abs(Q_filtered_tx);

% 搜索 45° 符号的训练区域: 遍历前 20 个符号的抽样时刻
for j = 1:1:min(M*sps, length(I_filtered_tx))
    % 45°符号的特征: |I| 和 |Q| 均 > 0 且比值接近 1
    if I_abs(j) > 3 && Q_abs(j) > 3
        ratio = I_abs(j) / max(Q_abs(j), 1e-9);
        if ratio > 0.8 && ratio < 1.2
            start_sample = j;
            point_7_level = (I_abs(j) + Q_abs(j)) / 2;
            full_level = point_7_level / 0.707;
            fprintf('  找到参考符号 @ sample=%d %.4fus, I_abs=%.4f, Q_abs=%.4f\n', j, j*1e6/Fs, I_abs(j), Q_abs(j));
            break;
        end
    end
end

% 如果搜索失败, 使用默认值
if full_level == 0
    full_level = max(abs([I_filtered_tx, Q_filtered_tx]));
    point_7_level = full_level * 0.707;
    fprintf('  未找到参考符号, 使用默认幅值: full=%.4f\n', full_level);
end
fprintf('  full_level=%.4f, point_7_level=%.4f, start_sample=%d\n', full_level, point_7_level, start_sample);

full_threshold = 0.85;
point_7_threshold = 0.35;

%% ===== π/4-DQPSK 抽样判决 =====
% 在符号中心点采样, 使用校准幅值进行 3 级量化
I_comb = [];
Q_comb = [];
%for j = start_sample:L:min(M*sps, length(I_filtered_tx))
for j = start_sample:L:length(I_filtered_tx)
    if false
        % 归一化到 ±full_level 范围
        I_norm = I_filtered_tx(j) / full_level;
        Q_norm = Q_filtered_tx(j) / full_level;
        
        % 3 级量化判定:
        %   |值| > 0.85  → ±1 (轴上点)
        %   |值| > 0.35  → ±0.707 (45°点)
        %   |值| <= 0.35 → 0
        if I_norm > full_threshold
            I_val = 1;
        elseif I_norm < -full_threshold
            I_val = -1;
        elseif I_norm > point_7_threshold
            I_val = 0.707;
        elseif I_norm < -point_7_threshold
            I_val = -0.707;
        else
            I_val = 0;
        end
        
        if Q_norm > full_threshold
            Q_val = 1;
        elseif Q_norm < -full_threshold
            Q_val = -1;
        elseif Q_norm > point_7_threshold
            Q_val = 0.707;
        elseif Q_norm < -point_7_threshold
            Q_val = -0.707;
        else
            Q_val = 0;
        end
    else
        I_norm = I_filtered_tx(j) / full_level;
        Q_norm = Q_filtered_tx(j) / full_level;
        if abs(I_norm) < 0.2
            I_val = 0;
        else
            if rem(length(I_comb), 2) == 0
                I_val = 1;
            else
                I_val = 0.707;
            end
            if I_norm < abs(I_norm)
                I_val = I_val * -1;
            end
        end
        if abs(Q_norm) < 0.2
            Q_val = 0;
        else
            if rem(length(Q_norm), 2) == 0
                Q_val = 1;
            else
                Q_val = 0.707;
            end
            if Q_norm < abs(Q_norm)
                Q_val = Q_val * -1;
            end
        end
    end
    I_comb = [I_comb, I_val];
    Q_comb = [Q_comb, Q_val];
end

fprintf('  抽样判决完成: %d 个符号\n', length(I_comb));

%% ===== 差分解码 (多级幅值版本) =====
% 利用 dot/cross 乘积, 使用完整的多级幅值
num_decoded = min(length(I_comb), length(Q_comb));
decoded_syms = zeros(1, num_decoded);
for k = 2:num_decoded
    Ik   = I_comb(k);
    Qk   = Q_comb(k);
    Ik_1 = I_comb(k-1);
    Qk_1 = Q_comb(k-1);

    % dot = Ik*Ik_1 + Qk*Qk_1  ~ cos(del_phi)
    % cross = Ik_1*Qk - Ik*Qk_1 ~ sin(del_phi)
    dot   = Ik*Ik_1 + Qk*Qk_1;
    cross = Ik_1*Qk - Ik*Qk_1;

    % 判决阈值:
    %   |dot| > 0.3 且 |cross| > 0.3 → 区分 4 个象限
    %   否则可能是幅值退化情况
    if dot > 0.3 && cross > 0.3
        decoded_syms(k) = 0;   % pi/4
    elseif dot < -0.3 && cross > 0.3
        decoded_syms(k) = 1;   % 3pi/4
    elseif dot < -0.3 && cross < -0.3
        decoded_syms(k) = 3;   % 5pi/4
    elseif dot > 0.3 && cross < -0.3
        decoded_syms(k) = 2;   % 7pi/4
    elseif dot > 0 && cross > 0
        decoded_syms(k) = 0;
    elseif dot < 0 && cross > 0
        decoded_syms(k) = 1;
    elseif dot < 0 && cross < 0
        decoded_syms(k) = 3;
    elseif dot > 0 && cross < 0
        decoded_syms(k) = 2;
    else
        % dot=0 或 cross=0: 保留上一符号
        decoded_syms(k) = decoded_syms(k-1);
    end
end

%% ===== 计算误符号率 =====
num_compare = min(M-1, num_decoded-1);  % 差分解码损失第一个符号
sym_errors = sum(decoded_syms(2:num_compare+1) ~= edrSym(2:num_compare+1)');
fprintf('\n误符号率: %d / %d = %.2f%%\n', sym_errors, num_compare, 100*sym_errors/num_compare);

%% ===== 绘图 =====

figure_index = 1;
t_us = t * 1e6;

if false

% 1. 原始 dibit 序列
figure(figure_index);
figure_index = figure_index + 1;
subplot(211);
stem(1:M, edrSym, 'filled', 'MarkerSize', 4);
title('EDR2 输入符号 (dibit)');
xlabel('符号索引');
ylabel('dibit 值');
grid on;
subplot(212);
stem(1:num_decoded, decoded_syms, 'filled', 'MarkerSize', 4);
title('解调输出符号');
xlabel('符号索引');
ylabel('dibit 值');
grid on;

end

if false

% 2. I/Q 基带信号
figure(figure_index);
figure_index = figure_index + 1;
plot(t_us(1:min(500,length(t))), I_base(1:min(500,length(t))), 'b', 'LineWidth', 1.5);
hold on;
plot(t_us(1:min(500,length(t))), Q_base(1:min(500,length(t))), 'r', 'LineWidth', 1.5);
title('I/Q 基带信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
legend('I', 'Q');
grid on;

end

if false

% 3. 成型滤波信号
figure(figure_index);
figure_index = figure_index + 1;
plot(t_us(1:min(500,length(t))), I_filtered_tx(1:min(500,length(t))), 'b', 'LineWidth', 1.5);
hold on;
plot(t_us(1:min(500,length(t))), Q_filtered_tx(1:min(500,length(t))), 'r', 'LineWidth', 1.5);
title('I/Q 成型滤波信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

end

if false

% 4. Costas 环鉴相器输出和环路滤波器输出
figure(figure_index);
figure_index = figure_index + 1;
subplot(211);
plot(t_us, pd_log, 'LineWidth', 1);
title('鉴相器计算结果');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;
subplot(212);
plot(t_us, err_phase, 'LineWidth', 1);
title('Costas 环路滤波器输出 (相位调整)');
xlabel('时间 (μs)');
ylabel('相位 (rad)');
grid on;

end

if false

% 5. 收发载波比较
figure(figure_index);
figure_index = figure_index + 1;
nop = 300;
start = 1000;
if start+nop > length(t)
    start = 1;
    nop = min(300, length(t));
end
subplot(211);
t_range = t_us(start:start+nop-1);
plot(t_range, carry_sin(start:start+nop-1), 'b', 'LineWidth', 1.5);
hold on;
plot(t_range, carry_sin_local(start:start+nop-1), 'r--', 'LineWidth', 1.5);
legend('发送端正弦载波', '接收端本地正弦载波');
title('正弦载波比较');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

subplot(212);
plot(t_range, carry_cos(start:start+nop-1), 'b', 'LineWidth', 1.5);
hold on;
plot(t_range, carry_cos_local(start:start+nop-1), 'r--', 'LineWidth', 1.5);
legend('发送端余弦载波', '接收端本地余弦载波');
title('余弦载波比较');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

end

if false

% 6. 低通滤波后信号
figure(figure_index);
figure_index = figure_index + 1;
subplot(211);
plot(t_us(1:min(2000,length(t))), I_filtered(1:min(2000,length(t))), 'LineWidth', 1);
title('I 路经过低通滤波后的信号 (前 2000 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
subplot(212);
plot(t_us(1:min(2000,length(t))), Q_filtered(1:min(2000,length(t))), 'LineWidth', 1);
title('Q 路经过低通滤波后的信号 (前 2000 采样)');
xlabel('时间 (μs)');
ylabel('幅度');

end

if true

% 7. 星座图
figure(figure_index);
figure_index = figure_index + 1;
% 选取稳定后的数据
stable_start = min(length(I_comb), round(length(I_comb)*0.3));
stable_end = min(length(I_comb), stable_start+80);
if stable_end > stable_start
    scatter(I_comb(stable_start:stable_end), Q_comb(stable_start:stable_end), 36, 'filled');
    hold on;
    % 绘制参考 8-PSK 星座点
    %ref_phi = 0:pi/4:2*pi-pi/4;
    %ref_I = cos(ref_phi);
    %ref_Q = sin(ref_phi);
    %scatter(ref_I, ref_Q, 100, 'rx', 'LineWidth', 2);
    legend('解调符号', '参考星座点');
    title(sprintf('星座图 (符号 %d~%d)', stable_start, stable_end));
    xlabel('I');
    ylabel('Q');
    axis([-1.5 1.5 -1.5 1.5]);
    grid on;
end

end

if false

% 2. I/Q 基带信号
figure(figure_index);
figure_index = figure_index + 1;
t_us = t * 1e6;
subplot(211);
plot(t_us(1:min(500,length(t))), I_base(1:min(500,length(t))), 'b', 'LineWidth', 1.5);
title('I 基带信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
subplot(212);
plot(t_us(1:min(500,length(t))), Q_base(1:min(500,length(t))), 'r', 'LineWidth', 1.5);
title('Q 基带信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

end

if false

% 3. 成型滤波信号
figure(figure_index);
figure_index = figure_index + 1;
subplot(211);
plot(t_us(1:min(500,length(t))), I_filtered_tx(1:min(500,length(t))), 'b', 'LineWidth', 1.5);
title('I 成型滤波信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
subplot(212);
plot(t_us(1:min(500,length(t))), Q_filtered_tx(1:min(500,length(t))), 'r', 'LineWidth', 1.5);
title('Q 成型滤波信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

end

if true

% 10. 低通滤波后信号 + 抽样判决点 (正确/错误颜色标注)
figure(figure_index);
figure_index = figure_index + 1;

% 计算每个判决点对应的正确性标志
decode_correct = zeros(1, num_decoded);
% 差分解码的第 1 个符号无法验证 (缺失前一个符号)
decode_correct(1) = 0;  % 不判断
for k = 1:num_decoded
    if k <= M  % 在输入符号范围内
        decode_correct(k) = (decoded_syms(k) == edrSym(k));
    else
        decode_correct(k) = 0;
    end
end

% 确定显示范围: 从 start_sample 到最后一个抽样点
last_sample = start_sample + (length(I_comb)-1) * L;
end_sample = min(length(t), last_sample);
nop = end_sample;  % 实际显示到大致的最后一个点附近
% 适当留一些余量
display_end = min(end_sample + 200, length(t));

% I 路
ax1 = subplot(211);
plot(t_us(1:display_end), I_filtered_tx(1:display_end)/full_level, 'b', 'LineWidth', 1);
hold on;
xlabel('时间 (μs)');
ylabel('幅度');
%grid on;

% Q 路
ax2 = subplot(212);
plot(t_us(1:display_end), Q_filtered_tx(1:display_end)/full_level, 'b', 'LineWidth', 1);
hold on;
xlabel('时间 (μs)');
ylabel('幅度');
%grid on;

if true
% 在抽样时刻标记判决点
for k = 1:length(I_comb)
    sample_idx = start_sample + (k-1) * L;
    if sample_idx <= display_end
        for j = 1:2
            if bitand(bitshift(1,(j-1)),decoded_syms(k)) == bitand(bitshift(1,(j-1)),edrSym(k))
                color = 'g';
            else
                color = 'r';
            end
            if bitand(bitshift(1,(j-1)),edrSym(k)) ~= 0
                marker = 'o';
            else
                marker = 'x';
            end
            if j == 1
                ax1 = subplot(211);
                plot(t_us(sample_idx), I_filtered_tx(sample_idx)/full_level, marker, ...
                    'Color', color, 'MarkerSize', 8, 'LineWidth', 1.5);
            else
                ax2 = subplot(212);
                plot(t_us(sample_idx), Q_filtered_tx(sample_idx)/full_level, marker, ...
                    'Color', color, 'MarkerSize', 8, 'LineWidth', 1.5);
            end
        end
    end
end
end
% 绘制判决阈值参考线
ax1 = subplot(211);
yline( full_threshold, 'k--', 'LineWidth', 0.5);
yline(-full_threshold, 'k--', 'LineWidth', 0.5);
yline( point_7_threshold, 'k:', 'LineWidth', 0.5);
yline(-point_7_threshold, 'k:', 'LineWidth', 0.5);

ax2 = subplot(212);
yline( full_threshold, 'k--', 'LineWidth', 0.5);
yline(-full_threshold, 'k--', 'LineWidth', 0.5);
yline( point_7_threshold, 'k:', 'LineWidth', 0.5);
yline(-point_7_threshold, 'k:', 'LineWidth', 0.5);

linkaxes([ax1 ax2], 'xy')
end

fprintf('\n仿真完成。\n');
