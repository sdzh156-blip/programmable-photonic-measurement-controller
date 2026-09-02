`default_nettype none

module pulse_engine (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        start_i,
    input  logic        stop_i,
    input  logic [15:0] width_i,
    output logic        busy_o,
    output logic        pulse_o,
    output logic        done_o
);
    logic        busy_q;
    logic [15:0] count_q;

    assign busy_o  = busy_q;
    assign pulse_o = busy_q;
    assign done_o  = busy_q && (count_q == 16'd1);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q  <= 1'b0;
            count_q <= 16'd0;
        end else if (start_i) begin
            busy_q  <= (width_i != 16'd0);
            count_q <= width_i;
        end else if (stop_i) begin
            busy_q  <= 1'b0;
            count_q <= 16'd0;
        end else if (busy_q) begin
            if (count_q == 16'd1) begin
                busy_q  <= 1'b0;
                count_q <= 16'd0;
            end else begin
                count_q <= count_q - 16'd1;
            end
        end
    end
endmodule

`default_nettype wire
