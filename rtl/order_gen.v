// Order_gen.v
// Simple scalar order packet generator for debug and TX-stubbing.
// Produces a 32-bit "order_packet" and one-cycle order_valid when a buy/sell is requested.
// // Format (32-bit):
// [31:16] = opcode (0xB001 = BUY, 0xC001 = SELL)
// [15: 0] = quantity

`timescale 1ns/1ps
module order_gen (
    input  wire        clk,
    input  wire        rst,
    input  wire        buy,
    input  wire        sell,
    input  wire [15:0] qty,

    output reg  [31:0] order_packet,
    output reg         order_valid
);

    localparam OPCODE_BUY  = 16'hB001;
    localparam OPCODE_SELL = 16'hC001;

    always @(posedge clk) begin
        if (rst) begin
            order_packet <= 32'd0;
            order_valid  <= 1'b0;
        end else begin
            order_valid <= 1'b0; // Default no valid

            if (buy) begin
                order_packet <= {OPCODE_BUY, qty};
                order_valid  <= 1'b1;
            end else if (sell) begin
                order_packet <= {OPCODE_SELL, qty};
                order_valid  <= 1'b1;
            end
        end
    end

endmodule