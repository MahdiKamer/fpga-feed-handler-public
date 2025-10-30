`timescale 1ns/1ps

module phy_behav_full(
    input  wire clk,      // 125 MHz or faster
    input  wire rst,
    input  wire mdc,      // MDIO clock
    inout  wire mdio      // MDIO bidirectional
);

    // ----------------------------------------------------------------
    // PHY registers (canned values)
    // ----------------------------------------------------------------
    reg [15:0] phy_regs [0:31];
    initial begin
        phy_regs[2] = 16'h2215; // PHYID1
        phy_regs[3] = 16'h5C90; // PHYID2
        phy_regs[1] = 16'h0004; // BMSR (link up)
    end

    // ----------------------------------------------------------------
    // MDIO tri-state output
    // ----------------------------------------------------------------
    reg mdio_out_en = 0;
    reg mdio_out    = 1'b1;
    assign mdio = mdio_out_en ? mdio_out : 1'bz;

    // ----------------------------------------------------------------
    // Shift registers for incoming/outgoing MDIO transactions
    // ----------------------------------------------------------------
    reg [31:0] shift_in;
    reg [15:0] shift_out;
    reg [5:0] bit_cnt;
    reg reading, writing;
    reg op_read;

    // State machine
    typedef enum logic [2:0] {
        IDLE,
        PREAMBLE,
        START,
        OPCODE,
        ADDR,
        TURNAROUND,
        DATA
    } mdio_state_t;

    mdio_state_t state = IDLE;

    reg [4:0] phy_addr;
    reg [4:0] reg_addr;

    always @(posedge mdc or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            mdio_out_en <= 0;
            bit_cnt <= 0;
            reading <= 0;
            writing <= 0;
        end else begin
            case (state)
                IDLE: begin
                    bit_cnt <= 0;
                    mdio_out_en <= 0;
                    reading <= 0;
                    writing <= 0;
                    if (mdio === 0) begin // Detect start of preamble (simplified)
                        state <= PREAMBLE;
                    end
                end

                PREAMBLE: begin
                    bit_cnt <= bit_cnt + 1;
                    if (bit_cnt == 31) begin
                        bit_cnt <= 0;
                        state <= START;
                    end
                end

                START: begin
                    // Capture start bits
                    bit_cnt <= bit_cnt + 1;
                    shift_in[31] <= mdio;
                    if (bit_cnt == 1) begin
                        state <= OPCODE;
                        bit_cnt <= 0;
                    end
                end

                OPCODE: begin
                    shift_in[30 - bit_cnt] <= mdio;
                    bit_cnt <= bit_cnt + 1;
                    if (bit_cnt == 1) begin
                        op_read <= shift_in[30]; // 1=read, 0=write
                        state <= ADDR;
                        bit_cnt <= 0;
                    end
                end

                ADDR: begin
                    shift_in[29 - bit_cnt] <= mdio; // Capture PHY + REG addr
                    bit_cnt <= bit_cnt + 1;
                    if (bit_cnt == 9) begin
                        phy_addr <= shift_in[29:25];
                        reg_addr <= shift_in[24:20];
                        state <= TURNAROUND;
                        bit_cnt <= 0;
                    end
                end

                TURNAROUND: begin
                    // MDIO driven by PHY for read
                    if (op_read) begin
                        shift_out <= phy_regs[reg_addr];
                        mdio_out_en <= 1;
                        mdio_out <= shift_out[15];
                        bit_cnt <= 0;
                        state <= DATA;
                    end else begin
                        writing <= 1;
                        mdio_out_en <= 0; // Master drives write data
                        bit_cnt <= 0;
                        state <= DATA;
                    end
                end

                DATA: begin
                    if (op_read) begin
                        mdio_out <= shift_out[15 - bit_cnt];
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 15) begin
                            mdio_out_en <= 0;
                            $display("[%0t] MDIO READ: phy=%0d reg=%0d -> 0x%h",
                                     $time, phy_addr, reg_addr, shift_out);
                            state <= IDLE;
                        end
                    end else if (writing) begin
                        shift_out[15 - bit_cnt] <= mdio;
                        bit_cnt <= bit_cnt + 1;
                        if (bit_cnt == 15) begin
                            phy_regs[reg_addr] <= shift_out;
                            $display("[%0t] MDIO WRITE: phy=%0d reg=%0d data=0x%h",
                                     $time, phy_addr, reg_addr, shift_out);
                            writing <= 0;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule