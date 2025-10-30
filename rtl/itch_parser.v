// Itch_parser.v
// Simple ITCH "A" (Add Order) parser that expects 15 bytes:
// Byte[0] = 'A' (0x41), Byte[1..8] = order_id (8 bytes),
// Byte[9..10] = quantity (2 bytes), Byte[11..14] = price (4 bytes).
// // When a full message is captured, parser asserts valid for one cycle
// And outputs order_id, price (32-bit), quantity (16-bit).
// // Note: This is a minimal parser for demo/testing. Extend for other
// Message types, variable lengths, or packet boundary handling.
`timescale 1ns/1ps
module itch_parser (
    input  wire        clk,
    input  wire        rst,

    // AXI-Stream like byte input (8-bit)
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output reg         s_axis_tready,

    // Parsed outputs
    output reg [63:0]  order_id,
    output reg [31:0]  price,
    output reg [15:0]  quantity,
    output reg         valid
);

    // Parameters
    localparam TOTAL_BYTES = 15; // Including message type byte at index 0

    reg [3:0]   byte_count;       // 0..14
    reg [7:0]   buffer [0:TOTAL_BYTES-1];

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            byte_count    <= 3'd0;
            s_axis_tready <= 1'b1;
            valid         <= 1'b0;
            order_id      <= 64'd0;
            price         <= 32'd0;
            quantity      <= 16'd0;
            for (i=0;i<TOTAL_BYTES;i=i+1) buffer[i] <= 8'd0;
        end else begin
            valid <= 1'b0; // Default: valid only one cycle when a message completes

            // Simple always-ready policy (can be changed for backpressure)
            s_axis_tready <= 1'b1;

            if (s_axis_tvalid && s_axis_tready) begin
                // Store incoming byte
                buffer[byte_count] <= s_axis_tdata;
                byte_count <= byte_count + 1;

                // If we just stored the last byte, try to decode
                if (byte_count == TOTAL_BYTES-1) begin

                    // Check message type at buf[0]
                    if (buffer[0] == 8'h41) begin // Unicode 'A'
                        // Build order_id from bytes [1..8] (big-endian)
                        order_id <= { buffer[1], buffer[2], buffer[3], buffer[4],
                                      buffer[5], buffer[6], buffer[7], buffer[8] };
                        // Quantity bytes [9,10]
                        quantity <= { buffer[9], buffer[10] };
                        // Price bytes [11..14]
                        // Instead of adding a check register to see if buffer[14] is load then make the price, the direct AXIS data inserted here to avoid one cycle latency.
                        price <= { buffer[11], buffer[12], buffer[13], s_axis_tdata };
                        valid <= 1'b1;
                    end else begin
                        // Unknown type: ignore (you can extend to other types)
                        valid <= 1'b0;
                    end
                    byte_count <= 0; // Ready for next message
                end
            end
        end
    end

endmodule