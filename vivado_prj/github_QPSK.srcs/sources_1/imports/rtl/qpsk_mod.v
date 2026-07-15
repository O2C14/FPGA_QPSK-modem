//////////////////////////////////////////////////////////////////////////////////
// pi/4-DQPSK 调制器 (2-bit 符号输入)
//
// EDR2: 16MHz clk
//   输入: [1:0] sym_in (dibit) + sym_en (1MHz 符号使能)
//   处理: mapper → RCOS(16MHz) → DDS(1MHz@16MHz) → 上变频 → qpsk
//////////////////////////////////////////////////////////////////////////////////
module qpsk_mod
    (
        input wire          clk         ,  // 16MHz 主时钟
        input wire          rst_n       ,
        input wire [1:0]    sym_in      ,  // 2-bit dibit 符号
        input wire          sym_en      ,  // 符号使能 (1周期脉冲, 1MHz)

        output wire [27:0]  qpsk
    );

    // pi/4-DQPSK mapper 输出 (符号率 1MHz, zero-order hold)
    wire [7:0]  I_base      ;  // 8bit signed I
    wire [7:0]  Q_base      ;  // 8bit signed Q
    wire        sym_valid   ;  // 符号有效 (1MHz)

    // 脉冲成形滤波器输出
    wire [22:0] I_filtered  ;
    wire [22:0] Q_filtered  ;

    // 载波 (1MHz, 16MHz 采样率)
    wire [7:0]  carry_cos   ;
    wire [7:0]  carry_sin   ;

    // 上变频输出
    wire [27:0] qpsk_i      ;
    wire [27:0] qpsk_q      ;

    // ---- pi/4-DQPSK 差分编码+星座映射 ----
    pi4_dqpsk_mapper pi4_dqpsk_mapper_inst (
        .clk        (clk        ),
        .rst_n      (rst_n      ),
        .sym_in     (sym_in     ),
        .sym_en     (sym_en     ),
        .I          (I_base     ),
        .Q          (Q_base     ),
        .sym_valid  (sym_valid  )
    );

    // ---- I路成形滤波 (custom rcosfilter, 1-cycle delay) ----
    rcosfilter rcosfilter_I (
        .aclk(clk),
        .s_axis_data_tvalid(rst_n),
        .s_axis_data_tready(),
        .s_axis_data_tdata(I_base),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(I_filtered)
    );

    // ---- Q路成形滤波 ----
    rcosfilter rcosfilter_Q (
        .aclk(clk),
        .s_axis_data_tvalid(rst_n),
        .s_axis_data_tready(),
        .s_axis_data_tdata(Q_base),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(Q_filtered)
    );

    // ---- DDS: 1MHz 载波 cos (16MHz 采样率) ----
    dds_cos dds_cos_inst (
        .aclk(clk),
        .aresetn(rst_n),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(carry_cos),
        .m_axis_phase_tvalid(),
        .m_axis_phase_tdata()
    );

    // ---- DDS: 1MHz 载波 sin ----
    dds_sin dds_sin_inst (
        .aclk(clk),
        .aresetn(rst_n),
        .m_axis_data_tvalid(),
        .m_axis_data_tdata(carry_sin),
        .m_axis_phase_tvalid(),
        .m_axis_phase_tdata()
    );

    //---- I路上变频 ----
    mul_mod mul_mod_I (
        .CLK(clk),
        .A(I_filtered[22:3]),
        .B(carry_cos),
        .P(qpsk_i)
    );

    //---- Q路上变频 ----
    mul_mod mul_mod_Q (
        .CLK(clk),
        .A(Q_filtered[22:3]),
        .B(carry_sin),
        .P(qpsk_q)
    );

    //---- IQ叠加 ----
    assign qpsk = qpsk_i + qpsk_q;

endmodule