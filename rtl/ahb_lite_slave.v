`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// ahb_lite_slave.v
// 32-bit AMBA 3 AHB-Lite CSR slave front-end.
//
// Key properties:
//   * Address/control phase is latched for every accepted transfer.
//   * Read and write data phases both resolve from the latched transaction.
//   * Normal CSR access is zero-wait-state.
//   * Bad HSIZE, misalignment, or unmapped offset returns a two-cycle ERROR.
// -----------------------------------------------------------------------------
module ahb_lite_slave (
    input  wire        hclk_i,
    input  wire        hreset_ni,

    input  wire        hsel_i,
    input  wire [31:0] haddr_i,
    input  wire [1:0]  htrans_i,
    input  wire        hwrite_i,
    input  wire [2:0]  hsize_i,
    input  wire [2:0]  hburst_i,
    input  wire [3:0]  hprot_i,
    input  wire        hmastlock_i,
    input  wire [31:0] hwdata_i,
    input  wire        hready_i,

    output reg  [31:0] hrdata_o,
    output reg         hreadyout_o,
    output reg         hresp_o,

    output wire [11:0] csr_addr_o,
    output wire        csr_write_o,
    output wire        csr_read_o,
    output wire [31:0] csr_wdata_o,
    input  wire [31:0] csr_rdata_i,
    input  wire        csr_addr_valid_i
);

    reg        trans_valid_q;
    reg [31:0] trans_addr_q;
    reg        trans_write_q;
    reg [2:0]  trans_size_q;
    reg        trans_pre_error_q;
    reg        error_second_q;

    wire trans_unmapped;
    wire trans_error;
    wire addr_accept;
    wire data_phase_complete;

    // hburst_i/hprot_i/hmastlock_i are intentionally accepted but ignored by V1.
    wire unused_inputs;
    assign unused_inputs = ^{hburst_i, hprot_i, hmastlock_i, trans_size_q};

    assign csr_addr_o  = trans_addr_q[11:0];
    assign csr_wdata_o = hwdata_i;

    assign trans_unmapped = trans_valid_q && !csr_addr_valid_i;
    assign trans_error    = trans_pre_error_q || trans_unmapped;

    // Include local HREADYOUT so a standalone connection cannot accept a new
    // address during the first (stalling) ERROR-response cycle.
    assign addr_accept = hsel_i && hready_i && hreadyout_o && htrans_i[1];

    assign data_phase_complete = trans_valid_q && hready_i && hreadyout_o;

    assign csr_write_o = data_phase_complete && trans_write_q && !trans_error;
    assign csr_read_o  = data_phase_complete && !trans_write_q && !trans_error;

    always @(*) begin
        hrdata_o    = 32'd0;
        hreadyout_o = 1'b1;
        hresp_o     = 1'b0;

        if (error_second_q) begin
            // Second and final ERROR response cycle.
            hreadyout_o = 1'b1;
            hresp_o     = 1'b1;
        end else if (trans_valid_q && trans_error) begin
            // First ERROR response cycle: hold the bus for one cycle.
            hreadyout_o = 1'b0;
            hresp_o     = 1'b1;
        end else if (trans_valid_q && !trans_write_q) begin
            hrdata_o = csr_rdata_i;
        end
    end

    always @(posedge hclk_i or negedge hreset_ni) begin
        if (!hreset_ni) begin
            trans_valid_q     <= 1'b0;
            trans_addr_q      <= 32'd0;
            trans_write_q     <= 1'b0;
            trans_size_q      <= 3'd0;
            trans_pre_error_q <= 1'b0;
            error_second_q    <= 1'b0;
        end else begin
            if (trans_valid_q && trans_error && !error_second_q) begin
                // First ERROR cycle: retain transaction state for second cycle.
                error_second_q <= 1'b1;
            end else if (!hready_i) begin
                // Global AHB stall: retain the current data-phase transaction.
                trans_valid_q     <= trans_valid_q;
                trans_addr_q      <= trans_addr_q;
                trans_write_q     <= trans_write_q;
                trans_size_q      <= trans_size_q;
                trans_pre_error_q <= trans_pre_error_q;
                error_second_q    <= error_second_q;
            end else begin
                // Current legal transfer or second ERROR cycle completes here.
                error_second_q <= 1'b0;

                if (addr_accept) begin
                    trans_valid_q     <= 1'b1;
                    trans_addr_q      <= haddr_i;
                    trans_write_q     <= hwrite_i;
                    trans_size_q      <= hsize_i;
                    trans_pre_error_q <= (hsize_i != 3'b010) ||
                                         (haddr_i[1:0] != 2'b00);
                end else begin
                    trans_valid_q     <= 1'b0;
                    trans_pre_error_q <= 1'b0;
                end
            end
        end
    end

endmodule
