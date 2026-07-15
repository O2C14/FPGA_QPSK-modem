`timescale 1ns / 1ps
module tb_qpsk_clk_top();
    reg         clk     ;
    reg         rst_n   ;
    
    wire [5:0]  sel     ;
    wire [7:0]  dig     ;

    
    initial begin
        clk = 1'b1;
        rst_n <= 1'b0;
    #30
        rst_n <= 1'b1;
    end
    
    always #31.250 clk = ~clk; // 16MHz时钟
    
    qpsk_clk_top
    #(
        .SYM_FILE("E:/CEVA_BT5.2/FPGA_QPSK-modem/matlab/edrsym.txt"),
        .MAX_SYMS(256)
    )
    qpsk_clk_top_inst
    (
        .clk            (clk    ),
        .rst_n          (rst_n  ),
        .sel            (sel    ),
        .dig            (dig    )
    );
endmodule