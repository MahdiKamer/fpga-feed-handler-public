`resetall
`timescale 1ns/1ps
`default_nettype none

// Rx_async_fifo.v
// Ultra-shallow asynchronous FIFO for AXI-Stream sideband
// Carries {tuser, tlast, tdata[7:0]} as a single DATA_WIDTH-bit word.
// Depth = 2 by default (very low latency).
// // Write domain: wr_clk (rx_clk from MAC)
// Read domain: rd_clk (fabric_clk)
// - din_valid is sampled in write domain, dout_valid produced in read domain.
// - rd_en should be asserted when downstream consumes the word.
// - If FIFO is full, incoming words are dropped (no backpressure to MAC).
// This matches eth_mac_1g_rgmii which does not provide RX backpressure.
module rx_async_fifo #(
    parameter DATA_WIDTH = 10, // {tuser(1), tlast(1), tdata[7:0]}
    parameter DEPTH = 2        // Ultra-shallow
) (
    input  wire                  wr_clk,
    input  wire                  rd_clk,
    input  wire                  rst,        // Active-high synchronous reset (applied to both domains)

    // Write side (rx_clk domain)
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  din_valid,
    output wire                  full,

    // Read side (fabric_clk domain)
    output reg  [DATA_WIDTH-1:0] dout,
    output reg                   dout_valid,
    input  wire                  rd_en,
    output wire                  empty
);

    // Pointer width
    localparam PTR_WIDTH = $clog2(DEPTH);

    // Storage
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Binary pointers
    reg [PTR_WIDTH:0] wr_ptr_bin = 0;
    reg [PTR_WIDTH:0] rd_ptr_bin = 0;

    // Gray pointers for CDC
    reg [PTR_WIDTH:0] wr_ptr_gray = 0;
    reg [PTR_WIDTH:0] rd_ptr_gray = 0;

    // Synchronized remote pointers
    reg [PTR_WIDTH:0] wr_ptr_gray_rdclk = 0;
    reg [PTR_WIDTH:0] wr_ptr_gray_rdclk_sync = 0;
    reg [PTR_WIDTH:0] rd_ptr_gray_wrclk = 0;
    reg [PTR_WIDTH:0] rd_ptr_gray_wrclk_sync = 0;

    // Convert binary -> gray
    function [PTR_WIDTH:0] bin2gray(input [PTR_WIDTH:0] b);
        begin
            bin2gray = (b >> 1) ^ b;
        end
    endfunction

    // Convert gray -> binary
    function [PTR_WIDTH:0] gray2bin(input [PTR_WIDTH:0] g);
        integer i;
        reg [PTR_WIDTH:0] b;
        begin
            b = g;
            for (i = 1; i <= PTR_WIDTH; i = i + 1) begin
                b[i] = b[i] ^ b[i-1];
            end
            gray2bin = b;
        end
    endfunction

    // ---------------------------
    // Write domain (wr_clk)
    // ---------------------------
    wire [PTR_WIDTH:0] wr_ptr_bin_next = wr_ptr_bin + (din_valid & ~full);

    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else begin
            if (din_valid & ~full) begin
                mem[wr_ptr_bin[PTR_WIDTH-1:0]] <= din;
                wr_ptr_bin <= wr_ptr_bin + 1;
                wr_ptr_gray <= bin2gray(wr_ptr_bin + 1);
            end
        end
    end

    // Synchronize rd pointer into write clock domain (two-stage)
    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            rd_ptr_gray_wrclk <= 0;
            rd_ptr_gray_wrclk_sync <= 0;
        end else begin
            rd_ptr_gray_wrclk <= rd_ptr_gray;
            rd_ptr_gray_wrclk_sync <= rd_ptr_gray_wrclk;
        end
    end

    // ---------------------------
    // Read domain (rd_clk)
    // ---------------------------
    //wire [PTR_WIDTH:0] rd_ptr_bin_next = rd_ptr_bin + (rd_en & ~empty);

    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
            dout        <= {DATA_WIDTH{1'b0}};
            dout_valid  <= 0;
        end else begin
            if (rd_en & ~empty) begin
                dout <= mem[rd_ptr_bin[PTR_WIDTH-1:0]];
                dout_valid <= 1'b1;
                rd_ptr_bin <= rd_ptr_bin + 1;
                rd_ptr_gray <= bin2gray(rd_ptr_bin + 1);
            end else begin
                dout_valid <= 1'b0;
            end
        end
    end

    // Synchronize write pointer into read clock domain (two-stage)
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            wr_ptr_gray_rdclk <= 0;
            wr_ptr_gray_rdclk_sync <= 0;
        end else begin
            wr_ptr_gray_rdclk <= wr_ptr_gray;
            wr_ptr_gray_rdclk_sync <= wr_ptr_gray_rdclk;
        end
    end

    // Compute full in write domain using synced read pointer
    wire [PTR_WIDTH:0] rd_ptr_bin_sync_in_wr = gray2bin(rd_ptr_gray_wrclk_sync);
    assign full = (wr_ptr_bin_next == {~rd_ptr_bin_sync_in_wr[PTR_WIDTH], rd_ptr_bin_sync_in_wr[PTR_WIDTH-1:0]});

    // Compute empty in read domain using synced write pointer
    wire [PTR_WIDTH:0] wr_ptr_bin_sync_in_rd = gray2bin(wr_ptr_gray_rdclk_sync);
    assign empty = (wr_ptr_bin_sync_in_rd == rd_ptr_bin);

endmodule

`default_nettype wire