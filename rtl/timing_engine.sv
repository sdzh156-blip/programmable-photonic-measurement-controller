`default_nettype none

module timing_engine (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        start_i,
    input  logic        stop_i,
    input  logic [31:0] load_i,
    output logic        active_o,
    output logic        done_o,
    output logic [31:0] count_o
);
    logic        active_q;
    logic [31:0] count_q;

    assign active_o = active_q;
    assign count_o  = count_q;
    assign done_o   = active_q && (count_q == 32'd1);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            active_q <= 1'b0;
            count_q  <= 32'd0;
        end else if (start_i) begin
            active_q <= (load_i != 32'd0);
            count_q  <= load_i;
        end else if (stop_i) begin
            active_q <= 1'b0;
            count_q  <= 32'd0;
        end else if (active_q) begin
            if (count_q == 32'd1) begin
                active_q <= 1'b0;
                count_q  <= 32'd0;
            end else begin
                count_q <= count_q - 32'd1;
            end
        end
    end
endmodule

`default_nettype wire
