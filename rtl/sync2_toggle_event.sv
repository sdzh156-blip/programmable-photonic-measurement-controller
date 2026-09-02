`default_nettype none

module sync2_toggle_event (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic async_toggle_i,
    output logic sync_toggle_o,
    output logic event_o
);
    logic sync_toggle;
    logic sync_toggle_q;

    sync2_level #(.WIDTH(1)) u_sync_toggle (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .async_i (async_toggle_i),
        .sync_o  (sync_toggle)
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_toggle_q <= 1'b0;
        end else begin
            sync_toggle_q <= sync_toggle;
        end
    end

    assign sync_toggle_o = sync_toggle;
    assign event_o       = sync_toggle ^ sync_toggle_q;
endmodule

`default_nettype wire
