//////////////////////////////////////////////////////////////////////////////////
// pi/4-DQPSK Mapper - 差分编码 + 基带I/Q星座映射
//
// EDR2 Classic Bluetooth:
//   2-bit 符号输入 (dibit), 符号率 1MHz
//   dibit -> del_phi (Gray code):
//     00 ->  pi/4 ( 45 deg)
//     01 -> 3pi/4 (135 deg)
//     11 -> 5pi/4 (225 deg)
//     10 -> 7pi/4 (315 deg)
//   phi_k = phi_{k-1} + del_phi (mod 2*pi)
//   输出 I/Q = 8bit signed cos/sin of phi_k, zero-order hold
//////////////////////////////////////////////////////////////////////////////////
module pi4_dqpsk_mapper
    (
        input wire          clk         ,  // 16MHz 系统时钟
        input wire          rst_n       ,
        input wire [1:0]    sym_in      ,  // 2-bit 符号输入 (dibit)
        input wire          sym_en      ,  // 符号使能 (1周期脉冲, 1MHz)

        output reg  [7:0]   I           ,  // 基带I路 8bit signed
        output reg  [7:0]   Q           ,  // 基带Q路 8bit signed
        output reg          sym_valid      // 符号有效 (1周期脉冲, 1MHz)
    );

    // 8bit相位累加器: 0..255 -> 0..2pi
    reg [7:0]  phase_acc;

    // del_phi lookup (Gray coded)
    // 00->32(pi/4), 01->96(3pi/4), 11->160(5pi/4), 10->224(7pi/4)
    wire [7:0] dphi;
    assign dphi = (sym_in == 2'b00) ? 8'd32  :
                  (sym_in == 2'b01) ? 8'd96  :
                  (sym_in == 2'b11) ? 8'd160 :
                  8'd224;  // 2'b10 -> 224 (7pi/4)

    // 星座表: phase[7:5] 3bit -> 8个绝对相位
    // 0:0deg 1:45 2:90 3:135 4:180 5:225 6:270 7:315
    wire [2:0]  idx = phase_acc[7:5];

    // 8项 cos/sin LUT
    reg signed [7:0] cos_tab [0:7];
    reg signed [7:0] sin_tab [0:7];

    initial begin
        // cos_tab[0] =  127; sin_tab[0] =    0;
        // cos_tab[1] =   90; sin_tab[1] =   90;
        // cos_tab[2] =    0; sin_tab[2] =  127;
        // cos_tab[3] =  -90; sin_tab[3] =   90;
        // cos_tab[4] = -127; sin_tab[4] =    0;
        // cos_tab[5] =  -90; sin_tab[5] =  -90;
        // cos_tab[6] =    0; sin_tab[6] = -127;
        // cos_tab[7] =   90; sin_tab[7] =  -90;
        cos_tab[0] =  3; sin_tab[0] =    0;
        cos_tab[1] =   2; sin_tab[1] =   2;
        cos_tab[2] =    0; sin_tab[2] =  3;
        cos_tab[3] =  -2; sin_tab[3] =   2;
        cos_tab[4] = -3; sin_tab[4] =    0;
        cos_tab[5] =  -2; sin_tab[5] =  -2;
        cos_tab[6] =    0; sin_tab[6] = -3;
        cos_tab[7] =   2; sin_tab[7] =  -2;
    end

    wire signed [7:0] I_raw = cos_tab[idx];
    wire signed [7:0] Q_raw = sin_tab[idx];

    //---- 相位累加 (在 sym_en 时更新) ----
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 8'd0;
        end else if (sym_en) begin
            phase_acc <= phase_acc + dphi;
        end
    end

    //---- 输出锁存 (zero-order hold) ----
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            I         <= 8'd0;
            Q         <= 8'd0;
            sym_valid <= 1'b0;
        end else begin
            sym_valid <= sym_en;
            if (sym_en) begin
                I <= I_raw;
                Q <= Q_raw;
            end
        end
    end

endmodule