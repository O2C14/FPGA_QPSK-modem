`timescale 1ns / 1ps
module tb_data_valid();
    reg         clk         ;
    reg         rst_n       ;
    reg         ser_i       ;
    reg         sync_flag   ;
    reg [39:0]  data        ;
    
    wire        header_flag ;
    wire        valid_flag  ;
    wire [39:0] valid_data_o;
    
    integer i;
    
    initial begin
        clk = 1'b1;
        rst_n <= 1'b0;
        data <= 40'b1100_1100_0001_0111_0001_1000_0001_1001_0001_0100;
        sync_flag <= 1'b0;
        ser_i <= 1'b0;
    #2000
        rst_n <= 1'b1;
        for(i=0;i<=39;i=i+1) begin
            #500  // 比特间隔 = 500ns (2Mbps)
            ser_i <= data[39 - i]; // 高位先入
            sync_flag <= 1'b1;
            #62.5  // sync_flag持续一个16MHz周期
            sync_flag <= 1'b0;
        end
    end
    
    always #31.250 clk = ~clk;  // 16MHz
        
    
    data_valid 
    #(.HEADER(8'b1100_1100))
    valid_data_inst
    (
        .clk            (clk            ),
        .rst_n          (rst_n          ),
        .ser_i          (ser_i          ),
        .sync_flag      (sync_flag      ),
 
        .header_flag    (header_flag    ),
        .valid_flag     (valid_flag     ),
        .valid_data_o   (valid_data_o   )
    );

endmodule