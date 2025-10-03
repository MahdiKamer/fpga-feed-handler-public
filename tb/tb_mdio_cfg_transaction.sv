`timescale 1ns/1ps
module tb_mdio_cfg_transaction;

    logic clk, rst;
    logic start_cfg;
    logic cfg_busy, cfg_done, link_up, error;

    // MDIO handshake signals
    logic         mdio_cmd_valid;
    logic         mdio_cmd_read;
    logic [4:0]   mdio_cmd_phy;
    logic [4:0]   mdio_cmd_reg;
    logic [15:0]  mdio_cmd_wdata;
    logic         mdio_busy;
    logic         mdio_ack;
    logic [15:0]  mdio_rdata;

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // Reset + start pulse
    initial begin
        rst = 1;
        start_cfg = 0;
        #100 rst = 0;
        #200 start_cfg = 1;
        #20  start_cfg = 0;  // One-cycle pulse
    end

    // DUT (FSM)
    phy_config_sm_onehot dut (
        .clk(clk), .rst(rst),
        .start_cfg(start_cfg),
        .cfg_busy(cfg_busy),
        .cfg_done(cfg_done),
        .link_up(link_up),
        .error(error),
        // Mdio
        .mdio_cmd_valid(mdio_cmd_valid),
        .mdio_cmd_read(mdio_cmd_read),
        .mdio_cmd_phy(mdio_cmd_phy),
        .mdio_cmd_reg(mdio_cmd_reg),
        .mdio_cmd_wdata(mdio_cmd_wdata),
        .mdio_busy(mdio_busy),
        .mdio_ack(mdio_ack),
        .mdio_rdata(mdio_rdata)
    );

    // PHY behavior model (simple register file)
    phy_behav_simple phy_model (
        .clk(clk), .rst(rst),
        .cmd_valid(mdio_cmd_valid),
        .cmd_read(mdio_cmd_read),
        .cmd_phy(mdio_cmd_phy),
        .cmd_reg(mdio_cmd_reg),
        .cmd_wdata(mdio_cmd_wdata),
        .busy(mdio_busy),
        .ack(mdio_ack),
        .rdata(mdio_rdata)
    );

    // Self-checking process
    initial begin
        // Wait until configuration finishes
        wait (cfg_done || error);

        if (error) begin
            $display("[%0t] ERROR: FSM reported error", $time);
            $finish;
        end

        $display("[%0t] FSM completed configuration", $time);

        // Check BMCR (reg 0) loopback bit [14]
        if (phy_model.phy_regs[0][14] !== 1'b1) begin
            $display("[%0t] ERROR: BMCR loopback bit not set!", $time);
        end else begin
            $display("[%0t] PASS: BMCR loopback bit set correctly", $time);
        end

        // Check PHYID registers
        if (phy_model.phy_regs[2] == 16'h2215 && phy_model.phy_regs[3] == 16'h1430)
            $display("[%0t] PASS: PHYID values correct", $time);
        else
            $display("[%0t] ERROR: PHYID mismatch (got %h/%h)",
                      $time, phy_model.phy_regs[2], phy_model.phy_regs[3]);

        $finish;
    end

    // Timeout safeguard
    initial begin
        #50000;
        $display("[%0t] TIMEOUT: test did not complete", $time);
        $finish;
    end

endmodule