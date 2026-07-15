`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// pi/4-DQPSK Mapper 测试 (2-bit 符号接口)
//////////////////////////////////////////////////////////////////////////////////
module tb_pi4_dqpsk_mapper();
    reg         clk     ;
    reg         rst_n   ;
    reg [1:0]   sym_in  ;
    reg         sym_en  ;
    
    wire [7:0]  I       ;
    wire [7:0]  Q       ;
    wire        sym_valid;
    
    reg [1:0]   test_syms [0:39];
    reg [3:0]   cnt;
    reg [5:0]   sym_idx;
    integer     i;
    
    initial begin
        clk = 1'b1;
        rst_n <= 1'b0;
        sym_in <= 2'b00;
        sym_en <= 1'b0;
        cnt <= 4'd0;
        sym_idx <= 6'd0;
        
        // 测试符号序列: 混合 4 种 dibit
        for (i = 0; i < 40; i = i + 1) begin
            test_syms[i] = i[1:0];  // 0,1,2,3 循环
        end
        
    #100
        rst_n <= 1'b1;
    end
    
    always #31.250 clk = ~clk;  // 16MHz
    
    // 符号时序: 每16周期输出一个符号
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 4'd0;
            sym_idx <= 6'd0;
            sym_en <= 1'b0;
        end else begin
            sym_en <= 1'b0;
            if (cnt == 4'd15) begin
                cnt <= 4'd0;
                if (sym_idx < 40) begin
                    sym_en <= 1'b1;
                    sym_in <= test_syms[sym_idx];
                    sym_idx <= sym_idx + 6'd1;
                end
            end else begin
                cnt <= cnt + 4'd1;
            end
        end
    end
    
    pi4_dqpsk_mapper pi4_dqpsk_mapper_inst
    (
        .clk        (clk        ),
        .rst_n      (rst_n      ),
        .sym_in     (sym_in     ),
        .sym_en     (sym_en     ),
        .I          (I          ),
        .Q          (Q          ),
        .sym_valid  (sym_valid  )
    );

endmodule