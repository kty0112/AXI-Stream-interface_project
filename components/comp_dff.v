//---------------------------------------------------------------------
// FILE_NAME   : comp_dff.v
// DESCRIPTION : Complement 1-bit D-FF
//---------------------------------------------------------------------

`timescale 1ns/1ps
module comp_dff #(
    parameter RESET_VAL = 1'b0
)(
    input      clk, 
    input      rstn,
    input      d,
    output reg q,
    output reg q_n
);

//---------------------------------------------------------------------
// Function Description
//---------------------------------------------------------------------
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin
        {q, q_n} <= {RESET_VAL, ~RESET_VAL};
    end else begin
        {q, q_n} <= {d, ~d};
    end
end

endmodule
