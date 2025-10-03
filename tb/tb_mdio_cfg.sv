`timescale 1ns/1ps

module tb_mdio_cfg;

    // ----------------------------------------------------------------
    // Clock / Reset
    // ----------------------------------------------------------------
    reg clk = 0, rst = 1;
    always #4 clk = ~clk;  // 125 MHz

    initial begin
        #100 rst = 0;
    end

    // ----------------------------------------------------------------
    // MDIO wires
    // ----------------------------------------------------------------
    wire mdc;
    tri  mdio;

    // ----------------------------------------------------------------
    // DUT <-> FSM handshake wires
    // ----------------------------------------------------------------
    wire        cmd_valid, cmd_read;
    wire [4:0]  cmd_phy, cmd_reg;
    wire [15:0] cmd_wdata;
    wire        busy, ack;
    wire [15:0] dut_rdata;      // Master output (unused)
    logic [15:0] tb_rdata;      // FSM input (sampled from MDIO)

    // ----------------------------------------------------------------
    // Instantiate DUT (MDIO master)
    // ----------------------------------------------------------------
    mdio_master #(.MDC_DIV(50)) mdio_dut (
        .clk(clk), .rst(rst),
        .cmd_valid(cmd_valid),
        .cmd_read(cmd_read),
        .cmd_phyaddr(cmd_phy),
        .cmd_regaddr(cmd_reg),
        .cmd_wdata(cmd_wdata),
        .busy(busy),
        .ack(ack),
        .rdata(dut_rdata),
        .mdc(mdc),
        .mdio(mdio)
    );

    // ----------------------------------------------------------------
    // Instantiate PHY config FSM
    // ----------------------------------------------------------------
    reg start_cfg = 0;
    wire cfg_busy, cfg_done, link_up, error;

    phy_config_sm_onehot fsm_dut (
        .clk(clk),
        .rst(rst),
        .mdio_cmd_valid(cmd_valid),
        .mdio_cmd_read(cmd_read),
        .mdio_cmd_phy(cmd_phy),
        .mdio_cmd_reg(cmd_reg),
        .mdio_cmd_wdata(cmd_wdata),
        .mdio_busy(busy),
        .mdio_ack(ack),
        .mdio_rdata(tb_rdata),
        .start_cfg(start_cfg),
        .cfg_busy(cfg_busy),
        .cfg_done(cfg_done),
        .link_up(link_up),
        .error(error)
    );

    // ----------------------------------------------------------------
    // Instantiate Behavioral PHY
    // ----------------------------------------------------------------
    phy_behav_full phy0 (
        .clk(clk),
        .rst(rst),
        .mdc(mdc),
        .mdio(mdio)
    );

    // ----------------------------------------------------------------
    // Sample MDIO from PHY to provide tb_rdata to FSM
    // ----------------------------------------------------------------
    reg [15:0] mdio_shift;
    reg [4:0]  bit_cnt;
    reg        mdc_prev = 0;

    always @(posedge clk) begin
        if (rst) begin
            mdio_shift <= 16'h0;
            bit_cnt    <= 0;
            tb_rdata   <= 16'h0;
            mdc_prev   <= 0;
        end else begin
            // Detect rising edge of MDC
            if (mdc && !mdc_prev) begin
                mdio_shift <= {mdio_shift[14:0], mdio};
                bit_cnt    <= bit_cnt + 1;

                if (bit_cnt == 15) begin
                    tb_rdata <= {mdio_shift[14:0], mdio};
                    $display("[%0t] MDIO sampled -> 0x%h", $time, tb_rdata);
                    bit_cnt <= 0;
                end
            end
            mdc_prev <= mdc;
        end
    end

    // ----------------------------------------------------------------
    // Drive start_cfg
    // ----------------------------------------------------------------
    initial begin
        #200 start_cfg = 1;
        #10  start_cfg = 0;
    end

    // ----------------------------------------------------------------
    // Finish condition
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (cfg_done) begin
            $display("[%0t] CONFIG DONE, link_up=%b", $time, link_up);
            #100 $finish;
        end
        if (error) begin
            $display("[%0t] CONFIG ERROR", $time);
            #100 $finish;
        end
    end

endmodule