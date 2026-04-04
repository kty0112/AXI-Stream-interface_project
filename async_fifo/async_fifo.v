//---------------------------------------------------------------------
// FILE_NAME   : async_fifo.v
// DESCRIPTION : Asynchronous FIFO used to CDC
//---------------------------------------------------------------------

`timescale 1ns/1ps
module async_fifo #(
  parameter DEPTH       = 128,
  parameter ADDR_WIDTH  = $clog2(DEPTH),
  parameter DATA_WIDTH  = 32,
  parameter LOW_LATENCY = 1
)(
    input                   w_clk_i,
    input                   w_rst_ni,
    input                   w_valid_i,
    output                  w_ready_o,
    input  [DATA_WIDTH-1:0] w_data_i,

    input                   r_clk_i,
    input                   r_rst_ni,
    output                  r_valid_o,
    input                   r_ready_i,
    output [DATA_WIDTH-1:0] r_data_o
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
integer i;

initial begin
    if((DEPTH & (DEPTH-1)) != 0) begin
        $fatal(1, "[ERROR] DEPTH must be a power of 2, But : %d", DEPTH);
        $finish;
    end

    if(ADDR_WIDTH < 2) begin
        $fatal(1, "[ERROR] DEPTH(%d) is lower than 4. Too Short", DEPTH);
        $finish;
    end 
end

//---------------------------------------------------------------------
// Data
//---------------------------------------------------------------------
wire full, full_n, is_full;
wire empty, empty_n, is_empty;

reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];

wire [ADDR_WIDTH-1:0] waddr, raddr;
wire [ADDR_WIDTH:0]   wptr, wptr_nxt;
wire [ADDR_WIDTH:0]   rptr, rptr_nxt;
wire [ADDR_WIDTH:0]   wptr_sync, rptr_sync;

wire waddr_msb, raddr_msb;
wire w_hs, r_hs;

//---------------------------------------------------------------------
// Logics
//---------------------------------------------------------------------
assign w_hs             = w_valid_i & w_ready_o;
assign r_hs             = r_valid_o & r_ready_i;
assign w_ready_o        = full_n;
assign waddr            = {waddr_msb, wptr[ADDR_WIDTH-2:0]}; 
assign raddr            = {raddr_msb, rptr[ADDR_WIDTH-2:0]}; 
assign is_full          = (&(wptr_nxt[ADDR_WIDTH-:2] ^ rptr_sync[ADDR_WIDTH-:2])) && (wptr_nxt[ADDR_WIDTH-2:0] == rptr_sync[ADDR_WIDTH-2:0]);
assign is_empty         = (rptr_nxt == wptr_sync); 
assign r_valid_o        = empty_n; 
assign r_data_o         = fifo_mem[raddr];

always @(posedge w_clk_i or negedge w_rst_ni) begin
    if(!w_rst_ni) for(i=0; i<DEPTH; i=i+1) fifo_mem[i] <= {DATA_WIDTH{1'b0}};
    else if(w_hs) fifo_mem[waddr] <= w_data_i;
end

// Instance
//---------------------------------------------------------------------
comp_dff #(
    .RESET_VAL(1'b0)
) full_dff (
    .clk (w_clk_i), .rstn (w_rst_ni),
    .d (is_full), .q (full), .q_n (full_n)
);

comp_dff #(
    .RESET_VAL(1'b1)    
) empty_dff (
    .clk (r_clk_i), .rstn (r_rst_ni),
    .d (is_empty), .q (empty), .q_n (empty_n)
);

synchronizer #(
    .DEPTH(2), .DATA_WIDTH(ADDR_WIDTH+1)
) r2w_sync (
    .clk (w_clk_i), .rstn (w_rst_ni),
    .async_din (rptr), .sync_dout (rptr_sync)
);

synchronizer #(
    .DEPTH(2), .DATA_WIDTH(ADDR_WIDTH+1)
) w2r_sync (
    .clk (r_clk_i), .rstn (r_rst_ni),
    .async_din (wptr), .sync_dout (wptr_sync)
);

gray_ptr #(
    .ADDR_WIDTH(ADDR_WIDTH), .LOW_LATENCY(LOW_LATENCY)
) w_gray_ptr (
    .clk (w_clk_i), .rstn (w_rst_ni),
    .cnt_ena (w_hs),
    .o_ptr (wptr), .o_ptr_nxt (wptr_nxt), .o_addr_msb (waddr_msb)
);

gray_ptr #(
    .ADDR_WIDTH(ADDR_WIDTH), .LOW_LATENCY(LOW_LATENCY)
) r_gray_ptr (
    .clk (r_clk_i), .rstn (r_rst_ni),
    .cnt_ena (r_hs),
    .o_ptr (rptr), .o_ptr_nxt (rptr_nxt), .o_addr_msb (raddr_msb)
);
endmodule

//---------------------------------------------------------------------
// FILE_NAME   : axis_async_fifo_wrapper.v
// DESCRIPTION : Asynchronous FIFO Wrapper with AXI-Stream Interface
//---------------------------------------------------------------------

module axis_async_fifo_wrapper #(
    parameter FIFO_DEPTH    = 16,
    parameter TDATA_WIDTH    = 32,
    parameter TX_SKID_NUM   = 1,
    parameter RX_SKID_NUM   = 1,
    parameter LOW_LATENCY   = 1,
    parameter TID_WIDTH     = 1,
    parameter TDEST_WIDTH   = 1,
    parameter TUSER_WIDTH   = 1
)(
    input                        s_axis_aclk,
    input                        s_axis_arstn,
    
    // AXI-Stream slave interface
    input                        s_axis_tvalid,
    output                       s_axis_tready,
    input  [TDATA_WIDTH-1:0]     s_axis_tdata,
    input  [(TDATA_WIDTH/8)-1:0] s_axis_tstrb,
    input  [(TDATA_WIDTH/8)-1:0] s_axis_tkeep,
    input                        s_axis_tlast,
    input  [TID_WIDTH-1:0]       s_axis_tid,
    input  [TDEST_WIDTH-1:0]     s_axis_tdest,
    input  [TUSER_WIDTH-1:0]     s_axis_tuser,

    input                        m_axis_aclk,
    input                        m_axis_arstn,
    
    // AXI-Stream master interface
    output                       m_axis_tvalid,
    input                        m_axis_tready,
    output [TDATA_WIDTH-1:0]     m_axis_tdata,
    output [(TDATA_WIDTH/8)-1:0] m_axis_tstrb,
    output [(TDATA_WIDTH/8)-1:0] m_axis_tkeep,
    output                       m_axis_tlast,
    output [TID_WIDTH-1:0]       m_axis_tid,
    output [TDEST_WIDTH-1:0]     m_axis_tdest,
    output [TUSER_WIDTH-1:0]     m_axis_tuser
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
genvar i;

localparam ADDR_WIDTH       = $clog2(FIFO_DEPTH);
localparam STRB_WIDTH       = (TDATA_WIDTH > 8) ? TDATA_WIDTH / 8 : 1;
localparam AXIS_WIDTH       = TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH + 
                              1 + TID_WIDTH + TDEST_WIDTH + TUSER_WIDTH;

//---------------------------------------------------------------------
// Data
//---------------------------------------------------------------------

// Async FIFO interface signals
wire                        fifo_valid_i;
wire                        fifo_ready_o;
wire [AXIS_WIDTH-1:0]       fifo_data_i;

wire                        fifo_valid_o;
wire                        fifo_ready_i;
wire [AXIS_WIDTH-1:0]       fifo_data_o;

//---------------------------------------------------------------------
// TX Skid Chain Generation (Input -> Async FIFO)
//---------------------------------------------------------------------
generate
    if (TX_SKID_NUM == 0) begin : gen_tx_bypass
        assign fifo_data_i = {
            s_axis_tuser,
            s_axis_tdest,
            s_axis_tid,
            s_axis_tlast,
            s_axis_tkeep,
            s_axis_tstrb,
            s_axis_tdata
        };
        assign fifo_valid_i  = s_axis_tvalid;
        assign s_axis_tready = fifo_ready_o;
    end else begin : gen_tx_chain
        wire [AXIS_WIDTH-1:0] chain_data  [0:TX_SKID_NUM];
        wire                  chain_valid [0:TX_SKID_NUM];
        wire                  chain_ready [0:TX_SKID_NUM];

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
                .DATA_WIDTH(AXIS_WIDTH)
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
        assign fifo_data_i  = chain_data[TX_SKID_NUM];
        assign fifo_valid_i = chain_valid[TX_SKID_NUM];
        assign chain_ready[TX_SKID_NUM] = fifo_ready_o;
    end
endgenerate

//---------------------------------------------------------------------
// Async FIFO Instance
//---------------------------------------------------------------------
async_fifo #(
    .DEPTH       (FIFO_DEPTH),
    .DATA_WIDTH  (AXIS_WIDTH),
    .LOW_LATENCY (LOW_LATENCY)
) u_async_fifo (
    .w_clk_i   (s_axis_aclk),
    .w_rst_ni  (s_axis_arstn),
    .w_valid_i (fifo_valid_i),
    .w_ready_o (fifo_ready_o),
    .w_data_i  (fifo_data_i),

    .r_clk_i   (m_axis_aclk),
    .r_rst_ni  (m_axis_arstn),
    .r_valid_o (fifo_valid_o),
    .r_ready_i (fifo_ready_i),
    .r_data_o  (fifo_data_o)
);

//---------------------------------------------------------------------
// RX Skid Chain Generation (Async FIFO -> Output)
//---------------------------------------------------------------------
generate
    if (RX_SKID_NUM == 0) begin : gen_rx_bypass
        assign m_axis_tvalid = fifo_valid_o;
        assign fifo_ready_i  = m_axis_tready;
        assign m_axis_tdata  = fifo_data_o[TDATA_WIDTH-1:0];
        assign m_axis_tstrb  = fifo_data_o[TDATA_WIDTH +: STRB_WIDTH];
        assign m_axis_tkeep  = fifo_data_o[TDATA_WIDTH + STRB_WIDTH +: STRB_WIDTH];
        assign m_axis_tlast  = fifo_data_o[TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH];
        assign m_axis_tid    = fifo_data_o[TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH + 1 +: TID_WIDTH];
        assign m_axis_tdest  = fifo_data_o[TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH + 1 + TID_WIDTH +: TDEST_WIDTH];
        assign m_axis_tuser  = fifo_data_o[TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH + 1 + TID_WIDTH + TDEST_WIDTH +: TUSER_WIDTH];
    end else begin : gen_rx_chain
        wire [AXIS_WIDTH-1:0] chain_data  [0:RX_SKID_NUM];
        wire                  chain_valid [0:RX_SKID_NUM];
        wire                  chain_ready [0:RX_SKID_NUM];

        // Input from Async FIFO
        assign chain_data[0]  = fifo_data_o;
        assign chain_valid[0] = fifo_valid_o;
        assign fifo_ready_i   = chain_ready[0];

        for (i = 0; i < RX_SKID_NUM; i = i + 1) begin : gen_rx_chain_loop
            skid_buffer #(
                .DATA_WIDTH(AXIS_WIDTH)
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
        assign m_axis_tdata  = chain_data[RX_SKID_NUM][TDATA_WIDTH-1:0];
        assign m_axis_tstrb  = chain_data[RX_SKID_NUM][TDATA_WIDTH +: STRB_WIDTH];
        assign m_axis_tkeep  = chain_data[RX_SKID_NUM][TDATA_WIDTH + STRB_WIDTH +: STRB_WIDTH];
        assign m_axis_tlast  = chain_data[RX_SKID_NUM][TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH];
        assign m_axis_tid    = chain_data[RX_SKID_NUM][TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH + 1 +: TID_WIDTH];
        assign m_axis_tdest  = chain_data[RX_SKID_NUM][TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH + 1 + TID_WIDTH +: TDEST_WIDTH];
        assign m_axis_tuser  = chain_data[RX_SKID_NUM][TDATA_WIDTH + STRB_WIDTH + STRB_WIDTH + 1 + TID_WIDTH + TDEST_WIDTH +: TUSER_WIDTH];
    end
endgenerate

endmodule
