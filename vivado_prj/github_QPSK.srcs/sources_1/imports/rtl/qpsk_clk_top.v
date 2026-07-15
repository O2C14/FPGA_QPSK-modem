`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 顶层模块 - pi/4-DQPSK EDR2 (从文件读取符号)
// 时钟: 16MHz
//
// 从 edrsym.txt 读取符号序列, 经过 π/4-DQPSK 调制解调, 验证输出符号
//////////////////////////////////////////////////////////////////////////////////
module qpsk_clk_top
#(
    parameter SYM_FILE = "edrsym.txt",  // 符号文件路径
    parameter MAX_SYMS = 256            // 最大符号数
)
(
    input wire          clk         ,  // 16MHz
    input wire          rst_n       ,

    output wire [5:0]   sel         ,
    output wire [7:0]   dig
);

    // ---- 调制信号 ----
    wire [27:0]         qpsk    ;

    // ---- 符号输入 (从文件读取) ----
    reg [1:0]   sym_in_reg;
    reg         sym_en_reg;

    // ---- 解调输出 ----
    wire [1:0]  sym_out;
    wire        sym_valid;

    // ---- 文件读取 ----
    reg [1:0]   sym_mem [0:MAX_SYMS-1];
    integer     num_syms;
    integer     fd, scan_ret, k;

    // ---- 符号时序: 每16个clk输出一个符号 (1MHz) ----
    reg [3:0]   sym_cnt;
    reg [8:0]   sym_idx;      // 当前输出到第几个符号
    reg         sym_seq_done;  // 所有符号已输出完毕

    // ---- 显示数据 (40-bit, 兼容 time_display) ----
    wire [39:0] para_out;
    
    // 将 2-bit 符号打包为 40-bit (每 20 个符号, 高位先出)
    // 此处简单显示: 高 8bit = sym_out 重复, 兼容 time_display 格式
    // 实际 time_display 只显示高 32bit
    // 不兼容 time_display, 改为直接 LED 指示
    wire [7:0] sym_disp;
    assign sym_disp = {4'd0, sym_out};

    //---- 文件读取 ----
    initial begin
        num_syms = 0;
        fd = $fopen(SYM_FILE, "r");
        if (fd == 0) begin
            fd = $fopen("../../../matlab/edrsym.txt", "r");
        end
        if (fd == 0) begin
            $display("ERROR: Cannot open %s", SYM_FILE);
            num_syms = 0;
        end else begin
            while (!$feof(fd) && num_syms < MAX_SYMS) begin
                scan_ret = $fscanf(fd, "%d", sym_mem[num_syms]);
                if (scan_ret == 1) begin
                    num_syms = num_syms + 1;
                end
            end
            $fclose(fd);
            $display("Read %0d symbols from %s", num_syms, SYM_FILE);
        end
    end

    //---- 符号时序控制 (1MHz) ----
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sym_cnt <= 4'd0;
            sym_idx <= 9'd0;
            sym_en_reg <= 1'b0;
            sym_in_reg <= 2'b00;
            sym_seq_done <= 1'b0;
        end else begin
            if (sym_cnt == 4'd15) begin
                sym_cnt <= 4'd0;
                // 输出下一个符号
                if (!sym_seq_done && sym_idx < num_syms) begin
                    sym_en_reg <= 1'b1;
                    sym_in_reg <= sym_mem[sym_idx];
                    sym_idx <= sym_idx + 9'd1;
                    if (sym_idx == num_syms - 1) begin
                        sym_seq_done <= 1'b1;
                    end
                end else begin
                    sym_en_reg <= 1'b0;
                end
            end else begin
                sym_cnt <= sym_cnt + 4'd1;
                sym_en_reg <= 1'b0;
            end
        end
    end

    //---- pi/4-DQPSK 调制 ----
    qpsk_mod qpsk_mod_inst
    (
        .clk        (clk        ),
        .rst_n      (rst_n      ),
        .sym_in     (sym_in_reg ),
        .sym_en     (sym_en_reg ),
        .qpsk       (qpsk       )
    );

    //---- pi/4-DQPSK 解调 ----
    qpsk_demod
    qpsk_demod_inst
    (
        .clk        (clk        ),
        .rst_n      (rst_n      ),
        .qpsk       (qpsk       ),
        .sym_out    (sym_out    ),
        .sym_valid  (sym_valid  )
    );

    //---- 数码管显示 (显示解调符号) ----
    // 将 2-bit 符号打包为 40-bit 给 time_display
    // 格式: [39:32]=HEADER, [31:24]=symbol count high, ...
    // 简化为直接显示解调符号值
    assign para_out = {8'hcc, 24'd0, sym_disp};

    time_display time_display_inst
    (
        .clk        (clk    ),
        .rst_n      (rst_n  ),
        .dat_i      (para_out),
        .sel        (sel    ),
        .dig        (dig    )
    );

endmodule