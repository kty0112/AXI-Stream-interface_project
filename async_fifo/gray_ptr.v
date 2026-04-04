//---------------------------------------------------------------------
// FILE_NAME   : gray_ptr.v
// DESCRIPTION : Gray Pointer used to CDC
//---------------------------------------------------------------------   
// LOW_LATENCY
// 0 : Area Efficient Architecture with fewer registers
// 1 : High Spped Architecture with shorter critical path
//---------------------------------------------------------------------
`timescale 1ns/1ps

module gray_ptr #(
    parameter ADDR_WIDTH  = 8,
    parameter LOW_LATENCY = 1
)(
    input                 clk, rstn,
    input                 cnt_ena,
    output [ADDR_WIDTH:0] o_ptr,
    output [ADDR_WIDTH:0] o_ptr_nxt,
    output                o_addr_msb
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
integer n;

initial begin
    if(LOW_LATENCY) $display("[INFO] Gray Pointer with Low Latency Mode");
    else            $display("[INFO] Gray Pointer with Normal Mode");
end

//---------------------------------------------------------------------
// Data Description
//---------------------------------------------------------------------
reg [ADDR_WIDTH:0] gray_cnt, gray_cnt_nxt;
reg [ADDR_WIDTH:0] bin_cnt, bin_cnt_nxt;

reg addr_msb;

//---------------------------------------------------------------------
// Function Description
//---------------------------------------------------------------------

assign o_ptr      = gray_cnt;
assign o_ptr_nxt  = gray_cnt_nxt;
assign o_addr_msb = addr_msb; 
always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        gray_cnt <= 0;
        addr_msb <= 0;
    end else begin
        gray_cnt <= gray_cnt_nxt;
        addr_msb <= gray_cnt_nxt[ADDR_WIDTH] ^ gray_cnt_nxt[ADDR_WIDTH-1];
    end
end

generate
    if(LOW_LATENCY) begin
        always @(posedge clk or negedge rstn) begin
            if (!rstn) bin_cnt <= 0;
            else       bin_cnt <= bin_cnt_nxt;
        end

        always @(*) begin
            bin_cnt_nxt = bin_cnt + cnt_ena;

            // Binary to Gray            
            gray_cnt_nxt = bin_cnt_nxt ^ (bin_cnt_nxt >> 1); 
        end
    end else begin
        always @(*) begin
            // Gray to Binary
            for (n=0; n<=ADDR_WIDTH; n=n+1) 
                bin_cnt[n] = ^(gray_cnt >> n);

            bin_cnt_nxt = bin_cnt + cnt_ena;

            // Binary to Gray            
            gray_cnt_nxt = bin_cnt_nxt ^ (bin_cnt_nxt >> 1);  
        end
    end
endgenerate
endmodule
