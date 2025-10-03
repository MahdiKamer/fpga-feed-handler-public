`timescale 1ns/1ps

module tb_header_skip_parser;

    reg clk = 0;
    reg rst = 1;

    // AXI-stream into header_skip
    reg  [7:0]  s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;

    // ITCH parser outputs
    wire [63:0] order_id;
    wire [31:0] price;
    wire [15:0] quantity;
    wire        itch_valid;

    // Clock generation
    always #5 clk = ~clk;

    // ------------------------
    // DUTs
    // ------------------------
    wire [7:0]  payload_tdata;
    wire        payload_tvalid;
    wire        payload_tready;
    wire        payload_tlast;

    header_skip #(
        .HEADER_LEN(42)
    ) dut_skip (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(payload_tdata),
        .m_axis_tvalid(payload_tvalid),
        .m_axis_tready(payload_tready),
        .m_axis_tlast(payload_tlast)
    );

    itch_parser dut_parser (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(payload_tdata),
        .s_axis_tvalid(payload_tvalid),
        .s_axis_tready(payload_tready),
        .order_id(order_id),
        .price(price),
        .quantity(quantity),
        .valid(itch_valid)
    );

    assign payload_tready = 1'b1;
    reg [7:0] itch_msg [0:14];
    integer i;
    // ------------------------
    // Test sequence
    // ------------------------
    initial begin
        $dumpfile("tb_header_skip_parser.vcd");
        $dumpvars(0, tb_header_skip_parser);

        // ---- Send 15-byte ITCH 'A' message (simplified test payload)
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

        // Reset pulse
        s_axis_tdata  = 8'h0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        #50 rst = 0;

        // ---- Send 42-byte dummy Ethernet/IP/UDP header
        repeat (42) begin
            @(posedge clk);
            s_axis_tdata  <= 8'hFF; // Dummy header byte
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= 1'b0;
            while (!s_axis_tready) @(posedge clk);
        end


        for (i = 0; i < 15; i = i + 1) begin
            @(posedge clk);
            s_axis_tdata  <= itch_msg[i];
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (i == 14);
            while (!s_axis_tready) @(posedge clk);
        end

        // Stop sending
        @(posedge clk);
        s_axis_tvalid <= 0;
        s_axis_tlast  <= 0;

        // Wait some cycles for parser output
        repeat (2) @(posedge clk);
        $display("=============== tb_header_skip_parser ================");
        $display("Parsed order_id   = %h", order_id);
        $display("Parsed quantity   = %d", quantity);
        $display("Parsed price      = %d", price);
        $display("ITCH Valid        = %b", itch_valid);
        $display("============== End tb_header_skip_parser ================");
       // $display("TB: OrderID=0x%h, Qty=%0d, Price=%0d, Valid=%b",
        // Order_id, quantity, price, itch_valid);

        $finish;
    end

endmodule