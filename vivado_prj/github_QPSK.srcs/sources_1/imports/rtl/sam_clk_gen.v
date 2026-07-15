//////////////////////////////////////////////////////////////////////////////////
// 采样时序发生器 - 从16MHz系统时钟产生各速率控制使能
// 16MHz整数分频:
//   samp_en  : 16/1  = 16MHz (恒为1)
//   bit_en   : 16/8  = 2Mbps (EDR2 比特率)
//   sym_en   : 16/16 = 1MHz  (EDR2 符号率)
//////////////////////////////////////////////////////////////////////////////////
module sam_clk_gen(
        input wire          clk         ,  // 16MHz 主时钟
        input wire          rst_n       ,
        
        output reg          samp_en     ,  // 16MHz 采样使能 (1周期脉冲)
        output wire         mod_en      ,  // 未使用 (保持兼容)
        output reg          bit_en      ,  // 2Mbps 比特使能 (1周期脉冲)
        output reg          sym_en         // 1MHz  符号使能 (1周期脉冲)
    );
    
    // 16进制模计数器: 0~15
    reg [3:0] cnt;
    
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 4'd0;
        end else if (cnt == 4'd15) begin
            cnt <= 4'd0;
        end else begin
            cnt <= cnt + 4'd1;
        end
    end
    
    // 边沿检测产生 bit_en / sym_en 脉冲
    reg bit_toggle, sym_toggle;
    reg bit_toggle_d, sym_toggle_d;
    
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_toggle   <= 1'b0;
            sym_toggle   <= 1'b0;
            bit_toggle_d <= 1'b0;
            sym_toggle_d <= 1'b0;
        end else begin
            bit_toggle_d <= bit_toggle;
            sym_toggle_d <= sym_toggle;
            // 2Mbps: cnt[2:0]==3'b111 时翻转 (每8周期)
            if (cnt[2:0] == 3'b111)  bit_toggle <= ~bit_toggle;
            // 1MHz:  cnt==15 时翻转 (每16周期)
            if (cnt == 4'd15)         sym_toggle <= ~sym_toggle;
        end
    end
    
    assign mod_en = 1'b0;  // 未使用, 保持兼容
    
    // 使能输出 (1周期脉冲)
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            samp_en <= 1'b0;
            bit_en  <= 1'b0;
            sym_en  <= 1'b0;
        end else begin
            // 16MHz使能: 每个周期有效
            samp_en <= 1'b1;
            // 2Mbps使能: bit_toggle边沿
            bit_en  <= (bit_toggle != bit_toggle_d);
            // 1MHz使能: sym_toggle边沿
            sym_en  <= (sym_toggle != sym_toggle_d);
        end
    end
    
endmodule