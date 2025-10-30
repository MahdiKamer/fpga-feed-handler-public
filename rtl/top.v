`resetall
`timescale 1ns/1ps
`default_nettype none

// Top.v - Z7-P PL Ethernet HFT skeleton (Option B: FIFO wrapper)
// Author : Mahdi Kamer

module top (
    // Physical clock + key
    input  wire         clk_200_p,
    input  wire         clk_200_n,
    input  wire         pl_key_n,

    // PL-side RGMII Ethernet PHY interface (PHY2)
    input  wire         rgmii_rx_clk,
    input  wire         rgmii_rx_ctl,
    input  wire  [3:0]  rgmii_rxd,
    output wire         rgmii_tx_clk,
    output wire         rgmii_tx_ctl,
    output wire  [3:0]  rgmii_txd,

    // PHY management
    output wire         phy2_mdc,
    inout  wire         phy2_mdio,
    output wire         phy2_reset
);

    // ------------------------------------------------------------------------
    // Clocking
    // ------------------------------------------------------------------------
    wire fabric_clk;
    wire clk_wiz_locked;
    wire gtx_clk90;     // 125 MHz 90-deg phase shifted clock for MAC

    clk_wiz_0 clk_wiz_inst (
        .clk_in1_p(clk_200_p),
        .clk_in1_n(clk_200_n),
        .clk_out1(fabric_clk),
        .clk_out2(gtx_clk90),
        .reset(1'b0),
        .locked(clk_wiz_locked)
    );
    // ------------------------------------------------------------------------
    // RX clock buffer
    // ------------------------------------------------------------------------
    wire rgmii_rx_clk_ibuf;
    wire rgmii_rx_clk_bufg;

    // Input buffer
    IBUF #(
        .IOSTANDARD("LVCMOS18")
    ) IBUF_rgmii_rx_clk (
        .I(rgmii_rx_clk),
        .O(rgmii_rx_clk_ibuf)
    );

    // Global buffer
    BUFG BUFG_rgmii_rx_clk (
        .I(rgmii_rx_clk_ibuf),
        .O(rgmii_rx_clk_bufg)
    );


    // ------------------------------------------------------------------------
    // Reset stretcher (synchronous reset generator)
    // ------------------------------------------------------------------------
    wire rst_sync;
    reset_sync #(.STRETCH_CYCLES(32)) rst_gen (
        .clk(fabric_clk),
        .pll_locked(clk_wiz_locked),
        .rst(rst_sync)
    );

    // Expose fabric reset to modules that expect logic_rst
    //wire fabric_rst = rst_sync;

    // ------------------------------------------------------------------------
    // PL user key -> start_tx_pulse (one-shot on button press)
    // ------------------------------------------------------------------------
    reg pl_key_meta, pl_key_sync, pl_key_prev /* Synthesis syn_keep = 1 */;
    reg start_tx_pulse_reg;
    always @(posedge fabric_clk) begin
        pl_key_meta <= pl_key_n;
        pl_key_sync <= pl_key_meta;
        pl_key_prev <= pl_key_sync;
        start_tx_pulse_reg <= 1'b0;
        if (pl_key_prev == 1'b1 && pl_key_sync == 1'b0)
            start_tx_pulse_reg <= 1'b1;
        if (rst_sync) begin
            pl_key_meta <= 1'b1;
            pl_key_sync <= 1'b1;
            pl_key_prev <= 1'b1;
            start_tx_pulse_reg <= 1'b0;
        end
    end
    wire start_tx_pulse = start_tx_pulse_reg;

    // ------------------------------------------------------------------------
    // MDIO master + PHY config (auto-detect PHY addr)
    // ------------------------------------------------------------------------
    wire mdio_cmd_valid, mdio_cmd_read;
    wire [4:0] mdio_cmd_phy, mdio_cmd_reg;
    wire [15:0] mdio_cmd_wdata;
    wire mdio_busy, mdio_ack;
    wire [15:0] mdio_rdata;

    mdio_master #(.MDC_DIV(50)) mdio_inst (
        .clk(fabric_clk),
        .rst(rst_sync),
        .cmd_valid(mdio_cmd_valid),
        .cmd_read(mdio_cmd_read),
        .cmd_phyaddr(mdio_cmd_phy),
        .cmd_regaddr(mdio_cmd_reg),
        .cmd_wdata(mdio_cmd_wdata),
        .busy(mdio_busy),
        .ack(mdio_ack),
        .rdata(mdio_rdata),
        .mdc(phy2_mdc),
        .mdio(phy2_mdio)
    );

    // One-shot for start_cfg after rst_sync deasserts
    reg rst_sync_d1, rst_sync_d2, rst_sync_d3 /* Synthesis syn_keep = 1 */;
    always @(posedge fabric_clk) begin
        rst_sync_d1 <= rst_sync;
        rst_sync_d2 <= rst_sync_d1;
        rst_sync_d3 <= rst_sync_d2;
    end
    wire rst_released = ~rst_sync_d2 & rst_sync_d3;

    wire cfg_busy, cfg_done, link_up, cfg_error;
    phy_config_sm_onehot phy_cfg_inst (
        .clk(fabric_clk),
        .rst(rst_sync),
        .mdio_cmd_valid(mdio_cmd_valid),
        .mdio_cmd_read(mdio_cmd_read),
        .mdio_cmd_phy(mdio_cmd_phy),
        .mdio_cmd_reg(mdio_cmd_reg),
        .mdio_cmd_wdata(mdio_cmd_wdata),
        .mdio_busy(mdio_busy),
        .mdio_ack(mdio_ack),
        .mdio_rdata(mdio_rdata),
        .start_cfg(rst_released),
        .cfg_busy(cfg_busy),
        .cfg_done(cfg_done),
        .link_up(link_up),
        .error(cfg_error)
    );

    // Hold PHY in reset while fabric reset asserted
    reg phy_reset_reg;
    always @(posedge fabric_clk) begin
        if (rst_sync) phy_reset_reg <= 1'b0;
        else phy_reset_reg <= 1'b1;
    end
    assign phy2_reset = phy_reset_reg;

    // -----------------------------------------------------------------------------
    // RGMII Ethernet MAC with FIFO wrapper (eth_mac_1g_rgmii_fifo)
    // - This wrapper exposes rx_axis_* on fabric_clk domain when logic_clk = fabric_clk
    // -----------------------------------------------------------------------------

    wire [7:0]  rx_axis_tdata;
    wire        rx_axis_tvalid, rx_axis_tlast, rx_axis_tready;

    wire [7:0]  tx_axis_tdata;
    wire        tx_axis_tvalid, tx_axis_tready, tx_axis_tlast;

    // Unused outputs captured into a dummy bundle to reduce warnings
    wire tx_error_underflow;
    wire rx_error_bad_frame;
    wire rx_error_bad_fcs;
    wire tx_fifo_overflow;
    wire tx_fifo_bad_frame;
    wire tx_fifo_good_frame;
    wire rx_fifo_overflow;
    wire rx_fifo_bad_frame;
    wire rx_fifo_good_frame;
    wire [1:0] speed; // If MAC wrapper reports link speed

    eth_mac_1g_rgmii_fifo #(
        .TARGET("XILINX"),
        .IODDR_STYLE("IODDR"),
        .CLOCK_INPUT_STYLE("BUFG"),
        .ENABLE_PADDING(1),
        .MIN_FRAME_LENGTH(64),
        .TX_FIFO_DEPTH(16),       // Reduce TX FIFO depth to 256 words
        .RX_FIFO_DEPTH(8),       // Reduce RX FIFO depth to 256 words
        // Disable whole-frame buffering if enabled
        .TX_FRAME_FIFO(0),
        .RX_FRAME_FIFO(0)
    ) eth_mac_1g_rgmii_fifo_inst (
        // MAC GTX/PLL inputs
        .gtx_clk        (fabric_clk),
        .gtx_clk90      (gtx_clk90),
        .gtx_rst        (rst_sync),
        .logic_clk      (fabric_clk),
        .logic_rst      (rst_sync),

        // RGMII interface
        .rgmii_txd      (rgmii_txd),
        .rgmii_tx_ctl   (rgmii_tx_ctl),
        .rgmii_tx_clk   (rgmii_tx_clk),
        .rgmii_rxd      (rgmii_rxd),
        .rgmii_rx_ctl   (rgmii_rx_ctl),
        .rgmii_rx_clk   (rgmii_rx_clk_bufg),// (rgmii_rx_clk),

        // AXI-stream TX (fabric --> Ethernet)
        .tx_axis_tdata  (tx_axis_tdata),
        .tx_axis_tvalid (tx_axis_tvalid),
        .tx_axis_tready (tx_axis_tready),
        .tx_axis_tlast  (tx_axis_tlast),
        .tx_axis_tkeep  (1'b1),      // Always send full byte
        .tx_axis_tuser  (1'b0),

        // AXI-stream RX (Ethernet --> fabric)
        .rx_axis_tdata  (rx_axis_tdata),
        .rx_axis_tvalid (rx_axis_tvalid),
        .rx_axis_tlast  (rx_axis_tlast),
        .rx_axis_tuser  (),          // Not used
        .rx_axis_tkeep  (),          // Not used (byte always valid)
        .rx_axis_tready (rx_axis_tready),

        // Status / error outputs
        .tx_error_underflow (tx_error_underflow),
        .rx_error_bad_frame (rx_error_bad_frame),
        .rx_error_bad_fcs   (rx_error_bad_fcs),
        .tx_fifo_overflow   (tx_fifo_overflow),
        .tx_fifo_bad_frame  (tx_fifo_bad_frame),
        .tx_fifo_good_frame (tx_fifo_good_frame),
        .rx_fifo_overflow   (rx_fifo_overflow),
        .rx_fifo_bad_frame  (rx_fifo_bad_frame),
        .rx_fifo_good_frame (rx_fifo_good_frame),
        .speed              (speed), //0X2 if phy configured for 1Gbps

        // Configuration inputs
        .cfg_ifg        (8'd12),     // Default inter-frame gap (12 byte times)
        .cfg_tx_enable  (1'b1),      // Enable TX
        .cfg_rx_enable  (1'b1)       // Enable RX
    );

    // ------------------------------------------------------------------------
    // RX path (now simplified because the FIFO wrapper presents rx_axis_* in
    // The fabric_clk domain): pack directly into header_skip
    // ------------------------------------------------------------------------
    wire header_s_axis_tready;
    assign rx_axis_tready = header_s_axis_tready;
    wire header_s_axis_tvalid = rx_axis_tvalid;
    wire [7:0] header_s_axis_tdata = rx_axis_tdata;
    wire header_s_axis_tlast = rx_axis_tlast;
    // Header_s_axis_tuser is not used

    // Header_skip consumes the stream in fabric_clk domain and strips headers.
    wire [7:0]  payload_tdata;
    wire        payload_tvalid, payload_tready, payload_tlast;

    header_skip #(.HEADER_LEN(42)) skip_inst (
        .clk(fabric_clk), .rst(rst_sync),
        .s_axis_tdata(header_s_axis_tdata),
        .s_axis_tvalid(header_s_axis_tvalid),
        .s_axis_tready(header_s_axis_tready),
        .s_axis_tlast(header_s_axis_tlast),
        .m_axis_tdata(payload_tdata),
        .m_axis_tvalid(payload_tvalid),
        .m_axis_tready(payload_tready),
        .m_axis_tlast(payload_tlast)
    );

    // ------------------------------------------------------------------------
    // Application RX pipeline (fabric_clk domain)
    // ------------------------------------------------------------------------
    wire [63:0] order_id;
    wire [31:0] price;
    wire [15:0] quantity;
    wire        itch_valid;

    itch_parser parser_inst (
        .clk(fabric_clk),
        .rst(rst_sync),
        .s_axis_tdata(payload_tdata),
        .s_axis_tvalid(payload_tvalid),
        .s_axis_tready(payload_tready),
        .order_id(order_id),
        .price(price),
        .quantity(quantity),
        .valid(itch_valid)
    );

    wire buy, sell;
    strategy #(.THRESHOLD(32'd1000)) strat (
        .clk(fabric_clk), .rst(rst_sync),
        .data_valid(itch_valid),
        .price(price),
        .qty(quantity),
        .buy(buy), .sell(sell)
    );

    wire        order_valid;
    wire [31:0] order_packet;
    order_gen ord (
        .clk(fabric_clk), .rst(rst_sync),
        .buy(buy), .sell(sell),
        .qty(quantity),
        .order_packet(order_packet),
        .order_valid(order_valid)
    );

    // ------------------------------------------------------------------------
    // TX path
    // ------------------------------------------------------------------------
    wire [7:0] hdr_tdata;
    wire       hdr_tvalid, hdr_tready, hdr_tlast;
    wire [7:0] pl_payload_tdata;
    wire       pl_payload_tvalid, pl_payload_tready, pl_payload_tlast;
    wire       pl_first_byte_pulse;

    pl_header_inserter hdr_ins (
        .clk(fabric_clk), .rst(rst_sync),
        .payload_in_tdata(pl_payload_tdata),
        .payload_in_tvalid(pl_payload_tvalid),
        .payload_in_tready(pl_payload_tready),
        .payload_in_tlast(pl_payload_tlast),
        .m_axis_tdata(hdr_tdata),
        .m_axis_tvalid(hdr_tvalid),
        .m_axis_tready(hdr_tready),
        .m_axis_tlast(hdr_tlast)
    );

    pl_tx_fsm_full tx_fsm (
        .clk(fabric_clk), .rst(rst_sync),
        .start_tx_pulse(start_tx_pulse),
        .payload_out_tvalid(pl_payload_tvalid),
        .payload_out_tready(pl_payload_tready),
        .payload_out_tdata(pl_payload_tdata),
        .payload_out_tlast(pl_payload_tlast),
        .first_byte_pulse(pl_first_byte_pulse)
    );

    assign tx_axis_tdata  = hdr_tdata;
    assign tx_axis_tvalid = hdr_tvalid;
    assign hdr_tready     = tx_axis_tready;
    assign tx_axis_tlast  = hdr_tlast;

    // ------------------------------------------------------------------------
    // Timestamping
    // ------------------------------------------------------------------------
    wire [63:0] ts;
    timestamp_counter ts_cnt (.clk(fabric_clk), .rst(rst_sync), .ts(ts));

    reg tx_seen, tx_first_pulse;
    always @(posedge fabric_clk) begin
        if (rst_sync) begin tx_seen <= 0; tx_first_pulse <= 0; end
        else begin
            tx_first_pulse <= 0;
            if (hdr_tvalid && hdr_tready && !tx_seen) begin
                tx_first_pulse <= 1; tx_seen <= 1;
            end
            if (hdr_tlast && hdr_tvalid && hdr_tready) tx_seen <= 0;
        end
    end

    reg rx_seen, rx_first_pulse;
    always @(posedge fabric_clk) begin
        if (rst_sync) begin rx_seen <= 0; rx_first_pulse <= 0; end
        else begin
            rx_first_pulse <= 0;
            if (payload_tvalid && payload_tready && !rx_seen) begin
                rx_first_pulse <= 1; rx_seen <= 1;
            end
            if (payload_tlast && payload_tvalid && payload_tready) rx_seen <= 0;
        end
    end

    wire [63:0] ts_tx, ts_rx;
    wire ts_valid;
    reg ts_clear;

    timestamp_latch ts_lat (
        .clk(fabric_clk), .rst(rst_sync),
        .tx_first_pulse(tx_first_pulse),
        .rx_first_pulse(rx_first_pulse),
        .ts_in(ts),
        .ts_tx(ts_tx),
        .ts_rx(ts_rx),
        .ts_valid(ts_valid),
        .ts_clear(ts_clear)
    );


    // ======================================================
    // Measure rgmii_rx_clk frequency in fabric_clk domain
    // ======================================================
    wire [31:0] rgmii_measured_freq;
    rgmii_freq_meter_500ms rgmii_rx_freq_inst(
    .fabric_clk(fabric_clk),
    .rst(rst_sync),
    .rgmii_rx_clk_bufg(rgmii_rx_clk_bufg),
    .rgmii_freq_hz(rgmii_measured_freq)     // Measured frequency in Hz
);


    // ------------------------------------------------------------------------
    // ILA (debug) - expanded probes
    // ------------------------------------------------------------------------
    ila_0 ila_dbg (
        .clk(fabric_clk),

        // Timing stamps
        .probe0(ts_tx[63:0]),
        .probe1(ts_rx[63:0]),

        // Parsed fields
        .probe2(price[31:0]),
        .probe3(ts_valid),

        // Status nibble
        .probe4(link_up),
        // .probe4({cfg_done, link_up, cfg_error, cfg_busy}),

        // .probe5({mdio_cmd_valid, mdio_busy, mdio_ack, mdio_cmd_phy[4:0], mdio_cmd_reg[4:0], mdio_cmd_wdata[15:0], mdio_cmd_read}),

        // Rx clock counter
        .probe5(rgmii_measured_freq[31:0]),
        .probe6(tx_axis_tdata[7:0]),
        .probe7({tx_axis_tready, tx_axis_tvalid, tx_axis_tlast}),
        // Payload / header / parser stream probes
        // .probe7(pl_payload_tdata[7:0]), // 8-bit
        // .probe8(pl_payload_tvalid), // 1-bit

        // .probe9(hdr_tdata[7:0]), // 8-bit
        // .probe10(hdr_tvalid), // 1-bit
        .probe8(speed[1:0]),
        .probe9({rx_error_bad_fcs, tx_error_underflow}),
        .probe10(rx_axis_tdata[7:0]),     // 8-bit (MAC -> header_skip)
        .probe11({rx_axis_tvalid, rx_axis_tready, rx_axis_tlast}),    // 1-bit

        // .probe13(payload_tdata[7:0]), // 8-bit (header_skip -> parser)
        // .probe14(payload_tvalid), // 1-bit

        .probe12({itch_valid, pl_first_byte_pulse})
        // .probe16({speed[1:0], rx_fifo_good_frame, rx_fifo_bad_frame, rx_fifo_overflow, tx_fifo_good_frame, tx_fifo_bad_frame, tx_fifo_overflow, rx_error_bad_fcs, rx_error_bad_frame, tx_error_underflow}),
        // .probe17({tx_axis_tvalid, tx_axis_tready})
    );

endmodule

`default_nettype wire