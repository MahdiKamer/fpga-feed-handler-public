// Timestamp_latch.v
module timestamp_latch (
    input  wire        clk,
    input  wire        rst,

    input  wire        tx_first_pulse,
    input  wire        rx_first_pulse,

    input  wire [63:0] ts_in,

    output reg  [63:0] ts_tx,
    output reg  [63:0] ts_rx,
    output reg         ts_valid,
    input  wire        ts_clear
);

    reg tx_seen;
    reg rx_seen;

    always @(posedge clk) begin
        if (rst || ts_clear) begin
            tx_seen <= 1'b0;
            rx_seen <= 1'b0;
            ts_valid <= 1'b0;
            ts_tx <= 64'd0;
            ts_rx <= 64'd0;
        end else begin
            ts_valid <= 1'b0;
            if (tx_first_pulse && !tx_seen) begin
                tx_seen <= 1'b1;
                ts_tx <= ts_in;
            end
            if (rx_first_pulse && !rx_seen) begin
                rx_seen <= 1'b1;
                ts_rx <= ts_in;
            end
            if (tx_seen && rx_seen) begin
                ts_valid <= 1'b1; // One-cycle pulse
            end
        end
    end
endmodule