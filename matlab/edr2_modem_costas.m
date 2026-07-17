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
t = 0:dt:TotalT-dt;          % 时间向量

flocal = 1.001e6;            % 接收端本地载波频率 (引入1kHz频偏测试Costas环)
C1 = 2^(-6);                 % Costas环滤波器系数 c1 (调大以适应更快的采样率)
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
I_filtered_tx=I_filtered_tx(round((length(b_srrc)-1)/2)+1:length(I_filtered_tx));
Q_filtered_tx=Q_filtered_tx(round((length(b_srrc)-1)/2)+1:length(Q_filtered_tx));
%% ===== 上变频 (1MHz 载波) =====
carry_cos = cos(2*pi*Fc*t);
carry_sin = sin(2*pi*Fc*t);
qpsk_tx = I_filtered_tx .* carry_cos + Q_filtered_tx .* carry_sin;

%% ===== AWGN 信道 =====
SNR_dB = 20;
qpsk_rx = awgn(qpsk_tx, SNR_dB);
fprintf('  AWGN SNR = %d dB\n', SNR_dB);

%% ===== 解调 (Costas环 + 鉴相器, 保持原有逻辑) =====
err_phase = zeros(1, length(t));
carry_cos_local = zeros(1, length(t));
carry_sin_local = zeros(1, length(t));
demo_I = zeros(1, length(t));
demo_Q = zeros(1, length(t));

% 低通滤波器 (接收端匹配滤波, 使用相同 SRRC)
I_filtered = zeros(1, length(t));
Q_filtered = zeros(1, length(t));

pd_I_log = zeros(1, length(t));
pd_Q_log = zeros(1, length(t));
pd_log = zeros(1, length(t));

% 低通滤波器设计 (30阶 FIR, Fc = 1.5 MHz @ 16MHz)
% 截止频率 = 1.5 MHz (高于 0.5Rb=0.5MHz, 保留基带频谱)
N_lpf = 30;
Fc_lpf = 1.5e6;
b_lpf = fir1(N_lpf, Fc_lpf/(Fs/2), 'low', rectwin(N_lpf+1));

fprintf('  开始 Costas 环迭代 (%d 点)...\n', length(t));

% ----- 载波同步与下变频 (逐点迭代) -----
% 使用滤波器状态变量避免 filter() 函数引起的延迟累积
% fir1(N, ...) 返回 N+1 个系数, 故状态变量长度需匹配
lpf_state_I = zeros(N_lpf+1, 1);
lpf_state_Q = zeros(N_lpf+1, 1);

for i = 1:length(t)
    % 本地载波 (受 Costas 环相位调整)
    carry_cos_local(i) = cos(2*pi*flocal*t(i) - err_phase(i));
    carry_sin_local(i) = sin(2*pi*flocal*t(i) - err_phase(i));

    % 下变频
    %demo_I(i) = qpsk_rx(i) * carry_cos_local(i);
    %demo_Q(i) = qpsk_rx(i) * carry_sin_local(i);

    % 低通滤波 (逐点 FIR 实现)
    % 更新状态
    %lpf_state_I = [demo_I(i); lpf_state_I(1:end-1)];
    %lpf_state_Q = [demo_Q(i); lpf_state_Q(1:end-1)];
    %I_filtered(i) = b_lpf * lpf_state_I;
    %Q_filtered(i) = b_lpf * lpf_state_Q;

    demo_I(i) = qpsk_rx(i) * carry_cos_local(i);
    demo_Q(i) = qpsk_rx(i) * carry_sin_local(i);
    I_filtered = filter(b_lpf,1,[demo_I,zeros(1,round((length(b_lpf)-1)/2))]);
    Q_filtered = filter(b_lpf,1,[demo_Q,zeros(1,round((length(b_lpf)-1)/2))]);
    I_filtered = I_filtered(round((length(b_lpf)-1)/2)+1:length(I_filtered));
    Q_filtered = Q_filtered(round((length(b_lpf)-1)/2)+1:length(Q_filtered));
    % ---- 鉴相器 (与 qpsk_modem_costas.m 完全一致) ----
    inv_Q = -1 * Q_filtered(i);
    inv_I = -1 * I_filtered(i);

    % 依据 I 路正负选择鉴相值
    if I_filtered(i) >= 0
        pd_I_log(i) = Q_filtered(i);
    else
        pd_I_log(i) = inv_Q;
    end

    % 依据 Q 路正负选择鉴相值
    if Q_filtered(i) >= 0
        pd_Q_log(i) = I_filtered(i);
    else
        pd_Q_log(i) = inv_I;
    end

    % 鉴相器原始输出
    pd_log(i) = pd_I_log(i) - pd_Q_log(i);

    % Costas 环路滤波器
    if i == 1
        err_phase(i+1) = C1 * pd_log(i);
    elseif i ~= length(t)
        err_phase(i+1) = err_phase(i) + C1*pd_log(i) + (C2-C1)*pd_log(i-1);
    end
end

fprintf('  Costas 环迭代完成\n');

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
I_abs = abs(I_filtered);
Q_abs = abs(Q_filtered);

% 搜索 45° 符号的训练区域: 遍历前 20 个符号的抽样时刻
for j = 1:1:min(M*sps, length(I_filtered))
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
    full_level = max(abs([I_filtered, Q_filtered]));
    point_7_level = full_level * 0.707;
    fprintf('  未找到参考符号, 使用默认幅值: full=%.4f\n', full_level);
end
fprintf('  full_level=%.4f, point_7_level=%.4f, start_sample=%d\n', full_level, point_7_level, start_sample);

full_threshold = 0.85
point_7_threshold = 0.35

%% ===== π/4-DQPSK 抽样判决 =====
% 在符号中心点采样, 使用校准幅值进行 3 级量化
I_comb = [];
Q_comb = [];
for j = start_sample:L:min(M*sps, length(I_filtered))
    % 归一化到 ±full_level 范围
    I_norm = I_filtered(j) / full_level;
    Q_norm = Q_filtered(j) / full_level;
    
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

% 1. 原始 dibit 序列
figure(1);
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

% 2. I/Q 基带信号
figure(2);
t_us = t * 1e6;
plot(t_us(1:min(500,length(t))), I_base(1:min(500,length(t))), 'b', 'LineWidth', 1.5);
hold on;
plot(t_us(1:min(500,length(t))), Q_base(1:min(500,length(t))), 'r', 'LineWidth', 1.5);
title('I/Q 基带信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
legend('I', 'Q');
grid on;

% 3. 成型滤波信号
figure(3);
plot(t_us(1:min(500,length(t))), I_filtered_tx(1:min(500,length(t))), 'b', 'LineWidth', 1.5);
hold on;
plot(t_us(1:min(500,length(t))), Q_filtered_tx(1:min(500,length(t))), 'r', 'LineWidth', 1.5);
title('I/Q 成型滤波信号 (前 500 采样)');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

% 4. Costas 环鉴相器输出和环路滤波器输出
figure(4);
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

% 5. 收发载波比较
figure(5);
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

% 6. 低通滤波后信号
figure(6);
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

% 7. 星座图
figure(7);
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


% 2. I/Q 基带信号
figure(8);
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

% 3. 成型滤波信号
figure(9);
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

% 10. 低通滤波后信号 + 抽样判决点 (正确/错误颜色标注)
figure(10);

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
subplot(211);
plot(t_us(1:display_end), I_filtered(1:display_end), 'b', 'LineWidth', 1);
hold on;
plot(t_us(1:display_end), I_filtered_tx(1:display_end), 'c', 'LineWidth', 1);
title('I 路低通滤波 + 抽样判决点 (绿=正确, 红=错误)');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

% Q 路
subplot(212);
plot(t_us(1:display_end), Q_filtered(1:display_end), 'b', 'LineWidth', 1);
hold on;
plot(t_us(1:display_end), Q_filtered_tx(1:display_end), 'c', 'LineWidth', 1);
title('Q 路低通滤波 + 抽样判决点 (绿=正确, 红=错误)');
xlabel('时间 (μs)');
ylabel('幅度');
grid on;

% 在抽样时刻标记判决点
for k = 1:length(I_comb)
    sample_idx = start_sample + (k-1) * L;
    if sample_idx <= display_end
        if decode_correct(k)
            color = 'g';
            marker = 'o';
        else
            color = 'r';
            marker = 'x';
        end
        subplot(211);
        plot(t_us(sample_idx), I_filtered(sample_idx), marker, ...
            'Color', color, 'MarkerSize', 8, 'LineWidth', 1.5);
        subplot(212);
        plot(t_us(sample_idx), Q_filtered(sample_idx), marker, ...
            'Color', color, 'MarkerSize', 8, 'LineWidth', 1.5);
    end
end

% 绘制判决阈值参考线
subplot(211);
yline( full_threshold*full_level, 'k--', 'LineWidth', 0.5);
yline(-full_threshold*full_level, 'k--', 'LineWidth', 0.5);
yline( point_7_threshold*full_level, 'k:', 'LineWidth', 0.5);
yline(-point_7_threshold*full_level, 'k:', 'LineWidth', 0.5);
legend('滤波后 I', '正确点', '错误点');

subplot(212);
yline( full_threshold*full_level, 'k--', 'LineWidth', 0.5);
yline(-full_threshold*full_level, 'k--', 'LineWidth', 0.5);
yline( point_7_threshold*full_level, 'k:', 'LineWidth', 0.5);
yline(-point_7_threshold*full_level, 'k:', 'LineWidth', 0.5);
legend('滤波后 Q', '正确点', '错误点');

fprintf('\n仿真完成。\n');
