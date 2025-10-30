// --------------------------------------------------
// RGMII frequency meter for ILA, ~500 ms update
// --------------------------------------------------
module rgmii_freq_meter_500ms(
    input  wire        fabric_clk,       // E.g., 125 MHz
    input  wire        rst,
    input  wire        rgmii_rx_clk_bufg,
    output reg [31:0]  rgmii_freq_hz     // Measured frequency in Hz
);

    // -------------------------
    // Step 1: count edges in RGMII clock domain
    // -------------------------
    reg [31:0] rgmii_count = 0;
    always @(posedge rgmii_rx_clk_bufg) begin
        rgmii_count <= rgmii_count + 1;
    end

    // -------------------------
    // Step 2: synchronize counter to fabric_clk
    // -------------------------
    reg [31:0] rgmii_count_sync0, rgmii_count_sync1;
    reg [31:0] rgmii_count_last;

    always @(posedge fabric_clk) begin
        rgmii_count_sync0 <= rgmii_count;  // Async sampling
        rgmii_count_sync1 <= rgmii_count_sync0;
    end

    // -------------------------
    // Step 3: compute frequency over 500ms window
    // -------------------------
    reg [31:0] fabric_counter = 0;

    always @(posedge fabric_clk) begin
        if (rst) begin
            fabric_counter <= 0;
            rgmii_count_last <= 0;
            rgmii_freq_hz <= 0;
        end else begin
            fabric_counter <= fabric_counter + 1;

            // 500 ms window
            // For fabric_clk = 125 MHz: 125e6 * 0.5 = 62_500_000 cycles
            if (fabric_counter == 62_500_000-1) begin
                // Frequency = delta count of RGMII edges per 0.5 s
                // Multiply by 2 to get Hz
                rgmii_freq_hz <= 2 * (rgmii_count_sync1 - rgmii_count_last);

                // Latch for next measurement
                rgmii_count_last <= rgmii_count_sync1;
                fabric_counter <= 0;
            end
        end
    end

endmodule