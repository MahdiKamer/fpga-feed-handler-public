// Pl_tx_fsm_full.v
// Drives header inserter with a simple payload sequence (one ITCH 'A' message).
// Connects the header inserter output directly to MAC TX AXIS or you can merge them in top.
`timescale 1ns/1ps
module pl_tx_fsm_full (
    input  wire       clk,
    input  wire       rst,
    input  wire       start_tx_pulse, // Single-cycle trigger to send one packet

    // Payload output interface (internal)
    // Here we provide a small internal payload generator for ITCH 'A' (15 bytes)
    output reg        payload_out_tvalid,
    input  wire       payload_out_tready,
    output reg  [7:0] payload_out_tdata,
    output reg        payload_out_tlast,

    // First accepted byte pulse (one cycle) when header inserter's first byte is accepted by MAC
    output reg        first_byte_pulse
);

    // Internal sending state
    reg sending;
    reg [7:0] byte_idx;

    // Payload ROM for 15-byte ITCH 'A'
    reg [7:0] itch [0:14];

    initial begin
        // Construct a demo ITCH 'A' payload
        itch[0]  = 8'h41; // 'A'
        itch[1]  = 8'h01;
        itch[2]  = 8'h02;
        itch[3]  = 8'h03;
        itch[4]  = 8'h04;
        itch[5]  = 8'h05;
        itch[6]  = 8'h06;
        itch[7]  = 8'h07;
        itch[8]  = 8'h08;
        itch[9]  = 8'h00;
        itch[10] = 8'h64; // Qty = 100 (example)
        itch[11] = 8'h00;
        itch[12] = 8'h00;
        itch[13] = 8'h27;
        itch[14] = 8'h10; // Price = 10000
    end

    // For this pattern: this FSM only drives the payload interface which header_inserter will read.
    always @(posedge clk) begin
        if (rst) begin
            sending <= 1'b0;
            payload_out_tvalid <= 1'b0;
            payload_out_tdata  <= 8'h00;
            payload_out_tlast  <= 1'b0;
            byte_idx <= 0;
            first_byte_pulse <= 1'b0;
        end else begin
            first_byte_pulse <= 1'b0; // Default

            if (!sending) begin
                if (start_tx_pulse) begin
                    sending <= 1'b1;
                    byte_idx <= 0;
                end
            end else begin
                payload_out_tdata <= itch[byte_idx];
                payload_out_tvalid <= 1'b1;
                payload_out_tlast <= (byte_idx == 14);
                if (payload_out_tready) begin
                    byte_idx <= byte_idx + 1;
                    if (byte_idx == 14) begin
                        sending <= 1'b0;
                    end
                end
                if (byte_idx == 0) begin
                    first_byte_pulse <= 1'b1;
                end
            end
        end
    end
endmodule