//---------------------------------------------------------------------
// FILE_NAME   : synchronizer.v
// DESCRIPTION : verilog code of simple synchronizer 
//---------------------------------------------------------------------

`timescale 1ns/1ps
module synchronizer #(
    parameter DEPTH = 2,
    parameter DATA_WIDTH = 1
)(
    input                   clk, rstn,
    input  [DATA_WIDTH-1:0] async_din,
    output [DATA_WIDTH-1:0] sync_dout
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
integer n;

initial begin
    if(DEPTH < 2) $fatal(1, "Depth of register in synchronizer is smaller than 2 : %0d", DEPTH);
end

//---------------------------------------------------------------------
// Data
//---------------------------------------------------------------------
reg [DATA_WIDTH-1:0] sync_ff [0:DEPTH-1];

//---------------------------------------------------------------------
// Logics
//---------------------------------------------------------------------
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        for(n=0; n<DEPTH; n=n+1) sync_ff[n] <= 0;
    end else begin
        for(n=0; n<DEPTH; n=n+1) sync_ff[n] <= (n == 0) ? async_din : sync_ff[n-1];
    end
end

assign sync_dout = sync_ff[DEPTH-1];
endmodule
