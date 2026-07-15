//////////////////////////////////////////////////////////////////////////////////
// NCO 模块 - 数控振荡器
// 产生strobe信号和小数间隔uk
//
// EDR2: 16 samples/symbol
// wn = T_symbol / T_sample = 2 / 16 = 1/8 = 0.125
// nco每个采样周期递减wn, 溢出时产生strobe_flag
//////////////////////////////////////////////////////////////////////////////////
module nco
(
    input wire          clk         ,  // 64MHz
    input wire          rst_n       ,
    input wire [15:0]   wn          ,  // 环路滤波器输出的w(n), 低15bit为小数位

    output reg          strobe_flag ,  // NCO溢出信号, 代表有效插值时刻
    output reg [15:0]   uk             // 输出到插值滤波器的小数间隔, 低15bit为小数位
);

    reg [16:0]   nco_reg_eta        ;  // NCO寄存器 eta (17-bit, 2整数 + 15小数)
    wire         eta_overflow       ;  // NCO寄存器eta溢出标志
    wire [16:0]  eta_temp           ;  // NCO寄存器eta的中间计算数据

    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // EDR2: wn ≈ 1/8 = 0.125
            // nco_reg_eta 初始值设置为 0.75 (Q2.15: 17'b0_0110_0000_0000_0000)
            nco_reg_eta <= 17'b0_0110_0000_0000_0000;
            // uk 初始值设置为 0.5 (Q1.15: 16'b0_1000_0000_0000_0000)
            uk          <= 16'b0_1000_0000_0000_0000;
            strobe_flag <= 1'b0;
        end else if (eta_overflow) begin
            // NCO溢出
            strobe_flag <= 1'b1;
            // eta(mk+1) = eta(mk) - wn + 1 (mod1操作)
            nco_reg_eta <= eta_temp + 17'b0_1_0000_0000_0000_000;  // +1 (2^15 LSB)
            // uk ≈ 2 * eta(mk) (即左移1位)
            uk <= {nco_reg_eta[15:0], 1'b0};
        end else begin
            strobe_flag <= 1'b0;
            // eta递减: eta(n+1) = eta(n) - wn
            nco_reg_eta <= eta_temp;
            uk <= uk;
        end
    end

    // eta_temp = nco_reg_eta - wn
    assign eta_temp     = nco_reg_eta - {wn[15], wn};
    // 溢出: eta_temp < 0, 即符号位为1
    assign eta_overflow = eta_temp[16];

endmodule