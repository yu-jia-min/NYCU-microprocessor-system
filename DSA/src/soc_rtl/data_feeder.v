//feeder
// 給他你是a/b/c 、 你抓好的value、 ready了嗎(她才可以取值)
`timescale 1ns / 1ps
`include "aquila_config.vh"

module data_feeder #(parameter XLEN = 32) (
    input  wire                     clk,
    //input  wire                     rst_i,

    // from aquila (CPU -> feeder)
    input  wire dev_strobe,
    input  wire [XLEN-1:0] dev_addr,
    input  wire dev_we,
    input  wire [XLEN-1:0] dev_din,
    input  wire dsa_sel,
    
    // to aquila (feeder -> CPU)
    output reg [XLEN-1:0]          dsa_dout,
    output reg                     dsa_ready,

    // to floating point IP
    output reg                      fp_valid,
    output wire [XLEN-1:0]          a_data_o,
    output wire [XLEN-1:0]          b_data_o,
    output wire [XLEN-1:0]          c_data_o,

    // from floating point IP
    input  wire                     r_valid_i,
    input  wire [XLEN-1:0]          r_data_i
);
assign a_data_o = fc[2];
assign b_data_o = pw[pw_counter];
assign c_data_o = fc[1];

// fully: 32'hC400_0000  、 connected: 32'hC400_0004
reg [31:0] fc [4:0];
reg [31:0] fc0_r;  //fc的上一拍
reg fc0;
//fc[0]:control  fc[1]:c  "fc[2]:a"  fc[3]:b(要被換掉)  -> a*b+c
//更新後 fc[3]: inner_loop_iter(pw的週期)
reg [31:0] pw [191:0]; //in有到192個
reg [7:0] pw_counter;
always @(posedge clk) begin
    if(dev_strobe && dsa_sel) begin //存a w in control 和讀取
        if(dev_we) begin    //in
            if (dev_addr[31:12] == 20'hC4001) begin  // pw
                pw[(dev_addr-32'hC400_1000)/4] <= dev_din;
                pw_counter <= 8'hff;    //從0開始
                fc0 <= 0;
            end
            else begin
                fc[(dev_addr-32'hC400_0000)/4] <= dev_din; //一般資訊
                if((dev_addr-32'hC400_0000)/4 == 2) fc0 <= 1; //ppi
                else fc0 <= 0;
            end
        end
        else begin
            dsa_dout<=fc[(dev_addr-32'hC400_0000)/4];    //out
            fc0 <= 0;
        end
        dsa_ready<=1;
    end
    else begin 
        dsa_ready<=0;
        fc0 <= 0;
    end
    fc[4]<=pw_counter;

    fc0_r <= fc0;
    //開始計算 -> valid=1 for 1 cyc
    if(!fc0_r & fc0) begin 
        fc[0] <= 1;
        fp_valid <= 1;    //當fc[2]改變了: ppi賦值了
        if(pw_counter == fc[3]-1) pw_counter <= 0;
        else pw_counter <= pw_counter + 1;
    end
    else fp_valid <= 0;
    //算好了 r_valid=1
    if(r_valid_i) begin
        fc[1] <= r_data_i;
        fc[0] <= 0;
    end
end

endmodule
