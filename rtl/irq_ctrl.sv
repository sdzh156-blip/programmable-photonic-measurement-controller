`default_nettype none

module irq_ctrl #(
    parameter integer WIDTH = 10
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic [WIDTH-1:0]     hw_set_i,
    input  logic [WIDTH-1:0]     sw_clear_i,
    input  logic                 enable_we_i,
    input  logic [WIDTH-1:0]     enable_wdata_i,
    output logic [WIDTH-1:0]     status_o,
    output logic [WIDTH-1:0]     enable_o,
    output logic                 irq_o
);
    logic [WIDTH-1:0] status_q;
    logic [WIDTH-1:0] enable_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            status_q <= '0;
            enable_q <= '0;
        end else begin
            // Event interrupt semantics: hardware set wins over software W1C.
            status_q <= (status_q & ~sw_clear_i) | hw_set_i;
            if (enable_we_i) begin
                enable_q <= enable_wdata_i;
            end
        end
    end

    assign status_o = status_q;
    assign enable_o = enable_q;
    assign irq_o    = |(status_q & enable_q);
endmodule

`default_nettype wire
