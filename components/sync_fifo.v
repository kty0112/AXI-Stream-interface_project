// --------------------------------------------------------------------------
// FILE_NAME   : sync_fifo.v
// AUTHOR      : MinSeok Kim 
// DESCRIPTION : Synchronous FIFO
// --------------------------------------------------------------------------
`timescale 1ns/1ps

module sync_fifo #(
    parameter DEPTH      = 64,
    parameter DATA_WIDTH = 32
)(
    input                    clk_i,
    input                    rst_ni,

    input                    w_tvalid,
    output                   w_tready,
    input  [DATA_WIDTH-1:0]  w_tdata,

    output                   r_tvalid,
    input                    r_tready,
    output [DATA_WIDTH-1:0]  r_tdata
);

// --------------------------------------------------------------------------
// Parameters
// --------------------------------------------------------------------------
integer i;

localparam ptr = $clog2(DEPTH);

// --------------------------------------------------------------------------
// Data
// --------------------------------------------------------------------------
reg [DATA_WIDTH-1:0] fifo_buffer [0:DEPTH-1];

reg [ptr-1:0] rptr, rptr_nxt;
reg [ptr-1:0] wptr, wptr_nxt;

reg rflag, rflag_nxt;
reg wflag, wflag_nxt;

// --------------------------------------------------------------------------
// Logics
// --------------------------------------------------------------------------
wire r_hs  = r_tvalid & r_tready;
wire w_hs  = w_tvalid & w_tready;
wire full  = (wptr == rptr) & (wflag != rflag);
wire empty = (wptr == rptr) & (wflag == rflag);

assign w_tready = ~full;
assign r_tvalid = ~empty;
assign r_tdata  = fifo_buffer[rptr];

always @(*) begin
    if (wptr == DEPTH-1) begin
        wflag_nxt = ~wflag;
        wptr_nxt  = 0;
    end else begin
        wflag_nxt = wflag;
        wptr_nxt  = wptr + 1;
    end
end

always @(*) begin
    if  (rptr == DEPTH-1) begin
        rflag_nxt = ~rflag;
        rptr_nxt  = 0;
    end else begin
        rflag_nxt = rflag;
        rptr_nxt  = rptr + 1;
    end
end

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) {wptr, wflag, rptr, rflag} <= 'd0;
    else begin
        if(w_hs) {wptr, wflag} <= {wptr_nxt, wflag_nxt};
        if(r_hs) {rptr, rflag} <= {rptr_nxt, rflag_nxt};
    end
end

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) for(i=0; i<DEPTH; i=i+1) fifo_buffer[i] <= {DATA_WIDTH{1'b0}};
    else if (w_hs) fifo_buffer[wptr] <= w_tdata;
end
endmodule
