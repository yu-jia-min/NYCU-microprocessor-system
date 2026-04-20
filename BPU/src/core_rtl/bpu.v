
// verilog_lint: waive-start
// designing
`timescale 1ns / 1ps

`include "aquila_config.vh"

module bpu #( parameter ENTRY_NUM = 128, parameter XLEN = 32 )      //var
(
    // System signals
    input               clk_i,
    input               rst_i,
    input               stall_i,

    // from Program_Counter
    input  [XLEN-1 : 0] pc_i, // Addr of the next instruction to be fetched.

    // from Decode
    // 其實這是exe的 只是他被延後了一下
    input               is_jal_i,
    input               is_cond_branch_i,
    input  [XLEN-1 : 0] dec_pc_i, // Addr of the instr. just processed by decoder.

    // from Execute
    input               exe_is_branch_i,
    input               branch_taken_i,
    input               branch_misprediction_i,
    input  [XLEN-1 : 0] branch_target_addr_i,

    // to Program_Counter
    output              branch_hit_o,
    output              branch_decision_o,
    output [XLEN-1 : 0] branch_target_addr_o
);
localparam integer NBITS = $clog2(ENTRY_NUM);

//tag
localparam  n1 = 4;     // var
localparam  n2 = 8;
localparam  n3 = 16;
localparam  n4 = 32;

wire [n1-1:0] tag1;
reg [n1-1:0] tag1_d;
reg [n1-1:0] tag1_dd;
// 00001 00001 00000
// 00010 00010 00000
assign tag1 = pc_i[n1-1:0]^(~h[n1+3:4])+h[n1-1:0];      //var
//assign tag1 = pc_i[n1-1:0]^(~h[n1-1:0]);
wire [n1-1:0] t1_tag;  //for read

wire [n2-1:0] tag2;
reg [n2-1:0] tag2_d;
reg [n2-1:0] tag2_dd;
assign tag2 = pc_i[n2-1:0]^(~h[n2-1:0]);
wire [n2-1:0] t2_tag;  //for read

wire [n3-1:0] tag3;
reg [n3-1:0] tag3_d;
reg [n3-1:0] tag3_dd;
assign tag3 = pc_i[n3-1:0]^(~h[n3-1:0]);
wire [n3-1:0] t3_tag;  //for read

wire [n4-1:0] tag4;
reg [n4-1:0] tag4_d;
reg [n4-1:0] tag4_dd;
assign tag4 = pc_i[n4-1:0]^(~h[n4-1:0]);
wire [n4-1:0] t4_tag;  //for read

//=======================

reg  [1 : 0]            branch_likelihood0[ENTRY_NUM-1 : 0];
reg  [2 : 0]            branch_likelihood[4:1][ENTRY_NUM-1 : 0];
reg  [3:0]              u[4:1][ENTRY_NUM-1 : 0];
reg [15:0]              u_counter;

reg  [127:0] h;  //history
reg [4:1] tag_enable;
wire [4:1] tage_hit;    //hit table
reg [4:1] tage_hit_d,tage_hit_dd; 
wire [NBITS-1:0] index;
reg [NBITS-1:0] index_d;
reg [NBITS-1:0] index_dd;
assign index = (pc_i ^ h);  //高位元自動忽視 overflow
reg [2:0]   a_d,b_d,decision_d,
            a_dd,b_dd,decision_dd;

wire [NBITS-1 : 0]      read_addr;
wire [NBITS-1 : 0]      write_addr;
wire [XLEN-1 : 0]       branch_inst_tag;
wire                    we;
reg                     BHT_hit_ff, BHT_hit;

// "we" is enabled to add a new entry to the BHT table when
// the decoded branch instruction is not in the BHT.
// CY Hsiang 0220_2020: added "~stall_i" to "we ="
assign we = ~stall_i & (is_cond_branch_i | is_jal_i) & !BHT_hit;

//fetch
assign read_addr = pc_i[NBITS+1 : 2];
assign write_addr = dec_pc_i[NBITS+1 : 2];


//exe
integer idx;
integer i,t;
always @(posedge clk_i)
begin
    if (rst_i)
    begin
        h<=1;
        u_counter <= 0;
        tag_enable <= 0;
        for (idx = 0; idx < ENTRY_NUM; idx = idx + 1) begin
            branch_likelihood0[idx] <= 2'b0;
            for(i=1;i<5;i=i+1)begin
                branch_likelihood[i][idx] <= 3'b011;
                u[i][idx] <= 3'b000;
            end
        end
    end
    else if (stall_i)
    begin
        h<=h;
        u_counter <= u_counter;
        for (idx = 0; idx < ENTRY_NUM; idx = idx + 1)begin
            branch_likelihood0[idx] <= branch_likelihood0[idx];
            for(i=1;i<5;i=i+1)begin
                branch_likelihood[i][idx] <= branch_likelihood[i][idx];
                u[i][idx] <= u[i][idx];
            end
        end
    end
    else
    begin
        // h、u_counter
        if (!stall_i && exe_is_branch_i) begin
            h <= {h[30:0], branch_taken_i};
        end
        if(u_counter == 16'h8000) //2^15
            u_counter <= 0;
        else u_counter <= u_counter+1;
        // hit_table_dd全為0 | (最長的2個hit中的 都預測錯誤) -> 分配new entry
        if(u_counter!=0) begin
            if((tage_hit_dd==0 || branch_likelihood[a_dd][index_dd][2]!=branch_taken_i
                || branch_likelihood[b_dd][index_dd][2]!=branch_taken_i)
                && (is_cond_branch_i | is_jal_i))begin //要真的是branch instr才分配
                //tage miss
                //都沒有tage table hit 或 ab當時都預測錯誤 -->分配新entry
                if(a_dd!=4)begin    //如果a==4的話就到底了 也不能分配
                    // at a_dd+1
                    if(u[a_dd+1][index_dd]!=0) begin
                        u[a_dd+1][index_dd]<=u[a_dd+1][index_dd]-1; //下一個沒位子allocate
                        for(idx=1;idx<5;idx=idx+1)begin
                            tag_enable[idx]<=0;
                        end
                    end
                    else begin  //下一個可以allocate
                        u[a_dd+1][index_dd]<=0;
                        branch_likelihood[a_dd+1][index_dd]<=branch_taken_i? 3'b100 : 3'b011;
                        // 寫tag到ram table 
                        tag_enable[a_dd+1]<=1;
                    end
                end
            end
            else begin
                //tag enble =0
                for(idx=1;idx<5;idx=idx+1)begin
                    tag_enable[idx]<=0;
                end
            end

            if (exe_is_branch_i) begin
                for(i=1; i<5; i=i+1) begin//只要有人hit到就要更新他的u、likelihood
                    if(tage_hit_dd[i]==1) begin  //地i個table hit 到了
                        if(branch_likelihood[i][index_dd][2]==branch_taken_i) begin //預測對嗎 yes
                            if(u[i][index_dd]!=5) u[i][index_dd]<=u[i][index_dd]+1;
                            //branch_likelihood
                            if(branch_likelihood[i][index_dd]!=3'b111) 
                                branch_likelihood[i][index_dd]<=branch_likelihood[i][index_dd]+1;
                        end
                        else begin //預測對嗎 no
                            if(u[i][index_dd]!=0) u[i][index_dd]<=u[i][index_dd]-1;
                            //branch_likelihood
                            if(branch_likelihood[i][index_dd]!=0) 
                                branch_likelihood[i][index_dd]<=branch_likelihood[i][index_dd]-1;

                        end
                    end
                end
            end
        end
        else begin
            for(i=1; i<5; i=i+1)begin
                for(idx=0;idx<ENTRY_NUM;idx=idx+1) begin
                    u[i][idx]<=0;
                end
            end
        end

        //bimodal (branch_likelihood0)
        if (we) // Execute the branch instruction for the first time.
        begin   // bimodal bht miss
            branch_likelihood0[write_addr] <= {branch_taken_i, branch_taken_i};
        end
        else if (exe_is_branch_i)
        begin
            case (branch_likelihood0[write_addr])
                2'b00:  // strongly not taken
                    if (branch_taken_i)
                        branch_likelihood0[write_addr] <= 2'b01;
                    else
                        branch_likelihood0[write_addr] <= 2'b00;
                2'b01:  // weakly not taken
                    if (branch_taken_i)
                        branch_likelihood0[write_addr] <= 2'b11;
                    else
                        branch_likelihood0[write_addr] <= 2'b00;
                2'b10:  // weakly taken
                    if (branch_taken_i)
                        branch_likelihood0[write_addr] <= 2'b11;
                    else
                        branch_likelihood0[write_addr] <= 2'b00;
                2'b11:  // strongly taken
                    if (branch_taken_i)
                        branch_likelihood0[write_addr] <= 2'b11;
                    else
                        branch_likelihood0[write_addr] <= 2'b10;
            endcase
        end
    end
end

// ===========================================================================
//  Branch History Table (BHT). Here, we use a direct-mapping cache table to
//  store branch history. Each entry of the table contains two fields:
//  the branch_target_addr and the PC of the branch instruction (as the tag).
// Branch Target Buffer
distri_ram #(.ENTRY_NUM(ENTRY_NUM), .XLEN(XLEN*2))
BPU_BHT(    //btb ram
    .clk_i(clk_i),
    //.we_i((!stall_i) & exe_is_branch_i & branch_taken_i),   //這裡有改
    .we_i(we),   
    .write_addr_i(write_addr),  
    .read_addr_i(read_addr),    

    .data_i({branch_target_addr_i, dec_pc_i}), // Input is not used when  is 0.
    .data_o({branch_target_addr_o, branch_inst_tag})    
    // branch_target_addr_o 當時要跳去的地方 : target_addr
    //branch_inst_tag 當時的pc
);

reg [NBITS-1:0] index_ddd;
reg [n1-1:0] tag1_ddd;
reg [n2-1:0] tag2_ddd;
reg [n3-1:0] tag3_ddd;
reg [n4-1:0] tag4_ddd;

always @ (posedge clk_i)
begin
    if (rst_i) begin
        index_ddd<=0;
        tag1_ddd<= 0;
        tag2_ddd<= 0;
        tag3_ddd<= 0;
        tag4_ddd<= 0;
    end
    if (!stall_i) begin
        index_ddd<=index_dd;
        tag1_ddd<= tag1_dd;
        tag2_ddd<= tag2_dd;
        tag3_ddd<= tag3_dd;
        tag4_ddd<= tag4_dd;
    end
end

distri_ram #(.ENTRY_NUM(ENTRY_NUM), .XLEN(n1))
table1(    //btb ram
    .clk_i(clk_i),
    .we_i(tag_enable[1]),
    .write_addr_i(index_ddd),  
    .read_addr_i(index),    

    .data_i({tag1_ddd}), 
    .data_o({t1_tag})   //if t1_tag==tag1 -->hit
);

distri_ram #(.ENTRY_NUM(ENTRY_NUM), .XLEN(n2))
table2(    //btb ram
    .clk_i(clk_i),
    .we_i(tag_enable[2]),
    .write_addr_i(index_ddd),  
    .read_addr_i(index),    

    .data_i({tag2_ddd}), 
    .data_o({t2_tag})   
);

distri_ram #(.ENTRY_NUM(ENTRY_NUM), .XLEN(n3))
table3(    //btb ram
    .clk_i(clk_i),
    .we_i(tag_enable[3]),
    .write_addr_i(index_ddd),  
    .read_addr_i(index),    

    .data_i({tag3_ddd}), 
    .data_o({t3_tag})   
);

distri_ram #(.ENTRY_NUM(ENTRY_NUM), .XLEN(n4))
table4(    //btb ram
    .clk_i(clk_i),
    .we_i(tag_enable[4]),
    .write_addr_i(index_ddd),  
    .read_addr_i(index),    

    .data_i({tag4_ddd}), 
    .data_o({t4_tag})   
);


// Delay the BHT hit flag at the Fetch stage for two clock cycles (plus stalls)
// such that it can be reused at the Execute stage for BHT update operation.
always @ (posedge clk_i)
begin
    if (rst_i) begin
        BHT_hit_ff <= 1'b0;
        BHT_hit <= 1'b0;
    end
    else if (!stall_i) begin
        index_d<=index;
        index_dd<=index_d;
        tag1_d<=tag1;
        tag1_dd<=tag1_d;
        tag2_d<=tag2;
        tag2_dd<=tag2_d;
        tag3_d<=tag3;
        tag3_dd<=tag3_d;
        tag4_d<=tag4;
        tag4_dd<=tag4_d;
        BHT_hit_ff <= branch_hit_o;
        BHT_hit <= BHT_hit_ff;
    end
end

// ===========================================================================
//  Outputs signals 
//  (fetch)
assign branch_hit_o = (branch_inst_tag == pc_i);//||(|tage_hit);
assign tage_hit[1] = (t1_tag==tag1);    //t1_tag old in btb  , tag1:now tag to compare
assign tage_hit[2] = (t2_tag==tag2);
assign tage_hit[3] = (t3_tag==tag3);
assign tage_hit[4] = (t4_tag==tag4);

always @ (posedge clk_i)
begin
    if (rst_i) begin
        tage_hit_d<=0;
        tage_hit_dd<=0;
    end
    else if (!stall_i) begin
        tage_hit_d<=tage_hit;
        tage_hit_dd<=tage_hit_d;
    end
end

integer ii,a,b,decision,final_decision;    //a b desision = 1-4
// a:最長 有hit到的table
always @(*)begin    //有hit中的table中 最長的兩個 看誰u比較大就選誰的 likelihood
    a=0;b=0;
    for (ii = 4; ii > 0; ii = ii - 1) begin
        if (tage_hit[ii]) begin
            if (a == 0)
                a = ii;
            else if (b ==0)
                b = ii;
        end
    end
    decision =  (a!=0 && b!=0)? ((u[a][index]>=u[b][index])?  a:b):
                (a!=0)? a:
                (b!=0)? b: 0;
    final_decision = u[decision][index]>=3? decision:0;
end
assign branch_decision_o = (final_decision==0)?  branch_likelihood0[read_addr][1]:
                                            branch_likelihood[final_decision][index][2];

reg decision_diff_d,decision_diff_dd;
reg final_decision_d,final_decision_dd;
wire decision_diff;
wire wrong_and_different;
wire tage_wrong_and_different;
assign decision_diff = branch_decision_o!=branch_likelihood0[read_addr][1]; //是tage且和bimodal預測不同時
assign wrong_and_different = decision_diff_dd && branch_misprediction_i;
assign tage_wrong_and_different = decision_diff_dd && branch_misprediction_i && (final_decision_dd!=0);

(* mark_debug = "true", keep = "true" *) reg [31:0] tage_mispredict_table1;
(* mark_debug = "true", keep = "true" *) reg [31:0] tage_mispredict_table2;
(* mark_debug = "true", keep = "true" *) reg [31:0] tage_mispredict_table3;
(* mark_debug = "true", keep = "true" *) reg [31:0] tage_mispredict_table4;

(* mark_debug = "true", keep = "true" *) wire [2:0] tage_wrong_and_diff_table 
= tage_wrong_and_different? final_decision_dd:0; //tage預測錯誤時是用哪一個table

(* mark_debug = "true", keep = "true" *) reg [31:0] different_time;
(* mark_debug = "true", keep = "true" *) reg [63:0] hit_time,miss_time;
(* mark_debug = "true", keep = "true" *) reg [31:0] tage_wrong_jump; //tage mispredict時是要跳 的次數
(* mark_debug = "true", keep = "true" *) reg [31:0] tage_right_jump; //tage 正確預測時是要跳 的次數
(* mark_debug = "true", keep = "true" *) reg [31:0] tage_wrong_time,bimodal_wrong_time;
(* mark_debug = "true", keep = "true" *) reg [63:0] tage_use_time, bimodal_use_time;
(* mark_debug = "true", keep = "true" *) reg [31:0] same_wrong;  //兩個預測相同 但是都錯了
(* mark_debug = "true", keep = "true" *) wire [63:0] mispredict = same_wrong + bimodal_wrong_time + tage_wrong_time;
(* mark_debug = "true", keep = "true" *) reg [63:0] branch;
always @ (posedge clk_i) begin
    if (rst_i) begin
        tage_mispredict_table1<=0;
        tage_mispredict_table2<=0;
        tage_mispredict_table3<=0;
        tage_mispredict_table4<=0;
        different_time<=0;
        branch<=0;
        hit_time <=0;
        miss_time<=0;
        tage_wrong_jump<=0;
        tage_right_jump<=0;
        same_wrong<=0;
        bimodal_wrong_time<=0;
        tage_wrong_time   <=0;
        bimodal_wrong_time<=0;
        tage_use_time    <=0;
        bimodal_use_time<=0;
        tage_wrong_time<=0;
        decision_diff_d<=0;
        decision_diff_dd<=0;
        a_d<=0;
        b_d<=0;
        final_decision_d<=0;
        a_dd<=0;
        b_dd<=0;
        final_decision_dd<=0;
    end
    else if (stall_i) begin
        tage_mispredict_table1<=tage_mispredict_table1;
        tage_mispredict_table2<=tage_mispredict_table2;
        tage_mispredict_table3<=tage_mispredict_table3;
        tage_mispredict_table4<=tage_mispredict_table4;
        different_time<=different_time;
        branch<=branch;
        hit_time <=hit_time ;
        miss_time<=miss_time;
        tage_wrong_jump<=tage_wrong_jump;
        tage_right_jump<=tage_right_jump;
        same_wrong<=same_wrong;
        tage_wrong_time   <=tage_wrong_time;
        bimodal_wrong_time<=bimodal_wrong_time;
        tage_use_time    <=tage_use_time;
        bimodal_use_time<=bimodal_use_time;
        bimodal_wrong_time<=bimodal_wrong_time;
        tage_wrong_time<=tage_wrong_time;
        decision_diff_d <=decision_diff_d ;
        decision_diff_dd<=decision_diff_dd;
        a_d<=a_d;
        b_d<=b_d;
        final_decision_d<=final_decision_d;
        a_dd<=a_dd;
        b_dd<=b_dd;
        final_decision_dd<=final_decision_dd;
    end
    else begin  
        case(tage_wrong_and_diff_table)
            1:tage_mispredict_table1<=tage_mispredict_table1+1;
            2:tage_mispredict_table2<=tage_mispredict_table2+1;
            3:tage_mispredict_table3<=tage_mispredict_table3+1;
            4:tage_mispredict_table4<=tage_mispredict_table4+1;
        endcase
        if(decision_diff)
            different_time<=different_time+1;
        if(exe_is_branch_i)
            branch<=branch+1;
        if(exe_is_branch_i && BHT_hit) 
            hit_time<=hit_time+1;
        else if(exe_is_branch_i)
            miss_time<=miss_time+1;
        if(tage_wrong_and_different && branch_taken_i && BHT_hit) 
            tage_wrong_jump<=tage_wrong_jump+1;  
            //tage mispredict時是要跳
        if(final_decision_dd!=0 && !branch_misprediction_i && branch_taken_i && BHT_hit) 
            tage_right_jump<=tage_right_jump+1;   
            //tage正確預測時是要跳
        if(final_decision_dd==0 && exe_is_branch_i && BHT_hit)
            bimodal_use_time<=bimodal_use_time+1;  
            //bimodal用了幾次
        if(final_decision_dd!=0 && exe_is_branch_i && BHT_hit)
            tage_use_time<=tage_use_time+1;    
            //tage用了幾次
        if(!decision_diff_dd && branch_misprediction_i && BHT_hit) 
            same_wrong<=same_wrong+1;   
            //兩個預測相同 但是都錯了
        if(tage_wrong_and_different==1 && BHT_hit)
            tage_wrong_time<=tage_wrong_time+1; 
             //最後選tage 他跟bimodal選不一樣 而且tage錯了
        if(wrong_and_different==1 && !tage_wrong_and_different && BHT_hit)
            bimodal_wrong_time<=bimodal_wrong_time+1;
            // bimodal 單獨預測錯誤的次數
        decision_diff_d <=decision_diff ;
        decision_diff_dd<=decision_diff_d;
        a_d<=a;
        b_d<=b;
        final_decision_d<=final_decision;
        a_dd<=a_d;
        b_dd<=b_d;
        final_decision_dd<=final_decision_d;
    end
end

endmodule

// verilog_lint: waive-stop