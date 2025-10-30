`timescale 1ns/1ps
module phy_behav_simple (
    input  logic       clk,
    input  logic       rst,
    input  logic       cmd_valid,
    input  logic       cmd_read,
    input  logic [4:0] cmd_phy,
    input  logic [4:0] cmd_reg,
    input  logic [15:0] cmd_wdata,
    output logic       busy,
    output logic       ack,
    output logic [15:0] rdata
);
    // Internal PHY register file
    logic [15:0] phy_regs [0:31];

    // Initialize with PHYID values (JL2121-like)
    initial begin
        phy_regs[0] = 16'h1140; // BMCR (default)
        phy_regs[1] = 16'h796D; // BMSR (example)
        phy_regs[2] = 16'h2215; // PHYID1
        phy_regs[3] = 16'h1430; // PHYID2
    end

    // Handshake state
    typedef enum logic [1:0] {P_IDLE, P_BUSY, P_ACK} pstate_t;
    pstate_t state;
    logic [15:0] rdata_q;

    assign rdata = rdata_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state   <= P_IDLE;
            busy    <= 1'b0;
            ack     <= 1'b0;
            rdata_q <= 16'h0;
        end else begin
            ack <= 1'b0; // Default

            case (state)
            P_IDLE: begin
                if (cmd_valid) begin
                    busy <= 1'b1;
                    if (cmd_read) begin
                        rdata_q <= phy_regs[cmd_reg];
                    end else begin
                        phy_regs[cmd_reg] <= cmd_wdata;
                    end
                    state <= P_BUSY;
                end
            end

            P_BUSY: begin
                // Simulate some delay
                busy  <= 1'b0;
                ack   <= 1'b1;
                state <= P_ACK;
            end

            P_ACK: begin
                ack   <= 1'b0;
                state <= P_IDLE;
            end
            endcase
        end
    end
endmodule