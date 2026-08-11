`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// timing_engine.v
// Shared 32-bit programmable timer for the PMC.
//
// Cycle semantics:
//   - A start at edge t0 with load_value_i=N>0 begins the first full wait cycle
//     during [t0,t1).
//   - expire_o is asserted combinationally during the cycle immediately before
//     the deadline edge, so the consumer can sample it at tN.
//   - N=1 therefore expires at the next rising edge.
//   - stop_i has safety priority over start_i.
// -----------------------------------------------------------------------------
module timing_engine (
    input  wire        hclk_i,
    input  wire        hreset_ni,
    input  wire        start_i,
    input  wire        stop_i,
    input  wire [31:0] load_value_i,
    output wire        running_o,
    output wire        expire_o
);

    reg [31:0] count_q;
    reg        running_q;

    assign running_o = running_q;
    assign expire_o  = running_q && (count_q == 32'd1);

    always @(posedge hclk_i or negedge hreset_ni) begin
        if (!hreset_ni) begin
            count_q   <= 32'd0;
            running_q <= 1'b0;
        end else if (stop_i) begin
            count_q   <= 32'd0;
            running_q <= 1'b0;
        end else if (start_i) begin
            if (load_value_i == 32'd0) begin
                count_q   <= 32'd0;
                running_q <= 1'b0;
            end else begin
                count_q   <= load_value_i;
                running_q <= 1'b1;
            end
        end else if (running_q) begin
            if (count_q <= 32'd1) begin
                count_q   <= 32'd0;
                running_q <= 1'b0;
            end else begin
                count_q <= count_q - 32'd1;
            end
        end
    end

endmodule
