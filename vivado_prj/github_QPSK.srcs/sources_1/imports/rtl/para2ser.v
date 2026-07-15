//////////////////////////////////////////////////////////////////////////////////
// 并串转换 - 40bit并行 -> 串行输出
// 高位先出 (MSB first)
// EDR2: clk=16MHz, DIV=8, 比特率=16MHz/8=2Mbps
//////////////////////////////////////////////////////////////////////////////////
module para2ser
    #(parameter DIV = 4'd8)  // 16MHz / 8 = 2Mbps bit rate
    (
        input wire          clk         ,  // 16MHz
        input wire          rst_n       ,
        input wire  [39:0]  para_i      ,
        
        output reg          ser_o       ,
        output reg          bit_valid     // 比特有效 (1周期脉冲)
    );
    
    // 分频计数，DIV=8, 需要3bit
    reg [2:0]   div_cnt;  
    
    // 记录当前输出bit位置 (0~39)
    reg [5:0]   bit_cnt;
    
    // div_cnt
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 3'd0;
        end else if (div_cnt == (DIV - 1)) begin
            div_cnt <= 3'd0;
        end else begin
            div_cnt <= div_cnt + 3'd1;
        end
    end
    
    // bit_cnt
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 6'd0;
        end else if ((bit_cnt == 6'd39) && (div_cnt == (DIV - 1))) begin
            bit_cnt <= 6'd0;
        end else if (div_cnt == (DIV - 1)) begin
            bit_cnt <= bit_cnt + 6'd1;
        end
    end
    
    // ser_o & bit_valid
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ser_o     <= 1'b0;
            bit_valid <= 1'b0;
        end else begin
            if (div_cnt == (DIV - 1)) begin
                ser_o     <= para_i[39 - bit_cnt];
                bit_valid <= 1'b1;
            end else begin
                bit_valid <= 1'b0;
            end
        end
    end
    
endmodule