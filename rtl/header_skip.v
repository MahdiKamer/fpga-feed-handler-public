// AXI-Stream header skipper: drops the first HEADER_LEN bytes of each packet.
// Useful for Ethernet/IP/UDP headers before ITCH payload.
`timescale 1ns/1ps
module header_skip #(
    parameter HEADER_LEN = 42
)(
    input  wire        clk,
    input  wire        rst,

    // AXIS input
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // AXIS output (payload only)
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);

    reg [15:0] byte_count;
    reg dropping;

    assign s_axis_tready = m_axis_tready; // Simple backpressure

    always @(posedge clk) begin
        if (rst) begin
            byte_count    <= 0;
            dropping      <= 1'b1;
            m_axis_tdata  <= 0;
            m_axis_tvalid <= 0;
            m_axis_tlast  <= 0;
        end else begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                if (dropping) begin
                    if (byte_count == HEADER_LEN-1) begin
                        // Finished skipping header, next byte is payload
                        dropping   <= 1'b0;
                        byte_count <= 0;
                    end else begin
                        byte_count <= byte_count + 1;
                    end
                end else begin
                    // Forward payload
                    m_axis_tdata  <= s_axis_tdata;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast  <= s_axis_tlast;

                    if (s_axis_tlast) begin
                        dropping   <= 1'b1; // Reset for next packet
                        byte_count <= 0;
                    end
                end
            end
        end
    end

endmodule