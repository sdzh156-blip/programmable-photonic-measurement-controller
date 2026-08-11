`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// irq_ctrl.v
// Interrupt pending/enable block.
// HW-set has priority over SW W1C when they collide in the same cycle.
// -----------------------------------------------------------------------------
module irq_ctrl (
    input  wire        hclk_i,
    input  wire        hreset_ni,
    input  wire [9:0]  hw_set_i,
    input  wire [9:0]  sw_clear_i,
    input  wire        int_enable_we_i,
    input  wire [9:0]  int_enable_wdata_i,
    output wire [9:0]  int_status_o,
    output wire [9:0]  int_enable_o,
    output wire        irq_o
);

    reg [9:0] int_status_q;
    reg [9:0] int_enable_q;

    assign int_status_o = int_status_q;
    assign int_enable_o = int_enable_q;
    assign irq_o        = |(int_status_q & int_enable_q);

    always @(posedge hclk_i or negedge hreset_ni) begin
        if (!hreset_ni) begin
            int_status_q <= 10'd0;
            int_enable_q <= 10'd0;
        end else begin
            int_status_q <= (int_status_q & ~sw_clear_i) | hw_set_i;
            if (int_enable_we_i)
                int_enable_q <= int_enable_wdata_i;
        end
    end

endmodule
