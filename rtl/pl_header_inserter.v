// Pl_header_inserter.v
// Minimal header inserter: constructs Ethernet + IPv4 + UDP headers
// Then forwards payload bytes from payload_in (8-bit stream).
// All numbers in network byte order (big-endian).
// NOTE: This is minimal and intended for lab tests & loopback; not production-grade IP.
`timescale 1ns/1ps
module pl_header_inserter #(
    parameter MAC_DST = 48'hDA_AA_AA_AA_AA_AA, // Dest MAC (set to loop target)
    parameter MAC_SRC = 48'hDE_AD_BE_EF_00_01, // Src MAC (set to board PL MAC)
    parameter ETH_TYPE = 16'h0800,             // IPv4
    parameter IP_SRC = 32'hC0A80102,           // 192.168.1.2 (example)
    parameter IP_DST = 32'hC0A80101,           // 192.168.1.1 (example)
    parameter UDP_SRC_PORT = 16'd5000,
    parameter UDP_DST_PORT = 16'd5000
)(
    input  wire        clk,
    input  wire        rst,

    // Payload input (payload stream that will be placed into UDP payload)
    input  wire [7:0]  payload_in_tdata,
    input  wire        payload_in_tvalid,
    output wire        payload_in_tready,
    input  wire        payload_in_tlast, // Last byte of payload

    // AXI-Stream master out (to MAC TX)
    output reg  [7:0]  m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);

    // Internal state machine: we first drive header bytes (42 bytes), then forward payload
    localparam S_IDLE  = 0;
    localparam S_HDR   = 1;
    localparam S_PAY   = 2;

    reg [1:0] state;
    reg [15:0] hdr_cnt;
    //reg [15:0] payload_len_reg;
    reg payload_start;

    // Precompute simple IPv4 header fields: version+ihl, total length later computed in two bytes
    // For simplicity here we will fill total length field after we know payload length. For lab usage
    // Where payload length is small and static, you can precompute; else you can send static small payloads.

    // For this demo: we will not fill IPv4 total length correctly; many NICs/PHYs do not check IP checksum on loopback.
    // But some stacks may drop incorrect IP packets. If you need to compute exact IPv4 checksum and lengths,
    // Extend this block. For quick lab loopback on PL-->PL, many PHY+MAC accept packets with these fields zeroed.
    // However we'll create a minimal, plausible set below.

    // We create a header byte function via indexing
        function [7:0] hdr_byte;
        input [15:0] idx;
        reg [47:0] dst_mac;
        reg [47:0] src_mac;
        reg [15:0] eth_type;
        begin
            dst_mac = MAC_DST;
            src_mac = MAC_SRC;
            eth_type = ETH_TYPE;
            case (idx)
                // Ethernet header (14 bytes)
                 0: hdr_byte = dst_mac[47:40];
                 1: hdr_byte = dst_mac[39:32];
                 2: hdr_byte = dst_mac[31:24];
                 3: hdr_byte = dst_mac[23:16];
                 4: hdr_byte = dst_mac[15:8];
                 5: hdr_byte = dst_mac[7:0];
                 6: hdr_byte = src_mac[47:40];
                 7: hdr_byte = src_mac[39:32];
                 8: hdr_byte = src_mac[31:24];
                 9: hdr_byte = src_mac[23:16];
                10: hdr_byte = src_mac[15:8];
                11: hdr_byte = src_mac[7:0];
                12: hdr_byte = eth_type[15:8];
                13: hdr_byte = eth_type[7:0];

                // IPv4 header (20 bytes, idx 14-33)
                14: hdr_byte = 8'h45; // Version + IHL
                15: hdr_byte = 8'h00; // DSCP/ECN
                16: hdr_byte = 8'h00; // Total length MSB
                17: hdr_byte = 8'h2C; // Total length LSB (example: 44)
                18: hdr_byte = 8'h00; // Identification
                19: hdr_byte = 8'h00;
                20: hdr_byte = 8'h40; // Flags/fragment
                21: hdr_byte = 8'h40; // TTL
                22: hdr_byte = 8'h11; // Protocol = UDP
                23: hdr_byte = 8'h00; // Header checksum MSB
                24: hdr_byte = 8'h00; // Header checksum LSB
                25: hdr_byte = IP_SRC[31:24]; // Src IP
                26: hdr_byte = IP_SRC[23:16];
                27: hdr_byte = IP_SRC[15:8];
                28: hdr_byte = IP_SRC[7:0];
                29: hdr_byte = IP_DST[31:24]; // Dst IP
                30: hdr_byte = IP_DST[23:16];
                31: hdr_byte = IP_DST[15:8];
                32: hdr_byte = IP_DST[7:0];
                33: hdr_byte = 8'h00; // Pad or options (none for IHL=5)

                // UDP header (8 bytes, idx 34-41)
                34: hdr_byte = UDP_SRC_PORT[15:8];
                35: hdr_byte = UDP_SRC_PORT[7:0];
                36: hdr_byte = UDP_DST_PORT[15:8];
                37: hdr_byte = UDP_DST_PORT[7:0];
                38: hdr_byte = 8'h00; // UDP length MSB (placeholder)
                39: hdr_byte = 8'h10; // UDP length LSB (example)
                40: hdr_byte = 8'h00; // UDP checksum MSB
                41: hdr_byte = 8'h00; // UDP checksum LSB

                default: hdr_byte = 8'h00;
            endcase
        end
    endfunction

    assign payload_in_tready = (hdr_cnt == 41) ? 1'b1 : 1'b0; // Accept payload when in PAY

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            hdr_cnt <= 0;
            m_axis_tdata <= 8'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            payload_start <= 1'b0;
        end else begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (payload_in_tvalid) begin
                        // Latch length if we wanted; here just start header emission
                        payload_start <= 1'b1;
                        hdr_cnt <= 0;
                        state <= S_HDR;
                    end
                end
                S_HDR: begin
                    // Emit header bytes
                    if (m_axis_tready) begin
                        m_axis_tdata <= hdr_byte(hdr_cnt);
                        m_axis_tvalid <= 1'b1;
                        if (hdr_cnt == 41) begin// Problem
                            // Header done; transition to payload stream next cycle
                            state <= S_PAY;
                        end else begin
                            hdr_cnt <= hdr_cnt + 1;
                        end
                    end
                end
                S_PAY: begin
                    // Forward payload bytes (payload_in is driving)
                    if (payload_in_tvalid && payload_in_tready) begin
                        if (m_axis_tready) begin
                            m_axis_tdata <= payload_in_tdata;
                            m_axis_tvalid <= 1'b1;
                            // Set tlast when payload_in_tlast asserted
                            if (payload_in_tlast) begin
                                m_axis_tlast <= 1'b1;
                                state <= S_IDLE;
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule