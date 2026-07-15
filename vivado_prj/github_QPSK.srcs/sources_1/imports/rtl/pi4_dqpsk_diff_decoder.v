//////////////////////////////////////////////////////////////////////////////////
// pi/4-DQPSK 差分解码器 (Multi-bit → 2-bit 符号输出)
//
// 输入: multi-bit I/Q (15-bit signed) sampled at sync_flag
//        sync_flag 符号同步标志
//
// 原理: 
//   dot_k   = I_k * I_{k-1} + Q_k * Q_{k-1}  ~ cos(del_phi)
//   cross_k = I_{k-1} * Q_k - I_k * Q_{k-1}  ~ sin(del_phi)
//
// 判定: dibit[1] = cross_sign, dibit[0] = dot_sign
//   对应 Gray mapping:
//     dot>0, cross>0 -> 00 (pi/4)
//     dot<0, cross>0 -> 01 (3pi/4)  
//     dot<0, cross<0 -> 11 (5pi/4)
//     dot>0, cross<0 -> 10 (7pi/4)
//
// 输出: [1:0] sym_out (dibit), sym_valid (1周期脉冲)
//////////////////////////////////////////////////////////////////////////////////
module pi4_dqpsk_diff_decoder
    (
        input wire          clk         ,  // 16MHz
        input wire          rst_n       ,

        input wire [14:0]   data_I      ,  // I路 (来自低通滤波后)
        input wire [14:0]   data_Q      ,  // Q路
        input wire          sync_flag   ,  // 符号同步 (1周期脉冲)

        output reg [1:0]    sym_out     ,  // 2-bit dibit 输出
        output reg          sym_valid      // 符号有效 (1周期脉冲)
    );

    // 前一符号的I/Q
    reg signed [14:0]  I_prev, Q_prev;

    // dot 和 cross 乘积
    wire signed [29:0]  I_prev_Q_prod;      // I_{k-1} * Q_k
    wire signed [29:0]  I_Q_prev_prod;      // I_k * Q_{k-1}

    assign I_prev_Q_prod  = $signed(I_prev) * $signed(data_Q);
    assign I_Q_prev_prod  = $signed(data_I) * $signed(Q_prev);

    wire signed [30:0] cross_diff;
    assign cross_diff = $signed({I_prev_Q_prod[29], I_prev_Q_prod}) - $signed({I_Q_prev_prod[29], I_Q_prev_prod});

    // dot = I_k*I_{k-1} + Q_k*Q_{k-1}, 通过比较 I 和 Q 的符号简化:
    // dot>0 when (I_k与I_{k-1}同号) AND (Q_k与Q_{k-1}同号)
    // dot<0 when (I_k与I_{k-1}异号) AND (Q_k与Q_{k-1}异号)  
    // But for robust multi-bit, use actual product sum:
    wire signed [29:0]  I_prod, Q_prod;
    assign I_prod = $signed(data_I) * $signed(I_prev);
    assign Q_prod = $signed(data_Q) * $signed(Q_prev);
    wire signed [30:0] dot_sum;
    assign dot_sum = $signed({I_prod[29], I_prod}) + $signed({Q_prod[29], Q_prod});

    wire dot_sign   = dot_sum[30];       // 1 = negative (dot<0)
    wire cross_sign = cross_diff[30];    // 1 = negative (cross<0)

    // 判决: dibit[1] = cross_sign, dibit[0] = dot_sign
    wire [1:0] dibit;
    assign dibit[1] = cross_sign;
    assign dibit[0] = dot_sign;

    //---- 前一符号延迟 ----
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            I_prev <= 15'd0;
            Q_prev <= 15'd0;
        end else if (sync_flag) begin
            I_prev <= data_I;
            Q_prev <= data_Q;
        end
    end

    //---- 输出锁存 ----
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sym_out   <= 2'b00;
            sym_valid <= 1'b0;
        end else begin
            sym_valid <= sync_flag;
            if (sync_flag) begin
                sym_out <= dibit;
            end
        end
    end

endmodule