// -----------------------------------------------------------------------------
// Reset_sync.v inline (reset stretcher module)
// Simple power-on reset synchronizer with stretch
// Generates an active-high reset in the fabric domain
// - Asserts reset until clk_wiz locked and holds for STRETCH_CYCLES
// -----------------------------------------------------------------------------
module reset_sync #(
    parameter integer STRETCH_CYCLES = 32
)(
    input  wire clk,        // Fabric clock (e.g. 125 MHz from clk_wiz)
    input  wire pll_locked, // From clk_wiz locked output
    output wire rst         // Active-high reset
);

    // Width to hold count
    localparam CNT_WIDTH = $clog2(STRETCH_CYCLES+1);
    reg [CNT_WIDTH-1:0] cnt = {CNT_WIDTH{1'b0}};
    reg rst_reg = 1'b1;

    always @(posedge clk) begin
        if (!pll_locked) begin
            cnt     <= {CNT_WIDTH{1'b0}};
            rst_reg <= 1'b1;
        end else if (cnt < STRETCH_CYCLES) begin
            cnt     <= cnt + 1'b1;
            rst_reg <= 1'b1;
        end else begin
            rst_reg <= 1'b0;
        end
    end

    assign rst = rst_reg;

endmodule