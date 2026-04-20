`timescale 1ns / 1ps
// =============================================================================
//  Program : dcache.v
//  Author  : Jin-you Wu
//  Date    : Nov/01/2018
// -----------------------------------------------------------------------------
//  Description:
//  This module implements the L1 Data Cache with the following
//  properties:
//      4-way set associative
//      FIFO replacement policy
//      Write-back
//      Write allocate
// -----------------------------------------------------------------------------
//  Revision information:
//
//  Mar/03/2020, by Chih-Yu Hsiang:
//    Added AMO support.
//
//  Sep/24/2023, by Chun-Jen Tsai:
//    Modify the code to use distributed RAM to store VALID and DIRTY bits.
//    This modification significantly reduces the resource usage.
// -----------------------------------------------------------------------------
//  License information:
//
//  This software is released under the BSD-3-Clause Licence,
//  see https://opensource.org/licenses/BSD-3-Clause for details.
//  In the following license statements, "software" refers to the
//  "source code" of the complete hardware/software system.
//
//  Copyright 2019,
//                    Embedded Intelligent Systems Lab (EISL)
//                    Deparment of Computer Science
//                    National Chiao Tung Uniersity
//                    Hsinchu, Taiwan.
//
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its contributors
//     may be used to endorse or promote products derived from this software
//     without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
// =============================================================================
`include "aquila_config.vh"

module dcache
#(parameter XLEN = 32,
  parameter CACHE_SIZE = 4,
  parameter CLSIZE = `CLP    // Cache line size. 128 (一個block的size)
)
(
    /////////// System signals   ///////////////////////////////////////////////
    input                     clk_i, rst_i,

    /////////// Processor signals //////////////////////////////////////////////
    // cpu<->cache 一次都是一個word or byte
    input                     p_strobe_i,      // Processor request signal.
    input                     p_rw_i,          // 0 for read, 1 for write.
    input  [XLEN/8-1 : 0]     p_byte_enable_i, // Byte-enable signal.(只作用在那幾個byte 雖然傳是傳整個word)
    input  [XLEN-1 : 0]       p_addr_i,        // Memory addr of the request.(會用word為單位 都是4的倍數)
    input  [XLEN-1 : 0]       p_data_i,        // Data to main memory.
    output reg [XLEN-1 : 0]   p_data_o,        // Data from main memory.
    output                    p_ready_o,       // The cache data is ready.
    input                     p_flush_i,       // Cache flush request.

    /////////// External memory signals   //////////////////////////////////////
    // 一次都是整個block (128bit: 4byte)
    output reg                m_strobe_o,      // Cache request to memory.
    output reg [XLEN-1 : 0]   m_addr_o,        // Address of the request.
    output reg                m_rw_o,          // 0 for read, 1 for write.
    input  [CLSIZE-1 : 0]     m_data_i,        // Data from memory controller.(傳一整個block)
    output reg [CLSIZE-1 : 0] m_data_o,        // Cache data to memory controller.(傳一整個block)
    input                     m_ready_i,       // Data from memory is ready.(mem:我處理完了 你可以用了)

    /////////// Control signals to other caches   //////////////////////////////
    output reg                busy_flushing_o, // D-Cache is busy flushing(被 p_flush_i 控制)

    /////////// AMO signals      ///////////////////////////////////////////////(atomic)
    input                     p_is_amo_i,      // AMO request from core.
    input  [4 : 0]            p_amo_type_i,    // Type of AMO from core.
    output                    m_is_amo_o,      // AMO request to D-memory.
    output reg [4 : 0]        m_amo_type_o     // Type of AMO to D-memory.
);

//======added
(* mark_debug = "true", keep = "true" *) reg [31:0] write_times; //次數
(* mark_debug = "true", keep = "true" *) reg [31:0] read_times;
(* mark_debug = "true", keep = "true" *) reg [31:0] hit_times;   
(* mark_debug = "true", keep = "true" *) reg [31:0] miss_times;
(* mark_debug = "true", keep = "true" *) reg [63:0] write_cyc;   //花的latency
(* mark_debug = "true", keep = "true" *) reg [63:0] read_cyc;
(* mark_debug = "true", keep = "true" *) reg [63:0] hit_cyc; //永遠是1
(* mark_debug = "true", keep = "true" *) reg [63:0] miss_cyc;

reg p_strobe_r;
reg wc,rc,hc,mc;    
reg [3:0] h; // history (hit是1  miss是0)
(* mark_debug = "true", keep = "true" *) reg [31:0] hit_3;   //最近很長hit
(* mark_debug = "true", keep = "true" *) reg [31:0] miss_3;  //最近很長miss

always @ (posedge clk_i)    //次數
begin
    if(rst_i)begin
        write_times <= 0; 
        read_times  <= 0;
        hit_times   <= 0;
        miss_times  <= 0;
        p_strobe_r  <= 0;
        {wc,rc,mc} <= 0;
        h   <= 0;
        hit_3  <=0;
        miss_3  <=0;
    end
    else begin
        if (!busy_flushing_o && !p_flush_i && !p_is_amo_i && p_strobe_i) begin
            if(p_rw_i)begin
                write_times <= write_times + 1;
                wc<=1;
            end
            if(!p_rw_i)begin
                read_times <= read_times + 1;
                rc<=1;
            end
        end
        p_strobe_r <= (!busy_flushing_o && !p_flush_i && !p_is_amo_i && p_strobe_i);
        if (p_strobe_r) begin
            if(cache_hit) begin
                hit_times <= hit_times + 1;
                //hc<=1;
                if((h[0]+h[1]+h[2]+h[3]>=3))
                    hit_3 <= hit_3+1;
            end
            if(!cache_hit) begin
                miss_times <= miss_times + 1;
                mc<=1;
                if((h[0]+h[1]+h[2]+h[3]<=1))
                    miss_3 <= miss_3+1;
            end
            h <= {h[2:0],cache_hit};  //hit是1
            
        end
        if(p_ready_o)
            {wc,rc,mc} <= 0;
    end
end

always @(posedge clk_i)
begin 
    if(rst_i)begin
        write_cyc   <= 0; 
        read_cyc    <= 0;
        hit_cyc     <= 0;
        miss_cyc    <= 0;
    end
    if(wc)  write_cyc <= write_cyc + 1;
    if(rc)  read_cyc <= read_cyc + 1;
    //  if(hc)  hit_cyc <= 1;
    if(mc)  miss_cyc <= miss_cyc + 1;   //最後要在+1
end


//==========

//=======================================================
// Cache parameters
//=======================================================
localparam N_WAYS      = 4;
localparam N_LINES     = (CACHE_SIZE*1024*8) / (N_WAYS*CLSIZE);

localparam WAY_BITS    = $clog2(N_WAYS);
localparam BYTE_BITS   = $clog2(XLEN/8);    // 4(100)byte 
localparam WORD_BITS   = $clog2(CLSIZE/XLEN);   //一個block裡面有幾個word(第幾個word) 4word = 1block
localparam LINE_BITS   = $clog2(N_LINES);
localparam NONTAG_BITS = LINE_BITS + WORD_BITS + BYTE_BITS;
localparam TAG_BITS    = XLEN - NONTAG_BITS;

//=======================================================
// N-way associative cache signals
//=======================================================
wire                   way_hit[0 : N_WAYS-1];     // Cache-way hit flag.
reg  [WAY_BITS-1 : 0]  hit_index;                 // Decoded way_hit[] signal.
wire                   cache_hit;                 // Got a cache hit?
reg  [CLSIZE-1 : 0]    c_data_i;                  // Data to write into cache.
reg  [CLSIZE-1 : 0]    c_data_update;             // Updated cache data.
reg  [CLSIZE-1 : 0]    m_data_update;             // Updated memory data.
wire [CLSIZE-1 : 0]    c_block[0 : N_WAYS-1];     // Cache blocks from N cache way.
wire [CLSIZE-1 : 0]    c_data_hit;                // Data from the hit cache block.
reg                    cache_write[0 : N_WAYS-1]; // WE signal for a $ tag & block.
reg                    valid_write[0 : N_WAYS-1]; // WE signal for a $ valid bit.
reg                    dirty_write[0 : N_WAYS-1]; // WE signal for a $ dirty bit.
wire [TAG_BITS-1 : 0]  c_tag_o[0 : N_WAYS-1];     // Tag bits of current $ blocks.
wire                   c_valid_o[0 : N_WAYS-1];   // Validity of current $ blocks.
wire                   c_dirty_o[0 : N_WAYS-1];   // Dirtiness of current $ blocks.
reg  [LINE_BITS-1 : 0] init_count;                // Counter to initialize valid bits.

integer idx,x;


assign c_data_hit = c_block[hit_index];

//=======================================================
// FIFO replacement policy signals
//=======================================================
//reg  [WAY_BITS-1 : 0] FIFO_cnt[0 : N_LINES-1];   // Replace policy counter.
reg  [WAY_BITS-1 : 0] victim_sel;                // The victim cache select.

//=======================================================
// Cache line and tag calculations
//=======================================================
wire [WORD_BITS-1 : 0] line_offset; //(那個block中的第幾個word)
wire [LINE_BITS-1 : 0] line_index;
wire [TAG_BITS-1  : 0] tag;
wire [LINE_BITS-1 : 0] addr_sram;
reg  [XLEN-1 : 0]      p_addr_r;

assign line_offset = (p_strobe_i)? p_addr_i[WORD_BITS + BYTE_BITS - 1 : BYTE_BITS] : //(那個block中的第幾個word)
                                   p_addr_r[WORD_BITS + BYTE_BITS - 1 : BYTE_BITS];
assign line_index  = (p_strobe_i)? p_addr_i[NONTAG_BITS - 1 : WORD_BITS + BYTE_BITS] :
                                   p_addr_r[NONTAG_BITS - 1 : WORD_BITS + BYTE_BITS];
assign tag         = p_addr_r[XLEN - 1 : NONTAG_BITS];  // 因為bram要一個cyc之後才會拿資料出來

//=======================================================
// Processor and memory interface signals
//=======================================================

// Input signal from processor   //////////////////////////////////////////
reg [XLEN-1 : 0] datain_from_p;
reg              rw;                 // 0 is for read, 1 is for write
reg [ 3 : 0]     byte_enable_from_p; // Which bytes are written if (rw == 1)
reg              is_amo_reg;

// Output signal to processor
reg              p_ready_reg;

// Input data from memory /////////////////////////////////////////////////
wire [CLSIZE-1 : 0] m_data;
reg  [CLSIZE-1 : 0] m_data_r;

//=======================================================
// Control signals for flushing all cache blocks
//=======================================================
reg [LINE_BITS-1 : 0] N_LINES_cnt;
reg [WAY_BITS-1 : 0]  N_WAYS_cnt;
wire NeedtoWb = c_dirty_o[N_WAYS_cnt];
wire WbAllFinish = (N_LINES_cnt == N_LINES - 1 && N_WAYS_cnt == N_WAYS - 1);
reg WbAllFinish_r;

//=======================================================
// Cache Finite State Machine
//=======================================================
localparam Init             = 0,
           Idle             = 1,
           Analysis         = 2,
           WbtoMem          = 3,
           RdfromMem        = 4,
           WbtoMemAll       = 5,
           WbtoMemAllFinish = 6,
           RdAmo            = 7,
           RdAmoFinish      = 8;

// Cache controller state registers
reg [ 3 : 0] S;
reg [ 3 : 0] S_nxt;

//====================================================
// Cache Controller FSM
//====================================================
always @(posedge clk_i)
begin
    if (rst_i)
        S <= Init;
    else
        S <= S_nxt;
end

always @(*)
begin
    case (S)
        Init: // Multi-cycle initialization of the VALID bits memory.
            if (init_count < N_LINES - 1)
                S_nxt = Init;
            else
                S_nxt = Idle;
        Idle:
            if (p_strobe_i || p_flush_i)
                S_nxt = Analysis;
            else
                S_nxt = Idle;
        Analysis:
            if (busy_flushing_o)
                S_nxt = WbtoMemAll;
            else if (p_is_amo_i)
                S_nxt = (cache_hit & c_dirty_o[hit_index])? WbtoMem : RdAmo;
            else if (!cache_hit)
                S_nxt = (c_dirty_o[victim_sel])? WbtoMem : RdfromMem;
            else // cache hit and not amo
                S_nxt = Idle;
        WbtoMem:
            if (m_ready_i)
                S_nxt =  (p_is_amo_i)? RdAmo : RdfromMem;
            else
                S_nxt = WbtoMem;
        RdfromMem:
            if (m_ready_i)
                S_nxt = Idle;
            else
                S_nxt = RdfromMem;
        WbtoMemAll:
            if (NeedtoWb)
                if (m_ready_i)
                    S_nxt = WbtoMemAllFinish;
                else
                    S_nxt = WbtoMemAll;
            else
                S_nxt = WbtoMemAllFinish;
        WbtoMemAllFinish:
            S_nxt = (WbAllFinish_r)? Idle : WbtoMemAll;
        RdAmo:
            if (m_ready_i)
                S_nxt = RdAmoFinish;
            else
                S_nxt = RdAmo;
        RdAmoFinish:
            S_nxt = Idle;
        default:
            S_nxt = Idle;
    endcase
end

// Initialization of the valid bits to zeros upon reset.
always @ (posedge clk_i)
begin
    if (S == Init)
        init_count <= init_count + 1;
    else
        init_count <= {LINE_BITS{1'b0}};
end

// Check and see if any cache way has the matched memory block.
genvar a;
generate
    for (a = 0; a < N_WAYS; a = a + 1)
    begin
        assign way_hit[a] = (c_valid_o[a] && (c_tag_o[a] == tag))? 1 : 0;
    end
endgenerate
assign cache_hit  = (way_hit[0] || way_hit[1] || way_hit[2] || way_hit[3]);     // 改這裡(way)

always @(*)
begin
    case ( { way_hit[0], way_hit[1], way_hit[2], way_hit[3] } )     // 改這裡(way)
        4'b1000: hit_index = 0;
        4'b0100: hit_index = 1;
        4'b0010: hit_index = 2;
        4'b0001: hit_index = 3;
        default: hit_index = 0; // error: multiple-way hit!
    endcase
end
//--------------------------用lru修改
always @(posedge clk_i)
begin
    victim_sel <= lru_min; //回答他要選第幾個way
end

reg [2:0] lru[0 : N_LINES-1][0 : N_WAYS-1];   //0~7
always @(posedge clk_i)
begin
    if (rst_i)
        for (idx = 0; idx < N_LINES; idx = idx + 1) //0-line-1
            for (x = 0; x < N_WAYS; x = x + 1)  //0-3
                lru[idx][x]<=2;
    else if (S == RdfromMem && m_ready_i)   //miss 要從mem那裏抓東西進來了 更新條件  到最後1clk才會更新
        //miss 全部格都-1 (最少到0)  但是最小的設回2(他要變成新來的)
        for (x = 0; x < N_WAYS; x = x + 1) begin  //0-3
            if(lru[line_index][x]>0 && x!=lru_min)
                lru[line_index][x]<=lru[line_index][x]-1;
            else if(x==lru_min) 
                lru[line_index][x]<=2;
        end
    else if(p_strobe_r && cache_hit && lru[line_index][hit_index] < 3'b111 && p_ready_o) begin  //hit
        lru[line_index][hit_index]<=lru[line_index][hit_index]+1;
        for (x = 0; x < N_WAYS; x = x + 1) begin  //0-3
            if(x != hit_index)
                lru[line_index][x]<=lru[line_index][x]-1;
        end
    end
end

reg [2:0] lru_min;   //for 4 way  lru[line_index][0-3]
always @(*) begin   //選那個line  4個block裡面 lru最小的
    lru_min = 
    (lru[line_index][0] <= lru[line_index][1] &&
     lru[line_index][0] <= lru[line_index][2] &&
     lru[line_index][0] <= lru[line_index][3]) ? 0 :

    (lru[line_index][1] <= lru[line_index][0] &&
     lru[line_index][1] <= lru[line_index][2] &&
     lru[line_index][1] <= lru[line_index][3]) ? 1 :

    (lru[line_index][2] <= lru[line_index][0] &&
     lru[line_index][2] <= lru[line_index][1] &&
     lru[line_index][2] <= lru[line_index][3]) ? 2 :

                                                 3;
end





//====================================================
// Register some signals from the processor/memory.
//====================================================

// Register the address from the processor.
always@(posedge clk_i) begin
    if (rst_i) begin
        p_addr_r <= {XLEN{1'b0}};
    end else if (p_strobe_i) begin
        p_addr_r <= p_addr_i; // cpu 要的addr
    end
end

// Register the data, rw, and byte enable signals from the processor.
always @(posedge clk_i)
begin
    if (S == Idle)
    begin
        datain_from_p <= p_data_i;
        rw <= p_rw_i;
        byte_enable_from_p <= p_byte_enable_i;
    end
    else
    begin
        datain_from_p <= datain_from_p;
        rw <= rw;
        byte_enable_from_p <= byte_enable_from_p;
    end
    //之後直接拿來用 (非 Idle 時保持原值即可)
end

// Register the input data from the main memory.
assign m_data = (S == RdAmo)? m_data_r : m_data_i;

always @(posedge clk_i)
begin
    if (S == RdAmo)
        m_data_r <= m_data_i;
    else
        m_data_r <= m_data_r;
end

//=======================================================
// Write back all cache blocks to the main memory
//=======================================================
assign addr_sram   = (busy_flushing_o)? N_LINES_cnt : line_index;

    always @(posedge clk_i)     //下一次直接讓他overflow歸零
    begin
    if (rst_i || S == Idle)
        N_LINES_cnt <= {LINE_BITS{1'b0}};
    else if (S_nxt == WbtoMemAllFinish)
        N_LINES_cnt <= N_LINES_cnt + 1;
end

always @(posedge clk_i)
begin
    if (rst_i || S == Idle)
        N_WAYS_cnt <= {WAY_BITS{1'b0}};
    else if (N_LINES_cnt == N_LINES - 1 && S_nxt == WbtoMemAllFinish)
        N_WAYS_cnt <= N_WAYS_cnt + 1;
end

always @(posedge clk_i) begin
    WbAllFinish_r <= WbAllFinish;
end

//-----------------------------------------------
// Read a 32-bit word from the target cache line
//-----------------------------------------------
reg [XLEN-1 : 0] fromCache; // Get the specific word in cache line
reg [XLEN-1 : 0] fromMem;   // Get the specific word in memory line

always @(*)
begin // for hit
    case (line_offset)
`ifdef DRAM_WIDTH_16  // Arty, QMCore
        2'b11: fromCache = c_data_hit[ 31: 0];     // [127: 96]
        2'b10: fromCache = c_data_hit[ 63: 32];    // [ 95: 64]
        2'b01: fromCache = c_data_hit[ 95: 64];    // [ 63: 32]
        2'b00: fromCache = c_data_hit[127: 96];    // [ 31:  0]
`else // KC705, Genesys2, AXKU5, PZKU060, or K7BaseC
        3'b111: fromCache = c_data_hit[ 31: 0];    // [255:224]
        3'b110: fromCache = c_data_hit[ 63: 32];   // [223:192]
        3'b101: fromCache = c_data_hit[ 95: 64];   // [191:160]
        3'b100: fromCache = c_data_hit[127: 96];   // [159:128]
        3'b011: fromCache = c_data_hit[159: 128];  // [127: 96]
        3'b010: fromCache = c_data_hit[191: 160];  // [ 95: 64]
        3'b001: fromCache = c_data_hit[223: 192];  // [ 63: 32]
        3'b000: fromCache = c_data_hit[255: 224];  // [ 31:  0]
`endif
    endcase
end

always @(*)
begin // for miss
    case (line_offset)
`ifdef DRAM_WIDTH_16  // Arty, QMCore
        2'b11: fromMem = m_data[ 31: 0];        // [127: 96]
        2'b10: fromMem = m_data[ 63: 32];       // [ 95: 64]
        2'b01: fromMem = m_data[ 95: 64];       // [ 63: 32]
        2'b00: fromMem = m_data[127: 96];       // [ 31:  0]
`else // KC705, Genesys2, AXKU5, PZKU060, or K7BaseC
        3'b111: fromMem = m_data[ 31: 0];       // [255:224]
        3'b110: fromMem = m_data[ 63: 32];      // [223:192]
        3'b101: fromMem = m_data[ 95: 64];      // [191:160]
        3'b100: fromMem = m_data[127: 96];      // [159:128]
        3'b011: fromMem = m_data[159: 128];     // [127: 96]
        3'b010: fromMem = m_data[191: 160];     // [ 95: 64]
        3'b001: fromMem = m_data[223: 192];     // [ 63: 32]
        3'b000: fromMem = m_data[255: 224];     // [ 31:  0]
`endif
    endcase
end

//======================================================================
// Generate Output signals.
//======================================================================

always @(*)
begin // Note: p_data_o is significant when processor read data
    if (S == RdAmoFinish)
        p_data_o = m_data[CLSIZE-1:CLSIZE-XLEN];
    else if ((S == Analysis) && cache_hit && !rw)
        p_data_o = fromCache;
    else if (S == RdfromMem && m_ready_i && !rw) 
        p_data_o = fromMem;
    else
        p_data_o = {XLEN{1'b0}};
end

always @(*)
begin
    if (((S == Analysis) && cache_hit && ~p_is_amo_i && !p_flush_i) ||
        (S == RdfromMem && m_ready_i) ||
        (S == RdAmoFinish) ||
        (S == WbtoMemAllFinish && WbAllFinish_r))
        p_ready_reg = 1;
    else
        p_ready_reg = 0;
end

assign p_ready_o = p_ready_reg;

//======================================================================
// Create a single-cycle memory request pluse for the memory controller
//======================================================================
// The old code uses the reqest/act protocol, which is corrected by the
// CDC synchronizer to match the strobe protocol of MIG. Modified to
// strobe protocol by Chun-Jen Tsai, 09/29/2023.
wire m_strobe;
reg  m_strobe_r;

assign m_strobe = (S == RdfromMem || S == WbtoMem || S == RdAmo ||
                  (S == WbtoMemAll && NeedtoWb)) && !m_ready_i;

always @(posedge clk_i)
    m_strobe_r <= m_strobe;

always @(posedge clk_i)
begin
    if (rst_i)
        m_strobe_o <= 0;
    else if (m_strobe && !m_strobe_r)
        m_strobe_o <= 1;
    else
        m_strobe_o <= 0;
end
//======================================================================

always @(posedge clk_i)
begin
    if (rst_i)
        m_addr_o <= 0;
    else if (S == WbtoMemAll)
        m_addr_o <= {c_tag_o[N_WAYS_cnt], N_LINES_cnt, {WORD_BITS{1'b0}}, 2'b0};
    else if (S == WbtoMem) // the dirty data addr
        m_addr_o <= (is_amo_reg)?
                        {c_tag_o[hit_index], line_index, {WORD_BITS{1'b0}}, 2'b0} :
                        {c_tag_o[victim_sel], line_index, {WORD_BITS{1'b0}}, 2'b0};
    else if (S == RdfromMem) // read a cache block
        m_addr_o <= {p_addr_i[XLEN-1 : WORD_BITS+2], {WORD_BITS{1'b0}}, 2'b0};
    else if (S == RdAmo)
        m_addr_o <= p_addr_i;
    else
        m_addr_o <= {XLEN{1'b0}};
end

always @(posedge clk_i)
begin
    if (rst_i)
        m_data_o <= 0;
    else if (S == WbtoMemAll && NeedtoWb)
        m_data_o <= c_block[N_WAYS_cnt];
    else if (S == WbtoMem) // the dirty data write back to memory
        m_data_o <= (is_amo_reg)? c_data_hit : c_block[victim_sel];
    else if (S == RdAmo)
        m_data_o <= {p_data_i, {CLSIZE-XLEN{1'b0}}};
    else
        m_data_o <= 0;
end

//------------------------------------------------------------------------
// Write the correct bytes according to the signal byte_enable_from_p
//------------------------------------------------------------------------
reg [XLEN-1 : 0] update_data;

always @(*)
begin           // write miss : write hit;
    case (byte_enable_from_p)
        // DataMem_Addr[1:0] == 2'b00
        4'b0001: update_data = (S == RdfromMem && m_ready_i) ?
                      { fromMem[31:8], datain_from_p[7:0] } :
                      { fromCache[31:8], datain_from_p[7:0] };
        4'b0011: update_data = (S == RdfromMem && m_ready_i) ?
                      { fromMem[31:16], datain_from_p[15:0] } :
                      { fromCache[31:16], datain_from_p[15:0]};
        4'b1111: update_data = datain_from_p;

        // DataMem_Addr[1:0] == 2'b01
        4'b0010: update_data = (S == RdfromMem && m_ready_i) ?
                      { fromMem[31:16], datain_from_p[15:8], fromMem[7:0] } :
                      { fromCache[31 : 16], datain_from_p[15:8], fromCache[7:0] };

        // DataMem_Addr[1:0] == 2'b10
        4'b0100: update_data = (S == RdfromMem && m_ready_i) ?
                      { fromMem[31:24], datain_from_p[23:16], fromMem[15:0] } :
                      { fromCache[31:24], datain_from_p[23:16], fromCache[15:0] };
        4'b1100: update_data = (S == RdfromMem && m_ready_i) ?
                      { datain_from_p[31:16], fromMem[15:0] } :
                      { datain_from_p[31:16], fromCache[15:0] };

        // DataMem_Addr[1:0] == 2'b11
        4'b1000: update_data = (S == RdfromMem && m_ready_i) ?
                      { datain_from_p[31:24], fromMem[23:0] } :
                      { datain_from_p[31:24], fromCache[23:0] };
        default: update_data = 32'b0;
    endcase
end

//------------------------------------------------------------------------
// Write a 32-bit word into the target cache line.
//------------------------------------------------------------------------
/* Writing into cache from the processor or the main memory */
always @(*) begin
    case (line_offset)
`ifdef DRAM_WIDTH_16  // Arty, QMCore
        2'b11: c_data_update = {c_data_hit[127:32], update_data};
        2'b10: c_data_update = {c_data_hit[127:64], update_data, c_data_hit[31:0]};
        2'b01: c_data_update = {c_data_hit[127:96], update_data, c_data_hit[63:0]};
        2'b00: c_data_update = {update_data, c_data_hit[95:0]};
`else // KC705, Genesys2, AXKU5, PZKU060, or K7BaseC
        3'b111: c_data_update = {c_data_hit[255: 32], update_data};
        3'b110: c_data_update = {c_data_hit[255: 64], update_data, c_data_hit[ 31:0]};
        3'b101: c_data_update = {c_data_hit[255: 96], update_data, c_data_hit[ 63:0]};
        3'b100: c_data_update = {c_data_hit[255:128], update_data, c_data_hit[ 95:0]};
        3'b011: c_data_update = {c_data_hit[255:160], update_data, c_data_hit[127:0]};
        3'b010: c_data_update = {c_data_hit[255:192], update_data, c_data_hit[159:0]};
        3'b001: c_data_update = {c_data_hit[255:224], update_data, c_data_hit[191:0]};
        3'b000: c_data_update = {update_data, c_data_hit[223:0]};
`endif
    endcase
end

always @(*) begin
    case (line_offset)
`ifdef DRAM_WIDTH_16  // Arty, QMCore
        2'b11: m_data_update = {m_data[127:32], update_data};
        2'b10: m_data_update = {m_data[127:64], update_data, m_data[31:0]};
        2'b01: m_data_update = {m_data[127:96], update_data, m_data[63:0]};
        2'b00: m_data_update = {update_data, m_data[95:0]};
`else // KC705, Genesys2, AXKU5, PZKU060, or K7BaseC
        3'b111: m_data_update = {m_data[255: 32], update_data};
        3'b110: m_data_update = {m_data[255: 64], update_data, m_data[ 31:0]};
        3'b101: m_data_update = {m_data[255: 96], update_data, m_data[ 63:0]};
        3'b100: m_data_update = {m_data[255:128], update_data, m_data[ 95:0]};
        3'b011: m_data_update = {m_data[255:160], update_data, m_data[127:0]};
        3'b010: m_data_update = {m_data[255:192], update_data, m_data[159:0]};
        3'b001: m_data_update = {m_data[255:224], update_data, m_data[191:0]};
        3'b000: m_data_update = {update_data, m_data[223:0]};
`endif
    endcase
end

always @(*)
begin
    if (!rw) // Processor read miss and update cache data
        c_data_i = (S == RdfromMem && m_ready_i) ? m_data : {CLSIZE{1'b0}};
    else begin   // Processor write cache
        if ( (S == Analysis) && cache_hit )    // write hit
            c_data_i = c_data_update;
        else if (S == RdfromMem && m_ready_i)  // write miss
            c_data_i = m_data_update;
        else
            c_data_i = {CLSIZE{1'b0}};
    end
end

always @(posedge clk_i)
begin
    if (rst_i)
        m_rw_o <= 0;
    else if (S == WbtoMem || S == WbtoMemAll || S == RdAmo)
        m_rw_o <= 1;
    else
        m_rw_o <= 0; // default: Read memory
end

// AMO output signal
always @(posedge clk_i ) begin
    if (rst_i)
        is_amo_reg <= 1'b0;
    else if ( S == Analysis )
        is_amo_reg <= p_is_amo_i;
end

assign m_is_amo_o = (S == RdAmo) ? is_amo_reg : 1'b0 ;

always @(posedge clk_i ) begin
    // data signal don't reset
    if ( S == Analysis )
        m_amo_type_o <= p_amo_type_i;    
end

// Set a signal for flushing-in-progress notification
always @(posedge clk_i) begin
    if (rst_i)
        busy_flushing_o <= 0;
    else if (S == Idle && !busy_flushing_o)
        busy_flushing_o <= p_flush_i;
    else if (WbAllFinish_r && S_nxt == WbtoMemAllFinish)
        busy_flushing_o <= 0;
end

//=======================================================================
//  Compute the write flags for cache block & tag, valid, and dirty bits
//=======================================================================
always @(*)
begin
    if ((S == Analysis) && cache_hit && rw)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            cache_write[idx] = way_hit[idx];
    else if (S == RdfromMem && m_ready_i)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            cache_write[idx] = (idx == victim_sel);
    else
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            cache_write[idx] = 1'b0;
end

always @(*)
begin
    if (S == Init)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            valid_write[idx] = 1'b1;
    else if (S == RdfromMem && m_ready_i)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            valid_write[idx] = (idx == victim_sel);
    else if (S == RdAmo && m_ready_i && cache_hit)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            valid_write[idx] = (idx == hit_index);
    else
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            valid_write[idx] = 1'b0;
end

always @(*)
begin
    if (S == Init)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            dirty_write[idx] = 1'b1;
    else if (S_nxt == WbtoMemAllFinish)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            dirty_write[idx] = (idx == N_WAYS_cnt);
    else if (S == RdfromMem && m_ready_i && rw)
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            dirty_write[idx] = (idx == victim_sel);
    else if ((S == Analysis && cache_hit && rw) ||
             (S == RdAmo && m_ready_i && cache_hit))
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            dirty_write[idx] = (idx == hit_index);
    else
        for (idx = 0; idx < N_WAYS; idx = idx + 1)
            dirty_write[idx] = 1'b0;
end

//=======================================================
//  Cache data storage in Block RAM
//=======================================================
genvar i;
generate
    for (i = 0; i < N_WAYS; i = i + 1)
    begin
        sram #(.DATA_WIDTH(CLSIZE), .N_ENTRIES(N_LINES))
             DATA_BRAM(
                 .clk_i(clk_i),
                 .en_i(1'b1),
                 .we_i(cache_write[i]),
                 .addr_i(addr_sram),
                 .data_i(c_data_i),  // data from processor or memory.
                 .data_o(c_block[i])
             );
    end
endgenerate

//=======================================================
//  Tags storage in Block RAM
//=======================================================
genvar j;
generate
    for (j = 0; j < N_WAYS; j = j + 1)
    begin
        sram #(.DATA_WIDTH(TAG_BITS), .N_ENTRIES(N_LINES))
             TAG_BRAM(
                 .clk_i(clk_i),
                 .en_i(1'b1),
                 .we_i(cache_write[j]),
                 .addr_i(addr_sram),
                 .data_i(tag),
                 .data_o(c_tag_o[j])
             );
    end
endgenerate

//=======================================================
//  Valid bits storage in distributed RAM
//=======================================================
genvar k;
generate
    for (k = 0; k < N_WAYS; k = k + 1)
    begin
        distri_ram #(.ENTRY_NUM(N_LINES), .XLEN(1))
             VALID_RAM(
                 .clk_i(clk_i),
                 .we_i(valid_write[k]),
                 .read_addr_i(line_index),  //在cpu請求後會先保持一樣
                 .write_addr_i((S == Init)? init_count : line_index),
                 .data_i(S == RdfromMem && m_ready_i),
                 .data_o(c_valid_o[k])
             );
    end
endgenerate

//=======================================================
//  Dirty bits storage in distributed RAM
//=======================================================
wire [6:0] dirty_raddr = (S == WbtoMemAll)? N_LINES_cnt : line_index;
wire [6:0] dirty_waddr = (S_nxt == WbtoMemAllFinish)? N_LINES_cnt :
                         (S == Init)? init_count : line_index;
wire       dirty_datai = (S == RdfromMem && m_ready_i && rw) ||
                         (S == Analysis && cache_hit && rw);
genvar m;
generate
    for (m = 0; m < N_WAYS; m = m + 1)
    begin
        distri_ram #(.ENTRY_NUM(N_LINES), .XLEN(1))
             DIRTY_RAM(
                 .clk_i(clk_i),
                 .we_i(dirty_write[m]),
                 .read_addr_i(dirty_raddr),
                 .write_addr_i(dirty_waddr),
                 .data_i(dirty_datai),
                 .data_o(c_dirty_o[m])
             );
    end
endgenerate

endmodule
