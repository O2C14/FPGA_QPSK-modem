//////////////////////////////////////////////////////////////////////////////////
// SRRC FIR Filter - Custom implementation (replaces Xilinx FIR IP)
//
// EDR2: 129-tap symmetric FIR, 8-bit signed input, 16-bit signed coeff, 24-bit out
//
// 延迟: 2 周期流水线 (输出寄存器 + MAC累加器)
//       群延迟仍为 64 samples (FIR 固有特性, 无法消除)
//
// 资源: Vivado 自动推断 DSP48 (约 65 个对称乘法), sym-folding 减少一半乘法
//
// 接口兼容 Xilinx FIR IP (AXI-Stream simplified)
//////////////////////////////////////////////////////////////////////////////////
module rcos_fir(
    input wire          aclk,
    input wire          s_axis_data_tvalid,
    output wire         s_axis_data_tready,
    input wire  [7:0]   s_axis_data_tdata,
    output wire         m_axis_data_tvalid,
    output wire [23:0]  m_axis_data_tdata
);

    assign s_axis_data_tready = 1'b1;

    // ── 系数表: 129 个 16-bit signed, 中心对称 h[n] = h[128-n] ──
    wire signed [15:0] coe [0:128];
    assign coe[  0] = -16'sd172;  assign coe[128] = -16'sd172;
    assign coe[  1] = -16'sd71;   assign coe[127] = -16'sd71;
    assign coe[  2] =  16'sd39;   assign coe[126] =  16'sd39;
    assign coe[  3] =  16'sd150;  assign coe[125] =  16'sd150;
    assign coe[  4] =  16'sd253;  assign coe[124] =  16'sd253;
    assign coe[  5] =  16'sd342;  assign coe[123] =  16'sd342;
    assign coe[  6] =  16'sd407;  assign coe[122] =  16'sd407;
    assign coe[  7] =  16'sd442;  assign coe[121] =  16'sd442;
    assign coe[  8] =  16'sd444;  assign coe[120] =  16'sd444;
    assign coe[  9] =  16'sd409;  assign coe[119] =  16'sd409;
    assign coe[ 10] =  16'sd339;  assign coe[118] =  16'sd339;
    assign coe[ 11] =  16'sd237;  assign coe[117] =  16'sd237;
    assign coe[ 12] =  16'sd108;  assign coe[116] =  16'sd108;
    assign coe[ 13] = -16'sd39;   assign coe[115] = -16'sd39;
    assign coe[ 14] = -16'sd192;  assign coe[114] = -16'sd192;
    assign coe[ 15] = -16'sd340;  assign coe[113] = -16'sd340;
    assign coe[ 16] = -16'sd469;  assign coe[112] = -16'sd469;
    assign coe[ 17] = -16'sd566;  assign coe[111] = -16'sd566;
    assign coe[ 18] = -16'sd621;  assign coe[110] = -16'sd621;
    assign coe[ 19] = -16'sd622;  assign coe[109] = -16'sd622;
    assign coe[ 20] = -16'sd564;  assign coe[108] = -16'sd564;
    assign coe[ 21] = -16'sd444;  assign coe[107] = -16'sd444;
    assign coe[ 22] = -16'sd263;  assign coe[106] = -16'sd263;
    assign coe[ 23] = -16'sd28;   assign coe[105] = -16'sd28;
    assign coe[ 24] =  16'sd251;  assign coe[104] =  16'sd251;
    assign coe[ 25] =  16'sd557;  assign coe[103] =  16'sd557;
    assign coe[ 26] =  16'sd871;  assign coe[102] =  16'sd871;
    assign coe[ 27] =  16'sd1171; assign coe[101] =  16'sd1171;
    assign coe[ 28] =  16'sd1432; assign coe[100] =  16'sd1432;
    assign coe[ 29] =  16'sd1629; assign coe[ 99] =  16'sd1629;
    assign coe[ 30] =  16'sd1739; assign coe[ 98] =  16'sd1739;
    assign coe[ 31] =  16'sd1740; assign coe[ 97] =  16'sd1740;
    assign coe[ 32] =  16'sd1616; assign coe[ 96] =  16'sd1616;
    assign coe[ 33] =  16'sd1357; assign coe[ 95] =  16'sd1357;
    assign coe[ 34] =  16'sd960;  assign coe[ 94] =  16'sd960;
    assign coe[ 35] =  16'sd429;  assign coe[ 93] =  16'sd429;
    assign coe[ 36] = -16'sd221;  assign coe[ 92] = -16'sd221;
    assign coe[ 37] = -16'sd967;  assign coe[ 91] = -16'sd967;
    assign coe[ 38] = -16'sd1775; assign coe[ 90] = -16'sd1775;
    assign coe[ 39] = -16'sd2606; assign coe[ 89] = -16'sd2606;
    assign coe[ 40] = -16'sd3413; assign coe[ 88] = -16'sd3413;
    assign coe[ 41] = -16'sd4142; assign coe[ 87] = -16'sd4142;
    assign coe[ 42] = -16'sd4740; assign coe[ 86] = -16'sd4740;
    assign coe[ 43] = -16'sd5150; assign coe[ 85] = -16'sd5150;
    assign coe[ 44] = -16'sd5319; assign coe[ 84] = -16'sd5319;
    assign coe[ 45] = -16'sd5199; assign coe[ 83] = -16'sd5199;
    assign coe[ 46] = -16'sd4749; assign coe[ 82] = -16'sd4749;
    assign coe[ 47] = -16'sd3940; assign coe[ 81] = -16'sd3940;
    assign coe[ 48] = -16'sd2752; assign coe[ 80] = -16'sd2752;
    assign coe[ 49] = -16'sd1183; assign coe[ 79] = -16'sd1183;
    assign coe[ 50] =  16'sd757;  assign coe[ 78] =  16'sd757;
    assign coe[ 51] =  16'sd3042; assign coe[ 77] =  16'sd3042;
    assign coe[ 52] =  16'sd5628; assign coe[ 76] =  16'sd5628;
    assign coe[ 53] =  16'sd8461; assign coe[ 75] =  16'sd8461;
    assign coe[ 54] =  16'sd11471;assign coe[ 74] =  16'sd11471;
    assign coe[ 55] =  16'sd14579;assign coe[ 73] =  16'sd14579;
    assign coe[ 56] =  16'sd17697;assign coe[ 72] =  16'sd17697;
    assign coe[ 57] =  16'sd20734;assign coe[ 71] =  16'sd20734;
    assign coe[ 58] =  16'sd23599;assign coe[ 70] =  16'sd23599;
    assign coe[ 59] =  16'sd26201;assign coe[ 69] =  16'sd26201;
    assign coe[ 60] =  16'sd28457;assign coe[ 68] =  16'sd28457;
    assign coe[ 61] =  16'sd30295;assign coe[ 67] =  16'sd30295;
    assign coe[ 62] =  16'sd31653;assign coe[ 66] =  16'sd31653;
    assign coe[ 63] =  16'sd32486;assign coe[ 65] =  16'sd32486;
    assign coe[ 64] =  16'sd32767;

    // ── 输入移位寄存器 ──
    reg signed [7:0] x [0:128];
    integer j;
    always @ (posedge aclk) begin
        x[0] <= s_axis_data_tdata;
        for (j = 1; j <= 128; j = j + 1)
            x[j] <= x[j-1];
    end

    // ── 对称预加: p[n] = x[n] + x[128-n] for n=0..63 ──
    wire signed [8:0] p [0:63];
    genvar n;
    generate
        for (n = 0; n < 64; n = n + 1) begin : gen_preadd
            assign p[n] = x[n] + x[128-n];
        end
    endgenerate

    // ── MAC: 65 个乘积 (8+1 bit × 16 bit → 25 bit) ──
    wire signed [24:0] prod [0:64];
    generate
        for (n = 0; n < 64; n = n + 1) begin : gen_prod
            assign prod[n] = p[n] * coe[n];
        end
    endgenerate
    assign prod[64] = x[64] * coe[64];  // 中心 tap

    // ── 加法树 (组合逻辑, 7 级) ──
    // 65 → 33 → 17 → 9 → 5 → 3 → 2 → 1
    wire signed [29:0] s1 [0:32];  wire signed [29:0] s2 [0:16];
    wire signed [29:0] s3 [0:8];   wire signed [29:0] s4 [0:4];
    wire signed [29:0] s5 [0:2];   wire signed [29:0] s6 [0:1];
    wire signed [29:0] s7;

    generate
        // Level 1: 65 items → 33
        for (n = 0; n < 32; n = n + 1) begin : l1
            assign s1[n] = prod[2*n] + prod[2*n+1];
        end
        assign s1[32] = prod[64];

        // Level 2: 33 → 17
        for (n = 0; n < 16; n = n + 1) begin : l2
            assign s2[n] = s1[2*n] + s1[2*n+1];
        end
        assign s2[16] = s1[32];

        // Level 3: 17 → 9
        for (n = 0; n < 8; n = n + 1) begin : l3
            assign s3[n] = s2[2*n] + s2[2*n+1];
        end
        assign s3[8] = s2[16];

        // Level 4: 9 → 5
        for (n = 0; n < 4; n = n + 1) begin : l4
            assign s4[n] = s3[2*n] + s3[2*n+1];
        end
        assign s4[4] = s3[8];

        // Level 5: 5 → 3
        for (n = 0; n < 2; n = n + 1) begin : l5
            assign s5[n] = s4[2*n] + s4[2*n+1];
        end
        assign s5[2] = s4[4];

        // Level 6: 3 → 2
        assign s6[0] = s5[0] + s5[1];
        assign s6[1] = s5[2];

        // Level 7: 2 → 1
        assign s7 = s6[0] + s6[1];
    endgenerate

    // ── 输出: 截断到 24-bit, 2 周期流水线 ──
    reg signed [23:0] out_reg;
    reg               valid_reg;

    // 增益缩放: 峰值系数=32767 → 累加和最高约 2^23 量级
    // 8-bit signed 输入, 16-bit signed 系数 → 乘积 24-bit
    // 65 个乘积相加需要额外 ~6 bit → 30-bit 总和
    // 截断低 6 位 (移 6 位) 回到 24-bit 输出
    always @ (posedge aclk) begin
        out_reg   <= s7[29:6];  // 截断低 6 位
        valid_reg <= s_axis_data_tvalid;
    end

    assign m_axis_data_tdata  = out_reg;
    assign m_axis_data_tvalid = valid_reg;

endmodule