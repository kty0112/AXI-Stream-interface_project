//---------------------------------------------------------------------
// FILE_NAME   : axis_downsizer.v
// DESCRIPTION : Data Width Downsizer
//---------------------------------------------------------------------

`timescale 1ns/1ps
module axis_downsizer #(
    parameter TX_WIDTH      = 128,
    parameter RX_WIDTH      = 32,
    parameter TID_WIDTH     = 1,
    parameter TDEST_WIDTH   = 1,
    parameter TUSER_WIDTH   = 1
)(
    input                           clk_i,
    input                           rst_ni,
    
    input                           tx_tvalid_i,
    output                          tx_tready_o,
    input  [TX_WIDTH-1:0]           tx_tdata_i,
    input  [(TX_WIDTH/8)-1:0]       tx_tstrb_i,
    input  [(TX_WIDTH/8)-1:0]       tx_tkeep_i,
    input                           tx_tlast_i,
    input  [TID_WIDTH-1:0]          tx_tid_i,
    input  [TDEST_WIDTH-1:0]        tx_tdest_i,
    input  [TUSER_WIDTH-1:0]        tx_tuser_i,
    
    output                          rx_tvalid_o,
    input                           rx_tready_i,
    output [RX_WIDTH-1:0]           rx_tdata_o,
    output [(RX_WIDTH/8)-1:0]       rx_tstrb_o,
    output [(RX_WIDTH/8)-1:0]       rx_tkeep_o,
    output                          rx_tlast_o,
    output [TID_WIDTH-1:0]          rx_tid_o,
    output [TDEST_WIDTH-1:0]        rx_tdest_o,
    output [TUSER_WIDTH-1:0]        rx_tuser_o
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
genvar n;

localparam RATIO            = TX_WIDTH/RX_WIDTH;
localparam CNT_BIT          = (RATIO > 1) ? $clog2(RATIO) : 1;
localparam TX_STRB_WIDTH    = (TX_WIDTH > 8) ? TX_WIDTH / 8 : 1;
localparam RX_STRB_WIDTH    = (RX_WIDTH > 8) ? RX_WIDTH / 8 : 1;

initial begin
    if(RATIO == 0) $fatal(1, "Error : Data Width of TX should be larger than RX");
    if(TX_WIDTH % RX_WIDTH != 0) $fatal(1, "Error : TX WIDTH (%0d) should be propotional with RX WIDTH (%0d)", TX_WIDTH, RX_WIDTH);
end

localparam [1:0] ST_IDLE      = 2'b00,
                 ST_XFER      = 2'b01,
                 ST_XFER_LAST = 2'b10;

//---------------------------------------------------------------------
// Data
//---------------------------------------------------------------------

// State
reg [1:0] state, state_nxt;

// Control Siganls
wire tx_hs, rx_hs;
wire is_last_frag;

// Input Register
reg  [TX_WIDTH-1:0]         tdata_reg;
reg  [TX_STRB_WIDTH-1:0]    tstrb_reg;
reg  [TX_STRB_WIDTH-1:0]    tkeep_reg;
reg  [TID_WIDTH-1:0]        tid_reg;
reg  [TDEST_WIDTH-1:0]      tdest_reg;
reg  [TUSER_WIDTH-1:0]      tuser_reg;

// Handshake Counter
reg [CNT_BIT-1:0]  frag_cnt, frag_cnt_nxt;

// Output Interface
wire [CNT_BIT-1:0]       sel_idx;

wire [RX_WIDTH-1:0]      mux_tdata [0:RATIO-1];
wire [RX_STRB_WIDTH-1:0] mux_tstrb [0:RATIO-1];
wire [RX_STRB_WIDTH-1:0] mux_tkeep [0:RATIO-1];

//---------------------------------------------------------------------
// Logics
//---------------------------------------------------------------------

// State Logic
always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) state <= ST_IDLE;
    else        state <= state_nxt;
end

always @(*) begin
    state_nxt = state;
    case(state)
    ST_IDLE      : if(tx_tvalid_i)  state_nxt = tx_tlast_i ? ST_XFER_LAST : ST_XFER ;
    ST_XFER      : if(is_last_frag) state_nxt = tx_tvalid_i ? (tx_tlast_i ? ST_XFER_LAST : ST_XFER) : ST_IDLE;
    ST_XFER_LAST : if(is_last_frag) state_nxt = tx_tvalid_i ? (tx_tlast_i ? ST_XFER_LAST : ST_XFER) : ST_IDLE;
    default      : state_nxt = ST_IDLE;
    endcase
end

// Control Signals
assign tx_hs            = tx_tvalid_i & tx_tready_o;
assign rx_hs            = rx_tvalid_o & rx_tready_i;
assign is_last_frag     = rx_hs & (frag_cnt == RATIO-1);
assign tx_tready_o      = (state == ST_IDLE) || is_last_frag;
assign rx_tvalid_o      = (state == ST_XFER) || (state == ST_XFER_LAST);

// Input Register
always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        tdata_reg  <= {TX_WIDTH{1'b0}};
        tstrb_reg  <= {TX_STRB_WIDTH{1'b0}};
        tkeep_reg  <= {TX_STRB_WIDTH{1'b0}};
        tid_reg    <= {TID_WIDTH{1'b0}};
        tdest_reg  <= {TDEST_WIDTH{1'b0}};
        tuser_reg  <= {TUSER_WIDTH{1'b0}};
    end else if (tx_hs) begin
        tdata_reg  <= tx_tdata_i;
        tstrb_reg  <= tx_tstrb_i;
        tkeep_reg  <= tx_tkeep_i;
        tid_reg    <= tx_tid_i;
        tdest_reg  <= tx_tdest_i;
        tuser_reg  <= tx_tuser_i;
    end
end

// Counter
always @(posedge clk_i or negedge rst_ni) begin
    if      (!rst_ni) frag_cnt <= 0;
    else if (rx_hs)   frag_cnt <= frag_cnt_nxt;
end

always @(*) begin
    frag_cnt_nxt = (frag_cnt == RATIO-1) ? 0 : frag_cnt + 1;
end

// Output Interfcaes
assign sel_idx = (frag_cnt < RATIO) ? frag_cnt : 0; 

generate
    for(n=0; n<RATIO; n=n+1) begin: gen_output_mux
        assign mux_tdata[n] = tdata_reg[n*RX_WIDTH+:RX_WIDTH];
        assign mux_tstrb[n] = tstrb_reg[n*RX_STRB_WIDTH+:RX_STRB_WIDTH];
        assign mux_tkeep[n] = tkeep_reg[n*RX_STRB_WIDTH+:RX_STRB_WIDTH];
    end
endgenerate

assign rx_tdata_o   = mux_tdata[sel_idx];
assign rx_tstrb_o   = mux_tstrb[sel_idx];
assign rx_tkeep_o   = mux_tkeep[sel_idx];
assign rx_tlast_o   = (state == ST_XFER_LAST) && (frag_cnt == RATIO-1);
assign rx_tid_o     = tid_reg;
assign rx_tdest_o   = tdest_reg;
assign rx_tuser_o   = tuser_reg;

endmodule

//---------------------------------------------------------------------
// FILE_NAME   : axis_downsizer_wrapper.v
// DESCRIPTION : AXI-Stream Downsizer Wrapper with Optional FIFO
//---------------------------------------------------------------------

module axis_downsizer_wrapper #(
    parameter TX_WIDTH      = 128,
    parameter RX_WIDTH      = 32,
    parameter TID_WIDTH     = 1,
    parameter TDEST_WIDTH   = 1,
    parameter TUSER_WIDTH   = 1,
    parameter USE_FIFO      = 0         // 0 : No FIFO | 1 : Enable FIFO
)(
    input                           clk_i,
    input                           rst_ni,
    
    // TX Interface (Input)
    input                           tx_tvalid_i,
    output                          tx_tready_o,
    input  [TX_WIDTH-1:0]           tx_tdata_i,
    input  [(TX_WIDTH/8)-1:0]       tx_tstrb_i,
    input  [(TX_WIDTH/8)-1:0]       tx_tkeep_i,
    input                           tx_tlast_i,
    input  [TID_WIDTH-1:0]          tx_tid_i,
    input  [TDEST_WIDTH-1:0]        tx_tdest_i,
    input  [TUSER_WIDTH-1:0]        tx_tuser_i,
    
    // RX Interface (Output)
    output                          rx_tvalid_o,
    input                           rx_tready_i,
    output [RX_WIDTH-1:0]           rx_tdata_o,
    output [(RX_WIDTH/8)-1:0]       rx_tstrb_o,
    output [(RX_WIDTH/8)-1:0]       rx_tkeep_o,
    output                          rx_tlast_o,
    output [TID_WIDTH-1:0]          rx_tid_o,
    output [TDEST_WIDTH-1:0]        rx_tdest_o,
    output [TUSER_WIDTH-1:0]        rx_tuser_o
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
localparam TX_STRB_WIDTH = (TX_WIDTH > 8) ? TX_WIDTH / 8 : 1;
localparam FIFO_DATA_WIDTH = TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 
                             1 + TID_WIDTH + TDEST_WIDTH + TUSER_WIDTH;

localparam RATIO = (TX_WIDTH / RX_WIDTH == 0) ? 1 : (TX_WIDTH / RX_WIDTH);
localparam FIFO_DEPTH = RATIO;

//---------------------------------------------------------------------
// Data
//---------------------------------------------------------------------
// FIFO output / Downsizer input signals
wire                          downsizer_tvalid_i;
wire                          downsizer_tready_o;
wire [TX_WIDTH-1:0]           downsizer_tdata_i;
wire [TX_STRB_WIDTH-1:0]      downsizer_tstrb_i;
wire [TX_STRB_WIDTH-1:0]      downsizer_tkeep_i;
wire                          downsizer_tlast_i;
wire [TID_WIDTH-1:0]          downsizer_tid_i;
wire [TDEST_WIDTH-1:0]        downsizer_tdest_i;
wire [TUSER_WIDTH-1:0]        downsizer_tuser_i;

// FIFO interface signals
wire [FIFO_DATA_WIDTH-1:0]    fifo_w_tdata;
wire [FIFO_DATA_WIDTH-1:0]    fifo_r_tdata;

//---------------------------------------------------------------------
// Conditional FIFO Instance
//---------------------------------------------------------------------
generate
    if (USE_FIFO == 1) begin : gen_with_fifo
        
        // Pack TX inputs into FIFO write data
        assign fifo_w_tdata = {
            tx_tuser_i,
            tx_tdest_i,
            tx_tid_i,
            tx_tlast_i,
            tx_tkeep_i,
            tx_tstrb_i,
            tx_tdata_i
        };
        
        // FIFO instance
        sync_fifo #(
            .DEPTH          (FIFO_DEPTH),
            .DATA_WIDTH     (FIFO_DATA_WIDTH)
        ) u_sync_fifo (
            .clk_i          (clk_i),
            .rst_ni         (rst_ni),
            
            .w_tvalid       (tx_tvalid_i),
            .w_tready       (tx_tready_o),
            .w_tdata        (fifo_w_tdata),
            
            .r_tvalid       (downsizer_tvalid_i),
            .r_tready       (downsizer_tready_o),
            .r_tdata        (fifo_r_tdata)
        );
        
        // Unpack FIFO read data to downsizer input
        assign downsizer_tdata_i  = fifo_r_tdata[TX_WIDTH-1:0];
        assign downsizer_tstrb_i  = fifo_r_tdata[TX_WIDTH +: TX_STRB_WIDTH];
        assign downsizer_tkeep_i  = fifo_r_tdata[TX_WIDTH + TX_STRB_WIDTH +: TX_STRB_WIDTH];
        assign downsizer_tlast_i  = fifo_r_tdata[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH];
        assign downsizer_tid_i    = fifo_r_tdata[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 +: TID_WIDTH];
        assign downsizer_tdest_i  = fifo_r_tdata[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 + TID_WIDTH +: TDEST_WIDTH];
        assign downsizer_tuser_i  = fifo_r_tdata[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 + TID_WIDTH + TDEST_WIDTH +: TUSER_WIDTH];
        
    end else begin : gen_without_fifo
        
        // Direct connection without FIFO
        assign downsizer_tvalid_i   = tx_tvalid_i;
        assign tx_tready_o          = downsizer_tready_o;
        assign downsizer_tdata_i    = tx_tdata_i;
        assign downsizer_tstrb_i    = tx_tstrb_i;
        assign downsizer_tkeep_i    = tx_tkeep_i;
        assign downsizer_tlast_i    = tx_tlast_i;
        assign downsizer_tid_i      = tx_tid_i;
        assign downsizer_tdest_i    = tx_tdest_i;
        assign downsizer_tuser_i    = tx_tuser_i;
        
    end
endgenerate

//---------------------------------------------------------------------
// AXI-Stream Downsizer Instance
//---------------------------------------------------------------------
axis_downsizer #(
    .TX_WIDTH       (TX_WIDTH),
    .RX_WIDTH       (RX_WIDTH),
    .TID_WIDTH      (TID_WIDTH),
    .TDEST_WIDTH    (TDEST_WIDTH),
    .TUSER_WIDTH    (TUSER_WIDTH)
) u_axis_downsizer (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    
    .tx_tvalid_i    (downsizer_tvalid_i),
    .tx_tready_o    (downsizer_tready_o),
    .tx_tdata_i     (downsizer_tdata_i),
    .tx_tstrb_i     (downsizer_tstrb_i),
    .tx_tkeep_i     (downsizer_tkeep_i),
    .tx_tlast_i     (downsizer_tlast_i),
    .tx_tid_i       (downsizer_tid_i),
    .tx_tdest_i     (downsizer_tdest_i),
    .tx_tuser_i     (downsizer_tuser_i),
    
    .rx_tvalid_o    (rx_tvalid_o),
    .rx_tready_i    (rx_tready_i),
    .rx_tdata_o     (rx_tdata_o),
    .rx_tstrb_o     (rx_tstrb_o),
    .rx_tkeep_o     (rx_tkeep_o),
    .rx_tlast_o     (rx_tlast_o),
    .rx_tid_o       (rx_tid_o),
    .rx_tdest_o     (rx_tdest_o),
    .rx_tuser_o     (rx_tuser_o)
);

endmodule
