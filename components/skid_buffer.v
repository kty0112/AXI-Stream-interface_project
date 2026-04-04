//---------------------------------------------------------------------
// FILE_NAME   : skid_buffer.v
// DESCRIPTION : Simple Skid Buffer
//---------------------------------------------------------------------

`timescale 1ns/1ps
module skid_buffer #(
    parameter DATA_WIDTH = 8
)(
    input                   clk_i, 
    input                   rst_ni,

    input                   s_valid_i,
    output                  s_ready_o,
    input  [DATA_WIDTH-1:0] s_data_i,

    output                  m_valid_o,
    input                   m_ready_i,
    output [DATA_WIDTH-1:0] m_data_o
);

//---------------------------------------------------------------------
// Parameters
//---------------------------------------------------------------------
localparam PIPE = 1'b0, SKID = 1'b1;

//---------------------------------------------------------------------
// Data 
//---------------------------------------------------------------------
reg state, state_nxt;

wire m_hs    = m_valid_o & m_ready_i;
wire s_hs    = s_valid_i & s_ready_o;
wire m_stall = m_valid_o & !m_ready_i;
wire s_stall = s_valid_i & !s_ready_o;

reg s_ready_o_reg;
reg m_valid_o_reg, m_valid_o_skid_reg;

reg [DATA_WIDTH-1:0] m_data_o_reg, m_data_o_skid_reg;

//---------------------------------------------------------------------
// Logics
//---------------------------------------------------------------------

// State Logic
//---------------------------------------------------------------------
always @(*) begin
    state_nxt = state;
    case(state)
    PIPE : if(m_stall) state_nxt = SKID;
    SKID : if(m_ready_i) state_nxt = PIPE;
    endcase
end

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) state <= PIPE;
    else        state <= state_nxt;
end

// Slave Interface
//---------------------------------------------------------------------
assign s_ready_o = s_ready_o_reg;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) s_ready_o_reg <= 1'b1;
    else begin
        case(state)
        PIPE : s_ready_o_reg <= m_stall ? 1'b0 : 1'b1;
        SKID : s_ready_o_reg <= m_ready_i ? 1'b1 : 1'b0;
        endcase
    end
end

// Skid Register
//---------------------------------------------------------------------
always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        m_valid_o_skid_reg <= 1'b0;
        m_data_o_skid_reg  <= {DATA_WIDTH{1'b0}};
    end else if(m_stall&(state==PIPE)) begin
        m_valid_o_skid_reg <= s_valid_i;
        m_data_o_skid_reg  <= s_data_i;
    end
end

// Master Interface
//---------------------------------------------------------------------
assign m_valid_o = m_valid_o_reg;
assign m_data_o  = m_data_o_reg;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        m_valid_o_reg <= 1'b0;
        m_data_o_reg  <= {DATA_WIDTH{1'b0}};
    end else begin
        case(state)
        PIPE : begin
            if(!m_stall) begin
                m_valid_o_reg <= s_stall ? 1'b0 : s_valid_i;
                m_data_o_reg  <= s_data_i ;
            end       
        end
        SKID : begin
            if(m_ready_i) begin
                m_valid_o_reg <= m_valid_o_skid_reg;
                m_data_o_reg  <= m_data_o_skid_reg;
            end
        end
        endcase
    end
end
endmodule
