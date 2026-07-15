`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_qpsk_mod - 从 matlab/edrsym.txt 读取符号, 送入 qpsk_mod 调制 (2-bit 符号接口)
//
// edrsym.txt: 每行一个 dibit 值 (0/1/2/3)
//////////////////////////////////////////////////////////////////////////////////
module tb_qpsk_mod();
    reg         clk     ;
    reg         rst_n   ;
    reg [1:0]   sym_in  ;
    reg         sym_en  ;

    wire [27:0] qpsk    ;

    // 文件读取
    reg [1:0]   sym_mem [0:255];
    integer     num_syms;
    integer     fd, scan_ret, i;

    // 符号时序: 每16个clk输出一个符号 (1MHz)
    reg [3:0]   cnt;
    reg [8:0]   sym_idx;

    initial begin
        clk      = 1'b1;
        rst_n    = 1'b0;
        sym_in   = 2'b00;
        sym_en   = 1'b0;
        cnt      = 4'd0;
        sym_idx  = 9'd0;
        num_syms = 0;

        // 读取 edrsym.txt
        fd = $fopen("edrsym.txt", "r");
        if (fd == 0) begin
            fd = $fopen("../../../matlab/edrsym.txt", "r");
        end
        if (fd == 0) begin
            $display("ERROR: Cannot open edrsym.txt");
            $finish;
        end

        while (!$feof(fd) && num_syms < 256) begin
            scan_ret = $fscanf(fd, "%d", sym_mem[num_syms]);
            if (scan_ret == 1) begin
                num_syms = num_syms + 1;
            end
        end
        $fclose(fd);
        $display("Read %0d symbols from edrsym.txt", num_syms);

        #80;
        rst_n = 1'b1;
    end

    // 16MHz 时钟
    always #31.250 clk = ~clk;

    // 符号时序: 每16周期输出一个符号
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 4'd0;
            sym_idx <= 9'd0;
            sym_en  <= 1'b0;
            sym_in  <= 2'b00;
        end else begin
            sym_en <= 1'b0;
            if (cnt == 4'd15) begin
                cnt <= 4'd0;
                if (sym_idx < num_syms) begin
                    sym_en  <= 1'b1;
                    sym_in  <= sym_mem[sym_idx];
                    sym_idx <= sym_idx + 9'd1;
                end
            end else begin
                cnt <= cnt + 4'd1;
            end
        end
    end

    // DUT: QPSK 调制器 (2-bit 符号接口)
    qpsk_mod qpsk_mod_inst
    (
        .clk        (clk    ),
        .rst_n      (rst_n  ),
        .sym_in     (sym_in ),
        .sym_en     (sym_en ),
        .qpsk       (qpsk   )
    );

endmodule