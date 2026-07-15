`timescale 1ns / 1ps
module tb_clk_gen();

    reg         clk         ;
    reg         rst_n       ;
    
    wire    [7:0]     s_dec ;
    wire    [7:0]     m_dec ;
    wire    [7:0]     h_dec ;
    
    
    initial begin
        clk = 1'b1;
        rst_n <= 1'b0;
        
        #300
        rst_n <= 1'b1;
    end

    always #31.250 clk = ~clk;  // 16MHz时钟 (period=62.5ns)


    clk_gen
    #(.CNT_MAX(26'd15)) // 仿真加速: 16个时钟周期即溢出
    clk_gen_inst
    (
        .clk        (clk    ),
        .rst_n      (rst_n  ),

        .s_dec      (s_dec  ),
        .m_dec      (m_dec  ),
        .h_dec      (h_dec  )
        );
endmodule