`timescale 1ns/1ps
module tb_top_loopback;

    // Clock & reset
    logic clk = 0;
    logic rst = 1;

    // Clock generation
    always #5 clk = ~clk; // 100MHz

    initial begin
        #20 rst = 0;       // Release reset
    end

    // =====================================================================
    // Expected values from pl_tx_fsm_full
    localparam [63:0] EXP_ORDER_ID = 64'h0102030405060708;
    localparam [15:0] EXP_QTY      = 16'd100;
    localparam [31:0] EXP_PRICE    = 32'd10000;

    // ------------------------------------------------------------------------
    // TX path : pl_header_inserter --> pl_tx_fsm_full
    // ------------------------------------------------------------------------
    logic [7:0] hdr_tdata;
    logic       hdr_tvalid, hdr_tready, hdr_tlast;
    logic [7:0] pl_payload_tdata;
    logic       pl_payload_tvalid, pl_payload_tready, pl_payload_tlast;
    logic       pl_first_byte_pulse;
    logic       start_tx_pulse;

    pl_header_inserter hdr_ins (
        .clk(clk), .rst(rst),
        .payload_in_tdata(pl_payload_tdata),
        .payload_in_tvalid(pl_payload_tvalid),
        .payload_in_tready(pl_payload_tready),
        .payload_in_tlast(pl_payload_tlast),
        // Header_skip (s_axis) ---> pl_header_inserter (m_axis)
        .m_axis_tdata(hdr_tdata),
        .m_axis_tvalid(hdr_tvalid),
        .m_axis_tready(hdr_tready),
        .m_axis_tlast(hdr_tlast)
    );

    pl_tx_fsm_full tx_fsm (
        .clk(clk), .rst(rst),
        .start_tx_pulse(start_tx_pulse),
        .payload_out_tvalid(pl_payload_tvalid),
        .payload_out_tready(pl_payload_tready),
        .payload_out_tdata(pl_payload_tdata),
        .payload_out_tlast(pl_payload_tlast),
        .first_byte_pulse(pl_first_byte_pulse)
    );

    // ------------------------------------------------------------------------
    // RX: header_skip --> itch_parser --> strategy --> order_gen
    // ------------------------------------------------------------------------
    logic [7:0]  payload_tdata;
    logic        payload_tvalid, payload_tready, payload_tlast;

    header_skip #(.HEADER_LEN(42)) skip_inst (
        .clk(clk), .rst(rst),
        // Header_skip (s_axis) ---> pl_header_inserter (m_axis)
        .s_axis_tdata(hdr_tdata),
        .s_axis_tvalid(hdr_tvalid),
        .s_axis_tready(hdr_tready),
        .s_axis_tlast(hdr_tlast),
        .m_axis_tdata(payload_tdata),
        .m_axis_tvalid(payload_tvalid),
        .m_axis_tready(payload_tready),
        .m_axis_tlast(payload_tlast)
    );

    logic [63:0] parsed_order_id;
    logic        itch_valid;
    logic [15:0] parsed_qty;
    logic [31:0] parsed_price;
    itch_parser parser_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(payload_tdata),
        .s_axis_tvalid(payload_tvalid),
        .s_axis_tready(payload_tready),
        .order_id(parsed_order_id),
        .price(parsed_price),
        .quantity(parsed_qty),
        .valid(itch_valid)
    );

    logic buy, sell;

    strategy #(.THRESHOLD(32'd1000)) strat (
        .clk(clk), .rst(rst),
        .data_valid(itch_valid),
        .price(parsed_price),
        .qty(parsed_qty),
        .buy(buy), .sell(sell)
    );

    logic        order_valid;
    logic [31:0] order_packet;
    order_gen ord (
        .clk(clk), .rst(rst),
        .buy(buy), .sell(sell),
        .qty(parsed_qty),
        .order_packet(order_packet),
        .order_valid(order_valid)
    );


    // =====================================================================
    // Stimulus
    initial begin
        start_tx_pulse = 0;
        #30;
        start_tx_pulse = 1;
        #10;
        start_tx_pulse = 0;
    end

    // =====================================================================
    // Timeout for safety
    initial begin
        #5000;
        $fatal(1, "TIMEOUT: Order was not generated!");
    end

    // =====================================================================
    // Check and display results
    always @(posedge clk) begin
        if (order_valid) begin
            if (parsed_order_id !== EXP_ORDER_ID)
                $fatal(1, "Order ID mismatch! Expected %h, got %h", EXP_ORDER_ID, parsed_order_id);
            if (parsed_qty !== EXP_QTY)
                $fatal(1, "Quantity mismatch! Expected %d, got %d", EXP_QTY, parsed_qty);
            if (parsed_price !== EXP_PRICE)
                $fatal(1, "Price mismatch! Expected %d, got %d", EXP_PRICE, parsed_price);

            $display("=============== tb_top_loopback ===============");
            $display("Parsed order_id   = %016h", parsed_order_id);
            $display("Parsed quantity   = %5d", parsed_qty);
            $display("Parsed price      = %8d", parsed_price);
            $display("Order packet      = %08h (valid=%0d)", order_packet, order_valid);
            $display("============== End tb_top_loopback ===============");
            $finish;
        end
    end

endmodule