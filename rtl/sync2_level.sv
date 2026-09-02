`default_nettype none

module sync2_level #(
    parameter integer WIDTH = 1
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic [WIDTH-1:0]     async_i,
    output logic [WIDTH-1:0]     sync_o
);
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_ff1_q;
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] sync_ff2_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_ff1_q <= '0;
            sync_ff2_q <= '0;
        end else begin
            sync_ff1_q <= async_i;
            sync_ff2_q <= sync_ff1_q;
        end
    end

    assign sync_o = sync_ff2_q;
endmodule

`default_nettype wire
