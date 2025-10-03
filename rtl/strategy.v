// Strategy.v
// Simple threshold strategy: set BUY if price < THRESHOLD,
// Set SELL if price > THRESHOLD. One-cycle pulse outputs (registered).
`timescale 1ns/1ps
module strategy #(
    parameter THRESHOLD = 32'd1000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        data_valid,  // From parser
    input  wire [31:0] price,
    input  wire [15:0] qty,

    output reg         buy,
    output reg         sell
);

    always @(posedge clk) begin
        if (rst) begin
            buy  <= 1'b0;
            sell <= 1'b0;
        end else begin
            // Default: no action unless a parsed message arrived
            buy  <= 1'b0;
            sell <= 1'b0;

            if (data_valid) begin
                if (price < THRESHOLD) begin
                    buy <= 1'b1;
                end else if (price > THRESHOLD) begin
                    sell <= 1'b1;
                end
            end
        end
    end

endmodule