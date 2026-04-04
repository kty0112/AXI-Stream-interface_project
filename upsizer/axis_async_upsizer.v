//---------------------------------------------------------------------
// FILE_NAME   : axis_async_upsizer.v
// DESCRIPTION : Asynchronous Upsizer with AXI-Stream Interface
//---------------------------------------------------------------------

`timescale 1ns/1ps
module axis_async_upsizer #(
    parameter FIFO_DEPTH    = 16,
    parameter TX_WIDTH      = 32,
    parameter RX_WIDTH      = 128,
    parameter TX_SKID_NUM   = 1,
    parameter MID_SKID_NUM  = 1,
    parameter RX_SKID_NUM   = 1,
    parameter LOW_LATENCY   = 1,
    parameter TID_WIDTH     = 1,
    parameter TDEST_WIDTH   = 1,
    parameter TUSER_WIDTH   = 1
)(
    input                       s_axis_aclk,
    input                       s_axis_arstn,
    
    // AXI-Stream slave interface
    input                       s_axis_tvalid,
    output                      s_axis_tready,
    input  [TX_WIDTH-1:0]       s_axis_tdata,
    input  [(TX_WIDTH/8)-1:0]   s_axis_tstrb,
    input  [(TX_WIDTH/8)-1:0]   s_axis_tkeep,
    input                       s_axis_tlast,
    input  [TID_WIDTH-1:0]      s_axis_tid,
    input  [TDEST_WIDTH-1:0]    s_axis_tdest,
    input  [TUSER_WIDTH-1:0]    s_axis_tuser,

    input                       m_axis_aclk,
    input                       m_axis_arstn,
    
    // AXI-Stream master interface
    output                      m_axis_tvalid,
    input                       m_axis_tready,
    output [RX_WIDTH-1:0]       m_axis_tdata,
    output [(RX_WIDTH/8)-1:0]   m_axis_tstrb,
    output [(RX_WIDTH/8)-1:0]   m_axis_tkeep,
    output                      m_axis_tlast,
    output [TID_WIDTH-1:0]      m_axis_tid,
    output [TDEST_WIDTH-1:0]    m_axis_tdest,
    output [TUSER_WIDTH-1:0]    m_axis_tuser
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
genvar i;

localparam ADDR_WIDTH       = $clog2(FIFO_DEPTH);
localparam TX_STRB_WIDTH    = (TX_WIDTH > 8) ? TX_WIDTH / 8 : 1;
localparam RX_STRB_WIDTH    = (RX_WIDTH > 8) ? RX_WIDTH / 8 : 1;
localparam TX_AXIS_WIDTH    = TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 
                              1 + TID_WIDTH + TDEST_WIDTH + TUSER_WIDTH;
localparam RX_AXIS_WIDTH    = RX_WIDTH + RX_STRB_WIDTH + RX_STRB_WIDTH + 
                              1 + TID_WIDTH + TDEST_WIDTH + TUSER_WIDTH;

//---------------------------------------------------------------------
// Data
//---------------------------------------------------------------------

// TX Skid Chain to Async FIFO interface signals
wire                        fifo_w_valid_i;
wire                        fifo_w_ready_o;
wire [TX_AXIS_WIDTH-1:0]    fifo_w_data_i;

// Async FIFO to MID Skid Chain interface signals
wire                        fifo_r_valid_o;
wire                        fifo_r_ready_i;
wire [TX_AXIS_WIDTH-1:0]    fifo_r_data_o;

// MID Skid Chain to Upsizer interface signals
wire                        ups_tvalid_i;
wire                        ups_tready_o;
wire [TX_WIDTH-1:0]         ups_tdata_i;
wire [TX_STRB_WIDTH-1:0]    ups_tstrb_i;
wire [TX_STRB_WIDTH-1:0]    ups_tkeep_i;
wire                        ups_tlast_i;
wire [TID_WIDTH-1:0]        ups_tid_i;
wire [TDEST_WIDTH-1:0]      ups_tdest_i;
wire [TUSER_WIDTH-1:0]      ups_tuser_i;

// Upsizer to RX Skid Chain interface signals
wire                        ups_tvalid_o;
wire                        ups_tready_i;
wire [RX_WIDTH-1:0]         ups_tdata_o;
wire [RX_STRB_WIDTH-1:0]    ups_tstrb_o;
wire [RX_STRB_WIDTH-1:0]    ups_tkeep_o;
wire                        ups_tlast_o;
wire [TID_WIDTH-1:0]        ups_tid_o;
wire [TDEST_WIDTH-1:0]      ups_tdest_o;
wire [TUSER_WIDTH-1:0]      ups_tuser_o;

//---------------------------------------------------------------------
// TX Skid Chain Generation (Input -> Async FIFO)
//---------------------------------------------------------------------
generate
    if (TX_SKID_NUM == 0) begin : gen_tx_bypass
        assign fifo_w_data_i = {
            s_axis_tuser,
            s_axis_tdest,
            s_axis_tid,
            s_axis_tlast,
            s_axis_tkeep,
            s_axis_tstrb,
            s_axis_tdata
        };
        assign fifo_w_valid_i = s_axis_tvalid;
        assign s_axis_tready  = fifo_w_ready_o;
    end else begin : gen_tx_chain
        wire [TX_AXIS_WIDTH-1:0] chain_data  [0:TX_SKID_NUM];
        wire                     chain_valid [0:TX_SKID_NUM];
        wire                     chain_ready [0:TX_SKID_NUM];

        // Pack input AXI-Stream signals
        assign chain_data[0] = {
            s_axis_tuser,
            s_axis_tdest,
            s_axis_tid,
            s_axis_tlast,
            s_axis_tkeep,
            s_axis_tstrb,
            s_axis_tdata
        };
        assign chain_valid[0] = s_axis_tvalid;
        assign s_axis_tready  = chain_ready[0];

        for (i = 0; i < TX_SKID_NUM; i = i + 1) begin : gen_tx_chain_loop
            skid_buffer #(
                .DATA_WIDTH(TX_AXIS_WIDTH)
            ) u_tx_skid (
                .clk_i    (s_axis_aclk),
                .rst_ni   (s_axis_arstn),

                .s_valid_i(chain_valid[i]),
                .s_ready_o(chain_ready[i]),
                .s_data_i (chain_data[i]),
                
                .m_valid_o(chain_valid[i+1]),
                .m_ready_i(chain_ready[i+1]),
                .m_data_o (chain_data[i+1])
            );
        end

        // Output to Async FIFO
        assign fifo_w_data_i  = chain_data[TX_SKID_NUM];
        assign fifo_w_valid_i = chain_valid[TX_SKID_NUM];
        assign chain_ready[TX_SKID_NUM] = fifo_w_ready_o;
    end
endgenerate

//---------------------------------------------------------------------
// Async FIFO Instance
//---------------------------------------------------------------------
async_fifo #(
    .DEPTH       (FIFO_DEPTH),
    .DATA_WIDTH  (TX_AXIS_WIDTH),
    .LOW_LATENCY (LOW_LATENCY)
) u_async_fifo (
    .w_clk_i   (s_axis_aclk),
    .w_rst_ni  (s_axis_arstn),
    .w_valid_i (fifo_w_valid_i),
    .w_ready_o (fifo_w_ready_o),
    .w_data_i  (fifo_w_data_i),

    .r_clk_i   (m_axis_aclk),
    .r_rst_ni  (m_axis_arstn),
    .r_valid_o (fifo_r_valid_o),
    .r_ready_i (fifo_r_ready_i),
    .r_data_o  (fifo_r_data_o)
);

//---------------------------------------------------------------------
// Middle Skid Chain Generation (Async FIFO -> Upsizer)
//---------------------------------------------------------------------
generate
    if (MID_SKID_NUM == 0) begin : gen_mid_bypass
        assign ups_tvalid_i = fifo_r_valid_o;
        assign fifo_r_ready_i = ups_tready_o;
        assign ups_tdata_i  = fifo_r_data_o[TX_WIDTH-1:0];
        assign ups_tstrb_i  = fifo_r_data_o[TX_WIDTH +: TX_STRB_WIDTH];
        assign ups_tkeep_i  = fifo_r_data_o[TX_WIDTH + TX_STRB_WIDTH +: TX_STRB_WIDTH];
        assign ups_tlast_i  = fifo_r_data_o[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH];
        assign ups_tid_i    = fifo_r_data_o[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 +: TID_WIDTH];
        assign ups_tdest_i  = fifo_r_data_o[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 + TID_WIDTH +: TDEST_WIDTH];
        assign ups_tuser_i  = fifo_r_data_o[TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 + TID_WIDTH + TDEST_WIDTH +: TUSER_WIDTH];
    end else begin : gen_mid_chain
        wire [TX_AXIS_WIDTH-1:0] chain_data  [0:MID_SKID_NUM];
        wire                     chain_valid [0:MID_SKID_NUM];
        wire                     chain_ready [0:MID_SKID_NUM];

        // Input from Async FIFO
        assign chain_data[0]  = fifo_r_data_o;
        assign chain_valid[0] = fifo_r_valid_o;
        assign fifo_r_ready_i = chain_ready[0];

        for (i = 0; i < MID_SKID_NUM; i = i + 1) begin : gen_mid_chain_loop
            skid_buffer #(
                .DATA_WIDTH(TX_AXIS_WIDTH)
            ) u_mid_skid (
                .clk_i    (m_axis_aclk),
                .rst_ni   (m_axis_arstn),
                .s_valid_i(chain_valid[i]),
                .s_ready_o(chain_ready[i]),
                .s_data_i (chain_data[i]),
                .m_valid_o(chain_valid[i+1]),
                .m_ready_i(chain_ready[i+1]),
                .m_data_o (chain_data[i+1])
            );
        end

        // Unpack output to Upsizer
        assign ups_tvalid_i = chain_valid[MID_SKID_NUM];
        assign chain_ready[MID_SKID_NUM] = ups_tready_o;
        assign ups_tdata_i  = chain_data[MID_SKID_NUM][TX_WIDTH-1:0];
        assign ups_tstrb_i  = chain_data[MID_SKID_NUM][TX_WIDTH +: TX_STRB_WIDTH];
        assign ups_tkeep_i  = chain_data[MID_SKID_NUM][TX_WIDTH + TX_STRB_WIDTH +: TX_STRB_WIDTH];
        assign ups_tlast_i  = chain_data[MID_SKID_NUM][TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH];
        assign ups_tid_i    = chain_data[MID_SKID_NUM][TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 +: TID_WIDTH];
        assign ups_tdest_i  = chain_data[MID_SKID_NUM][TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 + TID_WIDTH +: TDEST_WIDTH];
        assign ups_tuser_i  = chain_data[MID_SKID_NUM][TX_WIDTH + TX_STRB_WIDTH + TX_STRB_WIDTH + 1 + TID_WIDTH + TDEST_WIDTH +: TUSER_WIDTH];
    end
endgenerate

//---------------------------------------------------------------------
// AXI-Stream Upsizer Instance
//---------------------------------------------------------------------
axis_upsizer #(
    .TX_WIDTH    (TX_WIDTH),
    .RX_WIDTH    (RX_WIDTH),
    .TID_WIDTH   (TID_WIDTH),
    .TDEST_WIDTH (TDEST_WIDTH),
    .TUSER_WIDTH (TUSER_WIDTH)
) u_axis_upsizer (
    .clk_i       (m_axis_aclk),
    .rst_ni      (m_axis_arstn),
    
    .tx_tvalid_i (ups_tvalid_i),
    .tx_tready_o (ups_tready_o),
    .tx_tdata_i  (ups_tdata_i),
    .tx_tstrb_i  (ups_tstrb_i),
    .tx_tkeep_i  (ups_tkeep_i),
    .tx_tlast_i  (ups_tlast_i),
    .tx_tid_i    (ups_tid_i),
    .tx_tdest_i  (ups_tdest_i),
    .tx_tuser_i  (ups_tuser_i),
    
    .rx_tvalid_o (ups_tvalid_o),
    .rx_tready_i (ups_tready_i),
    .rx_tdata_o  (ups_tdata_o),
    .rx_tstrb_o  (ups_tstrb_o),
    .rx_tkeep_o  (ups_tkeep_o),
    .rx_tlast_o  (ups_tlast_o),
    .rx_tid_o    (ups_tid_o),
    .rx_tdest_o  (ups_tdest_o),
    .rx_tuser_o  (ups_tuser_o)
);

//---------------------------------------------------------------------
// RX Skid Chain Generation (Upsizer -> Output)
//---------------------------------------------------------------------
generate
    if (RX_SKID_NUM == 0) begin : gen_rx_bypass
        assign m_axis_tvalid = ups_tvalid_o;
        assign ups_tready_i  = m_axis_tready;
        assign m_axis_tdata  = ups_tdata_o;
        assign m_axis_tstrb  = ups_tstrb_o;
        assign m_axis_tkeep  = ups_tkeep_o;
        assign m_axis_tlast  = ups_tlast_o;
        assign m_axis_tid    = ups_tid_o;
        assign m_axis_tdest  = ups_tdest_o;
        assign m_axis_tuser  = ups_tuser_o;
    end else begin : gen_rx_chain
        wire [RX_AXIS_WIDTH-1:0] chain_data  [0:RX_SKID_NUM];
        wire                     chain_valid [0:RX_SKID_NUM];
        wire                     chain_ready [0:RX_SKID_NUM];

        // Pack input from Upsizer
        assign chain_data[0] = {
            ups_tuser_o,
            ups_tdest_o,
            ups_tid_o,
            ups_tlast_o,
            ups_tkeep_o,
            ups_tstrb_o,
            ups_tdata_o
        };
        assign chain_valid[0] = ups_tvalid_o;
        assign ups_tready_i   = chain_ready[0];

        for (i = 0; i < RX_SKID_NUM; i = i + 1) begin : gen_rx_chain_loop
            skid_buffer #(
                .DATA_WIDTH(RX_AXIS_WIDTH)
            ) u_rx_skid (
                .clk_i    (m_axis_aclk),
                .rst_ni   (m_axis_arstn),
                .s_valid_i(chain_valid[i]),
                .s_ready_o(chain_ready[i]),
                .s_data_i (chain_data[i]),
                .m_valid_o(chain_valid[i+1]),
                .m_ready_i(chain_ready[i+1]),
                .m_data_o (chain_data[i+1])
            );
        end

        // Unpack output to AXI-Stream master interface
        assign m_axis_tvalid = chain_valid[RX_SKID_NUM];
        assign chain_ready[RX_SKID_NUM] = m_axis_tready;
        assign m_axis_tdata  = chain_data[RX_SKID_NUM][RX_WIDTH-1:0];
        assign m_axis_tstrb  = chain_data[RX_SKID_NUM][RX_WIDTH +: RX_STRB_WIDTH];
        assign m_axis_tkeep  = chain_data[RX_SKID_NUM][RX_WIDTH + RX_STRB_WIDTH +: RX_STRB_WIDTH];
        assign m_axis_tlast  = chain_data[RX_SKID_NUM][RX_WIDTH + RX_STRB_WIDTH + RX_STRB_WIDTH];
        assign m_axis_tid    = chain_data[RX_SKID_NUM][RX_WIDTH + RX_STRB_WIDTH + RX_STRB_WIDTH + 1 +: TID_WIDTH];
        assign m_axis_tdest  = chain_data[RX_SKID_NUM][RX_WIDTH + RX_STRB_WIDTH + RX_STRB_WIDTH + 1 + TID_WIDTH +: TDEST_WIDTH];
        assign m_axis_tuser  = chain_data[RX_SKID_NUM][RX_WIDTH + RX_STRB_WIDTH + RX_STRB_WIDTH + 1 + TID_WIDTH + TDEST_WIDTH +: TUSER_WIDTH];
    end
endgenerate

endmodule