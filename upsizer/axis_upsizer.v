`timescale 1ns / 1ps

module axis_upsizer #(
    parameter TX_WIDTH  = 64, 
    parameter RX_WIDTH = 128,  
    parameter TX_STRB_WIDTH = TX_WIDTH / 8,
    parameter RX_STRB_WIDTH = RX_WIDTH / 8,
    parameter TX_KEEP_WIDTH = TX_WIDTH/8, 
    parameter RX_KEEP_WIDTH = RX_WIDTH / 8,
    parameter TID_WIDTH = 2,
    parameter TDEST_WIDTH = 2,
    parameter TUSER_WIDTH = 1
)
(
    input  wire                   clk_i,
    input  wire                   rst_ni,

    // slave
    input  wire       [TX_WIDTH-1:0]        tx_tdata_i,
    input  wire                             tx_tvalid_i,  
    output wire                             tx_tready_o,
    input  wire                             tx_tlast_i,
    input  wire      [TID_WIDTH-1:0]        tx_tid_i,
    input  wire      [TDEST_WIDTH-1:0]      tx_tdest_i,
    input  wire      [TX_KEEP_WIDTH-1:0]    tx_tkeep_i,
    input  wire      [TX_STRB_WIDTH-1:0]    tx_tstrb_i,
    input  wire      [TUSER_WIDTH-1:0]      tx_tuser_i,

    // master 
    output wire     [RX_WIDTH-1:0]            rx_tdata_o,
    output reg                                rx_tvalid_o,
    input  wire                               rx_tready_i,
    output wire     [RX_KEEP_WIDTH-1:0]       rx_tkeep_o,
    output wire     [RX_STRB_WIDTH-1:0]       rx_tstrb_o,
    output wire                               rx_tlast_o,
    output wire     [TID_WIDTH-1:0]           rx_tid_o,
    output wire     [TDEST_WIDTH-1:0]         rx_tdest_o,
    output wire     [TUSER_WIDTH-1:0]         rx_tuser_o
);
    

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
// (e.g. localparam for FSM states)

    localparam RATIO = RX_WIDTH / TX_WIDTH;
    localparam CNT_WIDTH = $clog2(RATIO);
    localparam ST_ACCUM = 1'b0, ST_XFER = 1'b1;

    reg [CNT_WIDTH-1:0]     cnt, cnt_nxt;
    reg                     rx_tvalid_o_nxt;

    wire    tx_hs, rx_hs;
    wire    is_last;
    wire    is_full; 

    reg [RX_WIDTH-1 : 0]    rx_tdata_o_reg, rx_tdata_o_comb;
    reg [TID_WIDTH-1:0]     id_reg;
    reg [TDEST_WIDTH-1:0]   dest_reg;
    reg [RX_STRB_WIDTH-1:0]    strb_reg, strb_comb;
    reg [RX_KEEP_WIDTH-1:0]    keep_reg, keep_comb;
    reg [TUSER_WIDTH-1 : 0]    tuser_reg;

    reg last_reg, last_comb;
    reg state;
    reg state_nxt;

    integer i;



    assign tx_tready_o = (!rx_tvalid_o) || rx_tready_i;
    assign tx_hs = tx_tvalid_i & tx_tready_o;
    assign rx_hs = rx_tvalid_o & rx_tready_i; 
    assign rx_tdata_o = rx_tdata_o_reg;
    assign is_last = (tx_tlast_i && tx_tvalid_i);
    assign is_full = (tx_hs && cnt == RATIO-1);
    assign rx_tstrb_o = strb_reg;
    assign rx_tkeep_o = keep_reg;
    assign rx_tid_o = id_reg;
    assign rx_tdest_o = dest_reg;
    assign rx_tlast_o = last_reg;
    assign rx_tuser_o = tuser_reg;


// cnt calculate-------------------------------------------------------
    always @(*) begin
        cnt_nxt = (cnt == RATIO - 1 || tx_tlast_i) ? 0 : cnt + 1;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)  cnt <= 0;
        else if(tx_hs) cnt <= cnt_nxt;
    end
//---------------------------------------------------------------------





//data upsizing--------------------------------------------------------

    always @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) rx_tdata_o_reg <= 0;
        else       rx_tdata_o_reg <= rx_tdata_o_comb;
    end

    always @(*) begin
        rx_tdata_o_comb = rx_tdata_o_reg;
        case(state)
        ST_ACCUM : if(tx_hs)    rx_tdata_o_comb[TX_WIDTH*cnt+:TX_WIDTH] = tx_tdata_i;  
        ST_XFER  : if(rx_tready_i) rx_tdata_o_comb = {{(RX_WIDTH-TX_WIDTH){1'b0}} , {TX_WIDTH{tx_tvalid_i}} & tx_tdata_i};
        endcase
    end
//---------------------------------------------------------------------



//  KEEP, STROB process-----------------------
    always@(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin
            keep_reg <=0;
            strb_reg <= 0;
        end else begin
            keep_reg <= keep_comb;
            strb_reg <= strb_comb;
        end 
    end


    always @(*) begin
        keep_comb = keep_reg;
        strb_comb = strb_reg;
        case(state)
        ST_ACCUM : if(tx_hs)   begin
                keep_comb[TX_KEEP_WIDTH*cnt +: TX_KEEP_WIDTH] = tx_tkeep_i;
                strb_comb[TX_STRB_WIDTH*cnt +: TX_STRB_WIDTH] = tx_tstrb_i;
        end 
        ST_XFER  : if(rx_tready_i) begin
                keep_comb = {{(RX_KEEP_WIDTH-TX_KEEP_WIDTH){1'b0}}, {TX_KEEP_WIDTH{tx_tvalid_i}}& tx_tkeep_i};
                strb_comb = {{(RX_STRB_WIDTH-TX_STRB_WIDTH){1'b0}}, {TX_STRB_WIDTH{tx_tvalid_i}}& tx_tstrb_i};
        end
        endcase
        
    end
//-------------------------------------------------------------------

//when handshake finish caculate logic-----------------------------------------------------
    always @(*) begin
        rx_tvalid_o_nxt = rx_tvalid_o;

        if(rx_hs) begin
            rx_tvalid_o_nxt = 0;
        end
        
        if(is_full || is_last) begin
            rx_tvalid_o_nxt = 1;
        end
    end
//----------------------------------------------------------------

//hs calculate result-------------------------------------
    always @(posedge clk_i or negedge rst_ni) begin
            if(!rst_ni) begin
                rx_tvalid_o <= 0;
            end else begin
                rx_tvalid_o <= rx_tvalid_o_nxt;
            end
        end
//---------------------------------------------------





//---------------------------------------------------------------------
// State
//---------------------------------------------------------------------
// (e.g. current_state, next_state)
always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)  state <= ST_ACCUM;
    else state <= state_nxt;
    end


always @(*) begin
    state_nxt = state;
    case(state)
        ST_ACCUM :  state_nxt = (is_last || is_full) ? ST_XFER : ST_ACCUM;

        ST_XFER :   begin
               if(rx_hs & is_last) state_nxt = ST_XFER;
               else if(rx_hs) state_nxt = ST_ACCUM;
        end
    endcase    
end




//---------------------------------------------------------------------
// Logics
//---------------------------------------------------------------------
// (e.g. always blocks, assign statements)


//id, dest save logic
always @(posedge clk_i or negedge rst_ni ) begin
    if(!rst_ni) begin
        id_reg <= 0;
        dest_reg <= 0;
        tuser_reg <= 0;
    end else if(tx_hs && cnt == 0) begin
        id_reg <= tx_tid_i;
        dest_reg <= tx_tdest_i;   
        tuser_reg <= tx_tuser_i;
    end
end



// LAST signal---------------------

always@(posedge clk_i or negedge rst_ni)begin
    if(!rst_ni) last_reg <= 0;
    else last_reg <= last_comb;
end

always@(*) begin
    last_comb =last_reg;
    case(state) 
    ST_ACCUM : if(tx_hs)       last_comb = tx_tlast_i;
    ST_XFER  : if(rx_tready_i)    last_comb = (tx_tvalid_i) ? tx_tlast_i : 0;
    endcase
end


endmodule