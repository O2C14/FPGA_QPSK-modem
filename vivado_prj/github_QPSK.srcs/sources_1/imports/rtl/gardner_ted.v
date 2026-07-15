//////////////////////////////////////////////////////////////////////////////////
// Gardner Timing Error Detector + Loop Filter
//
// EDR2: 16MHz采样, 1MHz符号率 (16 samples/symbol)
// 使用Gardner算法计算定时误差, 环路滤波器生成小数间隔 wn
// 同时输出最佳判决点的两路数据
//////////////////////////////////////////////////////////////////////////////////
module gardner_ted
(
    input wire          clk             ,  // 64MHz
    input wire          rst_n           ,
    input wire          strobe_flag     ,  // 有效插值标志 (来自NCO)
    input wire [19:0]   interpolate_I   ,  // 从插值滤波器来的I路数据
    input wire [19:0]   interpolate_Q   ,  // 从插值滤波器来的Q路数据

    output reg          sync_out_I      ,  // 判决后的I路数据
    output reg          sync_out_Q      ,  // 判决后的Q路数据
    output reg          sync_flag       ,  // 同步标志, 与输出判决数据对齐
    output reg [15:0]   wn                 // 通过环路滤波器后的误差数据 (低15bit小数)
);

    reg [21:0]  error               ;  // Gardner算法计算出的时间误差
    reg [21:0]  error_d1            ;

    // 寄存strobe_flag的次数 (0=最佳抽判, 1=中间点)
    reg         samp_phase          ;  // 0=最佳抽判时刻, 1=中间时刻

    // 用于计算误差的采样数据缓存
    reg [19:0]  interpolate_I_d1    ;
    reg [19:0]  interpolate_I_d2    ;
    reg [19:0]  interpolate_Q_d1    ;
    reg [19:0]  interpolate_Q_d2    ;

    wire        samp_flag           ;

    // sync_flag是samp_flag打一拍, 使sync_flag与判决输出数据对齐
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_flag <= 1'b0;
        end else begin
            sync_flag <= samp_flag;
        end
    end

    // 最佳抽样判决时刻标志
    // NCO输出交替产生最佳抽判点和中间点
    // samp_phase==0且strobe_flag高电平 -> 最佳抽判时刻
    assign samp_flag = ((samp_phase == 1'b0) && strobe_flag) ? 1'b1 : 1'b0;

    // 计算strobe_flag的相位 (0=最佳抽判, 1=中间点)
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            samp_phase <= 1'b0;
        end else if (strobe_flag) begin
            samp_phase <= ~samp_phase;
        end
    end

    // 采集最佳判决时刻以及中间时刻的数据
    // 依据Gardner算法计算误差
    // 每一个码元符号只需要计算一次误差
    // 并将得到的时间误差数据通过环路滤波, 得到小数间隔
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interpolate_I_d1 <= 20'b0;
            interpolate_I_d2 <= 20'b0;
            interpolate_Q_d1 <= 20'b0;
            interpolate_Q_d2 <= 20'b0;

            // 环路滤波器输出 w(n) 初始值 ≈ 1/(symbol_samples/2)
            // EDR2: 16 samples/symbol, 中间点间隔 = 8 samples
            // wn ≈ 1/8 = 0.125
            // 16-bit fixed: 0.125 * 2^15 = 0.125 * 32768 = 4096 = 16'b0001_0000_0000_0000
            wn    <= 16'b0001_0000_0000_0000;
            error <= 22'b0;
            error_d1 <= 22'b0;

        end else if (strobe_flag) begin
            // 最佳判决时刻及中间时刻的到来
            // 更新用于计算误差的数据
            interpolate_I_d1 <= interpolate_I;
            interpolate_I_d2 <= interpolate_I_d1;
            interpolate_Q_d1 <= interpolate_Q;
            interpolate_Q_d2 <= interpolate_Q_d1;

            if (samp_flag) begin
                // 最佳判决时刻到来
                // 计算并更新定时误差
                // ut(k) = I(k-1/2)[I(k)-I(k-1)] + Q(k-1/2)[Q(k)-Q(k-1)]
                // 依据符号位的不同, 通过移位操作实现*2以及*(-2)
                case ({interpolate_I[19], interpolate_I_d2[19],
                      interpolate_Q[19], interpolate_Q_d2[19]})
                    4'b1010: begin
                        // IQ两路都是 [I(k)-I(k-1)] < 0
                        error <= ~({interpolate_I_d1[19], interpolate_I_d1[19:0], 1'b0})+22'b1
                               + ~({interpolate_Q_d1[19], interpolate_Q_d1[19:0], 1'b0})+22'b1;
                    end
                    4'b1001: begin
                        // I路 [I(k)-I(k-1)] < 0, Q路 > 0
                        error <= ~({interpolate_I_d1[19], interpolate_I_d1[19:0], 1'b0})+22'b1
                               + {interpolate_Q_d1[19], interpolate_Q_d1[19:0], 1'b0};
                    end
                    4'b0110: begin
                        // I路 > 0, Q路 < 0
                        error <= {interpolate_I_d1[19], interpolate_I_d1[19:0], 1'b0}
                               + ~({interpolate_Q_d1[19], interpolate_Q_d1[19:0], 1'b0})+22'b1;
                    end
                    4'b0101: begin
                        // I路 > 0, Q路 > 0
                        error <= {interpolate_I_d1[19], interpolate_I_d1[19:0], 1'b0}
                               + {interpolate_Q_d1[19], interpolate_Q_d1[19:0], 1'b0};
                    end
                    4'b0100, 4'b0111: begin
                        // I路 > 0, Q路 == 0
                        error <= {interpolate_I_d1[19], interpolate_I_d1[19:0], 1'b0};
                    end
                    4'b1000, 4'b1011: begin
                        // I路 < 0, Q路 == 0
                        error <= ~({interpolate_I_d1[19], interpolate_I_d1[19:0], 1'b0})+22'b1;
                    end
                    4'b0001, 4'b1101: begin
                        // I路 == 0, Q路 > 0
                        error <= {interpolate_Q_d1[19], interpolate_Q_d1[19:0], 1'b0};
                    end
                    4'b0010, 4'b1110: begin
                        // I路 == 0, Q路 < 0
                        error <= ~({interpolate_Q_d1[19], interpolate_Q_d1[19:0], 1'b0})+22'b1;
                    end
                    default: begin
                        error <= 22'b0;
                    end
                endcase

                // 输出判决数据, 判决门限设为0, 判决符号位即可
                sync_out_I <= ~interpolate_I[19];
                sync_out_Q <= ~interpolate_Q[19];

                // 每个最佳判决时刻更新一次error数据
                error_d1 <= error;

                // 通过环路滤波器计算小数间隔
                // w(ms+1) = w(ms) + c1*(err(ms)-err(ms-1))
                // c1 = 2^(-8) (原设计保持不变, 因为误差幅度和更新速率已相应调整)
                wn = wn + ({{2{error[21]}}, error[21:8]} - {{2{error_d1[21]}}, error_d1[21:8]});
            end

        end else begin
            // 其他时刻数据保持不变
            interpolate_I_d1 <= interpolate_I_d1;
            interpolate_I_d2 <= interpolate_I_d2;
            interpolate_Q_d1 <= interpolate_Q_d1;
            interpolate_Q_d2 <= interpolate_Q_d2;
        end
    end

endmodule