// Timestamp_counter.v
module timestamp_counter (
    input  wire        clk,
    input  wire        rst,   // Active-high sync reset
    output reg [63:0]  ts
);
    always @(posedge clk) begin
        if (rst) ts <= 64'd0;
        else     ts <= ts + 64'd1;
    end
endmodule