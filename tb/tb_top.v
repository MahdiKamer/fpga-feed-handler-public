`timescale 1ns/1ps

module tb_top;

    reg clk = 0;
    reg rst = 1;

    // Wires to DUT
    wire [31:0] order_packet;
    wire        order_valid;

    // AXIS stream signals
    reg  [7:0]  s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;

    // Instantiate parser + strategy + order_gen only (skip MAC for now)
    wire [63:0] order_id;
    wire [31:0] price;
    wire [15:0] quantity;
    wire        itch_valid;
    wire        buy, sell;

    itch_parser dut_parser (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .order_id(order_id),
        .price(price),
        .quantity(quantity),
        .valid(itch_valid)
    );

    strategy #(.THRESHOLD(32'd1000)) dut_strategy (
        .clk(clk),
        .rst(rst),
        .data_valid(itch_valid),
        .price(price),
        .qty(quantity),
        .buy(buy),
        .sell(sell)
    );

    order_gen dut_order (
        .clk(clk),
        .rst(rst),
        .buy(buy),
        .sell(sell),
        .qty(quantity),
        .order_packet(order_packet),
        .order_valid(order_valid)
    );

    // Clock gen
    always #5 clk = ~clk; // 100 MHz

    // Stimulus
    reg [7:0] itch_msg [0:14];
    integer i;

    initial begin
        // ITCH "A" Add Order message (15 bytes total)
        // Format: ['A'], [order_id 8 bytes], [qty 2 bytes], [price 4 bytes]
        itch_msg[0]  = 8'h41; // 'A' Unicode
        itch_msg[1]  = 8'h01; // Order_id[63:56]
        itch_msg[2]  = 8'h02;
        itch_msg[3]  = 8'h03;
        itch_msg[4]  = 8'h04;
        itch_msg[5]  = 8'h05;
        itch_msg[6]  = 8'h06;
        itch_msg[7]  = 8'h07;
        itch_msg[8]  = 8'h08; // Order_id[7:0]
        itch_msg[9]  = 8'h00; // Qty high
        itch_msg[10] = 8'h64; // Qty low = 100
        itch_msg[11] = 8'h00; // Price = 0x00002710 = 10000
        itch_msg[12] = 8'h00;
        itch_msg[13] = 8'h27;
        itch_msg[14] = 8'h10;

        // Reset
        s_axis_tdata  = 8'd0;
        s_axis_tvalid = 1'b0;
        #50;
        rst = 0;

        // Drive ITCH bytes one per cycle
        @(posedge clk);
        for (i=0; i<15; i=i+1) begin
            @(posedge clk);
            s_axis_tdata  <= itch_msg[i];
            s_axis_tvalid <= 1'b1;
            // Wait until parser accepts (here always-ready)
            while (!s_axis_tready) @(posedge clk);
        end
        @(posedge clk);
        s_axis_tvalid <= 1'b0;

        // Wait for outputs
        #21;
        $display("=============== tb_top ================");
        $display("Parsed order_id   = %h", order_id);
        $display("Parsed quantity   = %d", quantity);
        $display("Parsed price      = %d", price);
        $display("Order packet      = %h (valid=%b)", order_packet, order_valid);
        $display("=============== End tb_top ================");
        $finish;
    end

endmodule