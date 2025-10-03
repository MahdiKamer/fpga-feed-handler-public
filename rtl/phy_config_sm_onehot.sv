// Phy_config_sm_onehot.sv
// PHY config with address autodetection
// One-hot Moore FSM per Cummings SNUG-2019
`timescale 1ns/1ps
module phy_config_sm_onehot (
    input  logic        clk,
    input  logic        rst,

    // Mdio interface
    output logic        mdio_cmd_valid,
    output logic        mdio_cmd_read,
    output logic [4:0]  mdio_cmd_phy,
    output logic [4:0]  mdio_cmd_reg,
    output logic [15:0] mdio_cmd_wdata,
    input  logic        mdio_busy,
    input  logic        mdio_ack,
    input  logic [15:0] mdio_rdata,

    // Control
    input  logic        start_cfg,
    output logic        cfg_busy,
    output logic        cfg_done,
    output logic        link_up,
    output logic        error
);

    // PHY registers
    localparam REG_BMCR       = 5'd0;
    localparam REG_BMSR       = 5'd1;
    localparam REG_PHYID1     = 5'd2;
    localparam REG_PHYID2     = 5'd3;
    localparam REG_ANAR       = 5'd4;
    localparam REG_1000T_CTRL = 5'd9;

    // One-hot states
    typedef enum logic [13:0] {
        S_IDLE         = 14'b0000_0000_000001,
        S_SCAN_START   = 14'b0000_0000_000010,
        S_SCAN_READ1   = 14'b0000_0000_000100,
        S_SCAN_READ2   = 14'b0000_0000_001000,
        S_CFG_WAIT_RST = 14'b0000_0000_010000,
        S_CFG_ANAR     = 14'b0000_0000_100000,
        S_CFG_1000     = 14'b0000_0001_000000,
        S_CFG_BMCR     = 14'b0000_0010_000000,
        S_CFG_POLL     = 14'b0000_0100_000000,
        S_CFG_LOOPBACK = 14'b0000_1000_000000,
        S_DONE         = 14'b0001_0000_000000,
        S_ERROR        = 14'b0010_0000_000000,
        S_ISSUE_CMD    = 14'b0100_0000_000000,
        S_WAIT_ACK     = 14'b1000_0000_000000
    } state_t;

    state_t state, next_state;
    state_t return_state;       // Where to go after WAIT_ACK

    // Staging
    logic [4:0]  scan_addr, phy_addr;
    logic [15:0] latched_rdata;
    logic [15:0] next_wdata;
    logic [4:0]  next_phy, next_reg;
    logic        next_is_read;
    //logic        found;
    logic [31:0] timer;

    // ---------------------------
    // Sequential state update
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            latched_rdata<= 16'h0;
        end else begin
            state <= next_state;
            if (state == S_WAIT_ACK && mdio_ack)
                latched_rdata <= mdio_rdata; // Capture once ack seen
        end
    end

    // ---------------------------
    // Next-state logic
    always_comb begin
        next_state = state; // Hold

        unique case (state)
            S_IDLE:       if (start_cfg) next_state = S_SCAN_START;

            S_SCAN_START: next_state = S_ISSUE_CMD; // Always issue read ID1

            S_SCAN_READ1: begin
                if ((latched_rdata !== 16'h0000) && (latched_rdata !== 16'hFFFF))
                    next_state = S_SCAN_READ2;
                else if (scan_addr == 5'd31)
                    next_state = S_ERROR;
                else
                    next_state = S_SCAN_START;
            end

            S_SCAN_READ2: begin
                if ((latched_rdata !== 16'h0000) && (latched_rdata !== 16'hFFFF))
                    next_state = S_CFG_WAIT_RST;
                else if (scan_addr == 5'd31)
                    next_state = S_ERROR;
                else
                    next_state = S_SCAN_START;
            end

            S_CFG_WAIT_RST: if (timer == 32'd1_000_000) next_state = S_CFG_ANAR;

            S_CFG_ANAR:     next_state = S_ISSUE_CMD;
            S_CFG_1000:     next_state = S_ISSUE_CMD;
            S_CFG_BMCR:     next_state = S_ISSUE_CMD;

            S_CFG_POLL: begin
                if (latched_rdata[2])          next_state = S_CFG_LOOPBACK;
                else if (timer > 32'd10_000_000) next_state = S_ERROR;
                else if (!mdio_busy)           next_state = S_ISSUE_CMD;
            end

            S_CFG_LOOPBACK: next_state = S_ISSUE_CMD;
            S_DONE:         next_state = S_IDLE;
            S_ERROR:        next_state = S_IDLE;

            S_ISSUE_CMD:    next_state = S_WAIT_ACK;
            S_WAIT_ACK:     if (mdio_ack) next_state = return_state;

            default:        next_state = S_ERROR;
        endcase
    end

    // ---------------------------
    // Outputs & regs
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cfg_busy      <= 0;
            cfg_done      <= 0;
            link_up       <= 0;
            error         <= 0;
            scan_addr     <= 0;
            //found         <= 0;
            phy_addr      <= 0;
            timer         <= 0;
            mdio_cmd_valid<= 0;
            mdio_cmd_read <= 0;
            mdio_cmd_phy  <= 0;
            mdio_cmd_reg  <= 0;
            mdio_cmd_wdata<= 0;
            return_state  <= S_IDLE;
        end else begin
            cfg_busy <= (state != S_IDLE && state != S_DONE && state != S_ERROR);
            cfg_done <= (state == S_DONE);
            error    <= (state == S_ERROR);
            if (state == S_CFG_LOOPBACK) link_up <= 1;

            // Timer
            if (state == S_CFG_WAIT_RST || state == S_CFG_POLL)
                timer <= timer + 1;
            else
                timer <= 0;

            // Scanning bookkeeping
            if (state == S_SCAN_READ2) begin
                phy_addr <= scan_addr;
                //found    <= 1;
            end
            if (state == S_SCAN_READ1 || state == S_SCAN_READ2) begin
                if ((latched_rdata == 16'h0000) || (latched_rdata == 16'hFFFF))
                    scan_addr <= scan_addr + 1;
            end

            // Drive MDIO cmd only in ISSUE_CMD
            if (state == S_ISSUE_CMD) begin
                mdio_cmd_valid <= 1;
                mdio_cmd_read  <= next_is_read;
                mdio_cmd_phy   <= next_phy;
                mdio_cmd_reg   <= next_reg;
                mdio_cmd_wdata <= next_wdata;
            end else begin
                mdio_cmd_valid <= 0;
            end

            // Staging: each state sets up next transaction + return state
            unique case (state)
                S_SCAN_START: begin
                    next_phy     <= scan_addr;
                    next_reg     <= REG_PHYID1;
                    next_wdata   <= 16'h0;
                    next_is_read <= 1;
                    return_state <= S_SCAN_READ1;
                end
                S_SCAN_READ2: begin
                    next_phy     <= scan_addr;
                    next_reg     <= REG_PHYID2;
                    next_wdata   <= 16'h0;
                    next_is_read <= 1;
                    return_state <= S_SCAN_READ2;
                end
                S_CFG_ANAR: begin
                    next_phy     <= phy_addr;
                    next_reg     <= REG_ANAR;
                    next_wdata <= 16'h0DE1;   // Advertise 10/100 + pause (leave 1000 to REG_1000T_CTRL)
                    next_is_read <= 0;
                    return_state <= S_CFG_1000;
                end
                S_CFG_1000: begin
                    next_phy     <= phy_addr;
                    next_reg     <= REG_1000T_CTRL;
                    next_wdata   <= 16'h0300;
                    next_is_read <= 0;
                    return_state <= S_CFG_BMCR;
                end
                S_CFG_BMCR: begin
                    next_phy     <= phy_addr;
                    next_reg     <= REG_BMCR;
                    next_wdata <= 16'h0140;   // Force 1000 Mb/s, full duplex
                    next_is_read <= 0;
                    return_state <= S_CFG_POLL;
                end
                S_CFG_POLL: begin
                    next_phy     <= phy_addr;
                    next_reg     <= REG_BMSR;
                    next_wdata   <= 16'h0;
                    next_is_read <= 1;
                    return_state <= S_CFG_POLL;
                end
                S_CFG_LOOPBACK: begin
                    next_phy     <= phy_addr;
                    next_reg     <= REG_BMCR;
                    next_wdata <= 16'h4140;   // Loopback + 1000 Mb/s + full duplex
                    next_is_read <= 0;
                    return_state <= S_DONE;
                end
                default: ;
            endcase
        end
    end
endmodule