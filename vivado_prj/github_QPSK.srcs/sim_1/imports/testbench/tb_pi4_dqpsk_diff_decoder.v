`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// pi/4-DQPSK 差分解码器 测试 (16MHz)
//////////////////////////////////////////////////////////////////////////////////
module tb_pi4_dqpsk_diff_decoder();
    reg         clk     ;
    reg         rst_n   ;
    reg [14:0]  data_I  ;
    reg [14:0]  data_Q  ;
    reg         sync_flag;

    wire        ser_o   ;
    wire        bit_valid;

    reg [3:0]   state;
    reg [4:0]   timer;
    
    initial begin
        clk = 1'b1;
        rst_n <= 1'b0;
        data_I <= 15'd0;
        data_Q <= 15'd0;
        sync_flag <= 1'b0;
        state <= 4'd0;
        timer <= 5'd0;
    #200
        rst_n <= 1'b1;
    end
    
    always #31.250 clk = ~clk;  // 16MHz

    // 产生测试序列: 每16个时钟周期产生一次sync_flag和新的I/Q数据
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer <= 5'd0;
            sync_flag <= 1'b0;
            state <= 4'd0;
        end else begin
            sync_flag <= 1'b0;
            if (timer == 5'd15) begin
                timer <= 5'd0;
                sync_flag <= 1'b1;
                state <= state + 4'd1;
            end else begin
                timer <= timer + 5'd1;
            end
        end
    end
    
    // 模拟符号序列 (π/4-DQPSK dibit = 00 重复)
    // 绝对相位: 0°,45°,90°,135°,180°,225°,270°,315°
    always @ (posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_I <= 15'd0;
            data_Q <= 15'd0;
        end else if (sync_flag) begin
            case (state[2:0])
                3'd0: begin data_I <=  15'd16256; data_Q <=  15'd0;     end
                3'd1: begin data_I <=  15'd11520; data_Q <=  15'd11520; end
                3'd2: begin data_I <=  15'd0;     data_Q <=  15'd16256; end
                3'd3: begin data_I <= -15'd11520; data_Q <=  15'd11520; end
                3'd4: begin data_I <= -15'd16256; data_Q <=  15'd0;     end
                3'd5: begin data_I <= -15'd11520; data_Q <= -15'd11520; end
                3'd6: begin data_I <=  15'd0;     data_Q <= -15'd16256; end
                3'd7: begin data_I <=  15'd11520; data_Q <= -15'd11520; end
            endcase
        end
    end
    
    pi4_dqpsk_diff_decoder pi4_dqpsk_diff_decoder_inst
    (
        .clk        (clk        ),
        .rst_n      (rst_n      ),
        .data_I     (data_I     ),
        .data_Q     (data_Q     ),
        .sync_flag  (sync_flag  ),
        .ser_o      (ser_o      ),
        .bit_valid  (bit_valid  )
    );

endmodule