//////////////////////////////////////////////////////////////////////////////////
// pi/4-DQPSK 解调器 (2-bit 符号输出)
//
// EDR2: 16MHz clk, 16MHz采样, 1MHz符号率, 1MHz载波
// 结构: 下变频 -> 低通滤波 -> Costas环 -> Gardner位同步 -> 差分解码 -> 符号输出
//
// 输出: [1:0] sym_out (dibit), sym_valid (1周期脉冲)
//////////////////////////////////////////////////////////////////////////////////
module qpsk_demod
    (
        input wire          clk         ,  // 16MHz
        input wire          rst_n       ,
        input wire  [27:0]  qpsk        ,

        output wire [1:0]   sym_out     ,  // 2-bit dibit 输出
        output wire         sym_valid      // 符号有效 (1周期脉冲)
    );

    // 载波DDS (1MHz, 相位由Costas环调整)
    wire [7:0]  carry_sin   ;
    wire [7:0]  carry_cos   ;

    // 下变频
    wire [35:0] demo_I      ;
    wire [35:0] demo_Q      ;

    // 低通滤波
    wire [55:0] filtered_I  ;
    wire [55:0] filtered_Q  ;

    // Costas 鉴相器 + 环路滤波
    wire [57:0] phase_error ;
    wire [23:0] pd          ;  // 环路滤波器输出(相位调整)

    // Gardner 位同步 (抽样判决后输出)
    wire        sync_I      ;  // 1-bit I判决
    wire        sync_Q      ;  // 1-bit Q判决
    wire        sync_flag   ;  // 符号同步标志

    //---- DDS: 1MHz 相干载波 cos (Fixed PINC + Streaming POFF) ----
    dds_demo_cos dds_demo_cos_inst (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_phase_tvalid(1'b1),
        .s_axis_phase_tdata(24'd0 - pd),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(carry_cos),
        .m_axis_phase_tvalid(),
        .m_axis_phase_tdata()
    );

    //---- DDS: 1MHz 相干载波 sin ----
    dds_demo_sin dds_demo_sin_inst (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_phase_tvalid(1'b1),
        .s_axis_phase_tdata(24'd0 - pd),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(carry_sin),
        .m_axis_phase_tvalid(),
        .m_axis_phase_tdata()
    );

    //---- I路下变频 (qpsk × cos) ----
    mul_demo mul_demo_I (
        .CLK(clk),
        .A(qpsk),
        .B(carry_cos),
        .P(demo_I)
    );

    //---- Q路下变频 (qpsk × sin) ----
    mul_demo mul_demo_Q (
        .CLK(clk),
        .A(qpsk),
        .B(carry_sin),
        .P(demo_Q)
    );

    //---- I路低通滤波 ----
    demo_lowpass demo_lowpass_I (
        .aclk(clk),
        .s_axis_data_tvalid(1'b1),
        .s_axis_data_tready(),
        .s_axis_data_tdata(demo_I),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(filtered_I)
    );

    //---- Q路低通滤波 ----
    demo_lowpass demo_lowpass_Q (
        .aclk(clk),
        .s_axis_data_tvalid(1'b1),
        .s_axis_data_tready(),
        .s_axis_data_tdata(demo_Q),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(filtered_Q)
    );

    //---- 鉴相器 (Costas环) ----
    phase_detector phase_detector_inst (
        .filtered_I     (filtered_I         ),
        .filtered_Q     (filtered_Q         ),
        .phase_error    (phase_error        )
    );

    //---- Costas环路滤波器 ----
    costas_loop_filter costas_loop_filter_inst (
        .clk            (clk                ),
        .rst_n          (rst_n              ),
        .pd_err         (phase_error        ),
        .pd             (pd                 )
    );

    //---- Gardner 位同步 + 抽样判决 ----
    gardner_sync gardner_sync_inst (
        .clk            (clk                ),
        .rst_n          (rst_n              ),
        .data_in_I      (filtered_I[54:40]  ),
        .data_in_Q      (filtered_Q[54:40]  ),
        .sync_out_I     (sync_I             ),
        .sync_out_Q     (sync_Q             ),
        .sync_flag      (sync_flag          )
    );

    //---- pi/4-DQPSK 差分解码器 ----
    pi4_dqpsk_diff_decoder diff_decoder_inst (
        .clk            (clk                ),
        .rst_n          (rst_n              ),
        .data_I         (filtered_I[54:40]  ),
        .data_Q         (filtered_Q[54:40]  ),
        .sync_flag      (sync_flag          ),
        .sym_out        (sym_out            ),
        .sym_valid      (sym_valid          )
    );

endmodule