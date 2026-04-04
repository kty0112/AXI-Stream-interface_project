//-------------------------------------------------------------------------------------------
// FILE_NAME   : axis_async_dwc_top.v
// Author      : Minseok Kim
// DESCRIPTION : Top module for AXI4-Stream based Asynchronous Data Width Converter (DWC).
//               Automatically instantiates Upsizer or Downsizer based on width parameters.
//-------------------------------------------------------------------------------------------
// <Performance and Design Specifications>
// 1. Protocol: AXI4-Stream compliant (TVALID/TREADY Handshake)
// 2. Throughput: Full-rate (1 word per cycle without back-pressure)
// 3. Operating Frequency (Fmax): 250MHz on FPGA (Ensured CDC stability)
// 4. Latency: Approx. 2 to 4 cycles per domain including Async FIFO and Skid Buffers
// 5. Feature Scope: 
//    - Supports Asynchronous Clock Domain Crossing (CDC)
//    - Supports both Data Width Expansion (Upsize) and Reduction (Downsize)
//    - Timing Closure optimization using Skid Buffers
//-------------------------------------------------------------------------------------------

`timescale 1ns/1ps
module axis_async_dwc_top #(
    parameter FIFO_DEPTH    = 16,
    parameter TX_WIDTH      = 32,      // Input Data Width
    parameter RX_WIDTH      = 128,       // Output Data Width
    parameter TX_SKID_NUM   = 1,        // Number of Skid Buffers on Input side
    parameter RX_SKID_NUM   = 1,        // Number of Skid Buffers on Output side
    parameter MID_SKID_NUM  = 1,        // Number of Skid Buffers between internal logics
    parameter TID_WIDTH     = 1,        // ID Signal Width
    parameter TDEST_WIDTH   = 1,        // Destination Signal Width
    parameter TUSER_WIDTH   = 1,        // User Signal Width
    parameter USE_SYNC_FIFO = 1
)(
    //-----------------------------------------------------------------
    // Slave Interface (Input Domain - s_axis_aclk)
    //-----------------------------------------------------------------
    input  wire                     s_axis_aclk,
    input  wire                     s_axis_aresetn,

    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [TX_WIDTH-1:0]      s_axis_tdata,
    input  wire [(TX_WIDTH/8)-1:0]  s_axis_tkeep,
    input  wire [(TX_WIDTH/8)-1:0]  s_axis_tstrb,
    input  wire                     s_axis_tlast,
    input  wire [TID_WIDTH-1:0]     s_axis_tid,
    input  wire [TDEST_WIDTH-1:0]   s_axis_tdest,
    input  wire [TUSER_WIDTH-1:0]   s_axis_tuser,

    //-----------------------------------------------------------------
    // Master Interface (Output Domain - m_axis_aclk)
    //-----------------------------------------------------------------
    input  wire                     m_axis_aclk,
    input  wire                     m_axis_aresetn,

    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire [RX_WIDTH-1:0]      m_axis_tdata,
    output wire [(RX_WIDTH/8)-1:0]  m_axis_tkeep,
    output wire [(RX_WIDTH/8)-1:0]  m_axis_tstrb,
    output wire                     m_axis_tlast,
    output wire [TID_WIDTH-1:0]     m_axis_tid,
    output wire [TDEST_WIDTH-1:0]   m_axis_tdest,
    output wire [TUSER_WIDTH-1:0]   m_axis_tuser
);

//---------------------------------------------------------------------
// Instance
//---------------------------------------------------------------------
generate
    if(TX_WIDTH > RX_WIDTH) begin: gen_downsizer
        axis_async_downsizer #(
            .FIFO_DEPTH     (FIFO_DEPTH),
            .TX_WIDTH       (TX_WIDTH),
            .RX_WIDTH       (RX_WIDTH),
            .TX_SKID_NUM    (TX_SKID_NUM),
            .RX_SKID_NUM    (RX_SKID_NUM),
            .MID_SKID_NUM   (MID_SKID_NUM),
            .TID_WIDTH      (TID_WIDTH),
            .TDEST_WIDTH    (TDEST_WIDTH),
            .TUSER_WIDTH    (TUSER_WIDTH),
            .USE_SYNC_FIFO  (USE_SYNC_FIFO)
        ) u_axis_async_downsizer (
            .s_axis_aclk    (s_axis_aclk),
            .s_axis_arstn   (s_axis_aresetn),
            
            .s_axis_tvalid  (s_axis_tvalid),
            .s_axis_tready  (s_axis_tready),
            .s_axis_tdata   (s_axis_tdata),
            .s_axis_tkeep   (s_axis_tkeep),
            .s_axis_tstrb   (s_axis_tstrb),
            .s_axis_tlast   (s_axis_tlast),
            .s_axis_tid     (s_axis_tid),
            .s_axis_tdest   (s_axis_tdest),
            .s_axis_tuser   (s_axis_tuser),

            .m_axis_aclk    (m_axis_aclk),
            .m_axis_arstn   (m_axis_aresetn),

            .m_axis_tvalid  (m_axis_tvalid),
            .m_axis_tready  (m_axis_tready),
            .m_axis_tdata   (m_axis_tdata),
            .m_axis_tkeep   (m_axis_tkeep),
            .m_axis_tstrb   (m_axis_tstrb),
            .m_axis_tlast   (m_axis_tlast),
            .m_axis_tid     (m_axis_tid),
            .m_axis_tdest   (m_axis_tdest),
            .m_axis_tuser   (m_axis_tuser)
        );
    end else if(RX_WIDTH > TX_WIDTH) begin: gen_upsizer
        axis_async_upsizer #(
            .FIFO_DEPTH     (FIFO_DEPTH),
            .TX_WIDTH       (TX_WIDTH),
            .RX_WIDTH       (RX_WIDTH),
            .TX_SKID_NUM    (TX_SKID_NUM),
            .RX_SKID_NUM    (RX_SKID_NUM),
            .MID_SKID_NUM   (MID_SKID_NUM),
            .TID_WIDTH      (TID_WIDTH),
            .TDEST_WIDTH    (TDEST_WIDTH),
            .TUSER_WIDTH    (TUSER_WIDTH)
        ) u_axis_async_upsizer (
            .s_axis_aclk    (s_axis_aclk),
            .s_axis_arstn   (s_axis_aresetn),
            
            .s_axis_tvalid  (s_axis_tvalid),
            .s_axis_tready  (s_axis_tready),
            .s_axis_tdata   (s_axis_tdata),
            .s_axis_tkeep   (s_axis_tkeep),
            .s_axis_tstrb   (s_axis_tstrb),
            .s_axis_tlast   (s_axis_tlast),
            .s_axis_tid     (s_axis_tid),
            .s_axis_tdest   (s_axis_tdest),
            .s_axis_tuser   (s_axis_tuser),

            .m_axis_aclk    (m_axis_aclk),
            .m_axis_arstn   (m_axis_aresetn),

            .m_axis_tvalid  (m_axis_tvalid),
            .m_axis_tready  (m_axis_tready),
            .m_axis_tdata   (m_axis_tdata),
            .m_axis_tkeep   (m_axis_tkeep),
            .m_axis_tstrb   (m_axis_tstrb),
            .m_axis_tlast   (m_axis_tlast),
            .m_axis_tid     (m_axis_tid),
            .m_axis_tdest   (m_axis_tdest),
            .m_axis_tuser   (m_axis_tuser)
        );
    end else begin: gen_bypass
        axis_async_fifo_wrapper #(
            .FIFO_DEPTH     (FIFO_DEPTH),
            .TDATA_WIDTH    (TX_WIDTH),
            .TX_SKID_NUM    (TX_SKID_NUM),
            .RX_SKID_NUM    (RX_SKID_NUM),
            .TID_WIDTH      (TID_WIDTH),
            .TDEST_WIDTH    (TDEST_WIDTH),
            .TUSER_WIDTH    (TUSER_WIDTH)
        ) u_axis_async_fifo (
            .s_axis_aclk    (s_axis_aclk),
            .s_axis_arstn   (s_axis_aresetn),
            
            .s_axis_tvalid  (s_axis_tvalid),
            .s_axis_tready  (s_axis_tready),
            .s_axis_tdata   (s_axis_tdata),
            .s_axis_tkeep   (s_axis_tkeep),
            .s_axis_tstrb   (s_axis_tstrb),
            .s_axis_tlast   (s_axis_tlast),
            .s_axis_tid     (s_axis_tid),
            .s_axis_tdest   (s_axis_tdest),
            .s_axis_tuser   (s_axis_tuser),

            .m_axis_aclk    (m_axis_aclk),
            .m_axis_arstn   (m_axis_aresetn),

            .m_axis_tvalid  (m_axis_tvalid),
            .m_axis_tready  (m_axis_tready),
            .m_axis_tdata   (m_axis_tdata),
            .m_axis_tkeep   (m_axis_tkeep),
            .m_axis_tstrb   (m_axis_tstrb),
            .m_axis_tlast   (m_axis_tlast),
            .m_axis_tid     (m_axis_tid),
            .m_axis_tdest   (m_axis_tdest),
            .m_axis_tuser   (m_axis_tuser)
        );
    end
endgenerate
endmodule