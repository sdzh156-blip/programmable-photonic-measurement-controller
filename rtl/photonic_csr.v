`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// photonic_csr.v
// Software-visible CSR programming bank for the PMC.
//
// Active runtime configuration is NOT owned here. measurement_ctrl snapshots
// these programming registers when a START command is accepted.
// -----------------------------------------------------------------------------
module photonic_csr (
    input  wire         hclk_i,
    input  wire         hreset_ni,

    input  wire [11:0]  csr_addr_i,
    input  wire         csr_write_i,
    input  wire         csr_read_i,
    input  wire [31:0]  csr_wdata_i,
    output reg  [31:0]  csr_rdata_o,
    output reg          csr_addr_valid_o,

    output reg          start_req_o,
    output reg          abort_req_o,
    output wire         enable_o,
    output wire [3:0]   phase_count_o,
    output wire [31:0]  sensor_ready_timeout_o,
    output wire [31:0]  frame_timeout_o,
    output wire [31:0]  exc_ready_timeout_o,
    output wire [255:0] phase_cfg_flat_o,
    output wire [255:0] phase_settle_flat_o,

    input  wire         busy_i,
    input  wire         done_i,
    input  wire         aborted_i,
    input  wire         failed_i,
    input  wire [15:0]  measurement_id_i,
    input  wire [2:0]   current_phase_index_i,
    input  wire [1:0]   current_phase_type_i,
    input  wire [7:0]   current_frame_index_i,
    input  wire         current_phase_valid_i,

    input  wire [7:0]   hw_error_set_i,
    output wire [7:0]   error_status_o,

    input  wire [9:0]   int_status_i,
    input  wire [9:0]   int_enable_i,
    output wire [9:0]   int_status_sw_clear_o,
    output wire         int_enable_we_o,
    output wire [9:0]   int_enable_wdata_o
);

    localparam [11:0] A_CTRL                 = 12'h000;
    localparam [11:0] A_STATUS               = 12'h004;
    localparam [11:0] A_PHASE_COUNT          = 12'h008;
    localparam [11:0] A_SENSOR_READY_TIMEOUT = 12'h00C;
    localparam [11:0] A_FRAME_TIMEOUT        = 12'h010;
    localparam [11:0] A_EXC_READY_TIMEOUT    = 12'h014;
    localparam [11:0] A_MEASUREMENT_ID       = 12'h018;
    localparam [11:0] A_CURRENT_PHASE        = 12'h01C;
    localparam [11:0] A_ERROR_STATUS         = 12'h020;
    localparam [11:0] A_INT_STATUS           = 12'h024;
    localparam [11:0] A_INT_ENABLE           = 12'h028;
    localparam [11:0] A_VERSION              = 12'h02C;

    reg        enable_q;
    reg [3:0]  phase_count_q;
    reg [31:0] sensor_ready_timeout_q;
    reg [31:0] frame_timeout_q;
    reg [31:0] exc_ready_timeout_q;
    reg [31:0] phase_cfg_q [0:7];
    reg [31:0] phase_settle_q [0:7];
    reg [7:0]  error_status_q;

    integer i;

    wire [7:0] error_sw_clear;

    assign enable_o               = enable_q;
    assign phase_count_o          = phase_count_q;
    assign sensor_ready_timeout_o = sensor_ready_timeout_q;
    assign frame_timeout_o        = frame_timeout_q;
    assign exc_ready_timeout_o    = exc_ready_timeout_q;
    assign error_status_o         = error_status_q;

    assign phase_cfg_flat_o = {
        phase_cfg_q[7], phase_cfg_q[6], phase_cfg_q[5], phase_cfg_q[4],
        phase_cfg_q[3], phase_cfg_q[2], phase_cfg_q[1], phase_cfg_q[0]
    };

    assign phase_settle_flat_o = {
        phase_settle_q[7], phase_settle_q[6], phase_settle_q[5], phase_settle_q[4],
        phase_settle_q[3], phase_settle_q[2], phase_settle_q[1], phase_settle_q[0]
    };

    assign error_sw_clear = (csr_write_i && (csr_addr_i == A_ERROR_STATUS)) ?
                            csr_wdata_i[7:0] : 8'd0;

    assign int_status_sw_clear_o = (csr_write_i && (csr_addr_i == A_INT_STATUS)) ?
                                   csr_wdata_i[9:0] : 10'd0;

    assign int_enable_we_o    = csr_write_i && (csr_addr_i == A_INT_ENABLE);
    assign int_enable_wdata_o = csr_wdata_i[9:0];

    // Address-valid decode is intentionally shared by read and write accesses.
    always @(*) begin
        csr_addr_valid_o = 1'b1;
        case (csr_addr_i)
            A_CTRL,
            A_STATUS,
            A_PHASE_COUNT,
            A_SENSOR_READY_TIMEOUT,
            A_FRAME_TIMEOUT,
            A_EXC_READY_TIMEOUT,
            A_MEASUREMENT_ID,
            A_CURRENT_PHASE,
            A_ERROR_STATUS,
            A_INT_STATUS,
            A_INT_ENABLE,
            A_VERSION,
            12'h040, 12'h044,
            12'h048, 12'h04C,
            12'h050, 12'h054,
            12'h058, 12'h05C,
            12'h060, 12'h064,
            12'h068, 12'h06C,
            12'h070, 12'h074,
            12'h078, 12'h07C:
                csr_addr_valid_o = 1'b1;
            default:
                csr_addr_valid_o = 1'b0;
        endcase
    end

    always @(*) begin
        csr_rdata_o = 32'd0;
        case (csr_addr_i)
            A_CTRL: begin
                csr_rdata_o[0] = enable_q;
            end
            A_STATUS: begin
                csr_rdata_o[0] = busy_i;
                csr_rdata_o[1] = done_i;
                csr_rdata_o[2] = aborted_i;
                csr_rdata_o[3] = failed_i;
                csr_rdata_o[4] = enable_q;
            end
            A_PHASE_COUNT: begin
                csr_rdata_o[3:0] = phase_count_q;
            end
            A_SENSOR_READY_TIMEOUT: csr_rdata_o = sensor_ready_timeout_q;
            A_FRAME_TIMEOUT:        csr_rdata_o = frame_timeout_q;
            A_EXC_READY_TIMEOUT:    csr_rdata_o = exc_ready_timeout_q;
            A_MEASUREMENT_ID: begin
                csr_rdata_o[15:0] = measurement_id_i;
            end
            A_CURRENT_PHASE: begin
                csr_rdata_o[2:0]   = current_phase_index_i;
                csr_rdata_o[5:4]   = current_phase_valid_i ? current_phase_type_i : 2'b00;
                csr_rdata_o[15:8]  = current_phase_valid_i ? current_frame_index_i : 8'd0;
                csr_rdata_o[16]    = current_phase_valid_i;
            end
            A_ERROR_STATUS: csr_rdata_o[7:0] = error_status_q;
            A_INT_STATUS:   csr_rdata_o[9:0] = int_status_i;
            A_INT_ENABLE:   csr_rdata_o[9:0] = int_enable_i;
            A_VERSION:      csr_rdata_o = 32'h0001_0000;
            12'h040: csr_rdata_o = phase_cfg_q[0];
            12'h044: csr_rdata_o = phase_settle_q[0];
            12'h048: csr_rdata_o = phase_cfg_q[1];
            12'h04C: csr_rdata_o = phase_settle_q[1];
            12'h050: csr_rdata_o = phase_cfg_q[2];
            12'h054: csr_rdata_o = phase_settle_q[2];
            12'h058: csr_rdata_o = phase_cfg_q[3];
            12'h05C: csr_rdata_o = phase_settle_q[3];
            12'h060: csr_rdata_o = phase_cfg_q[4];
            12'h064: csr_rdata_o = phase_settle_q[4];
            12'h068: csr_rdata_o = phase_cfg_q[5];
            12'h06C: csr_rdata_o = phase_settle_q[5];
            12'h070: csr_rdata_o = phase_cfg_q[6];
            12'h074: csr_rdata_o = phase_settle_q[6];
            12'h078: csr_rdata_o = phase_cfg_q[7];
            12'h07C: csr_rdata_o = phase_settle_q[7];
            default: csr_rdata_o = 32'd0;
        endcase
    end

    // csr_read_i is intentionally side-effect free in V1.
    wire unused_read;
    assign unused_read = csr_read_i;

    always @(posedge hclk_i or negedge hreset_ni) begin
        if (!hreset_ni) begin
            enable_q               <= 1'b0;
            phase_count_q          <= 4'd0;
            sensor_ready_timeout_q <= 32'd0;
            frame_timeout_q        <= 32'd0;
            exc_ready_timeout_q    <= 32'd0;
            error_status_q         <= 8'd0;
            start_req_o            <= 1'b0;
            abort_req_o            <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                phase_cfg_q[i]    <= 32'd0;
                phase_settle_q[i] <= 32'd0;
            end
        end else begin
            // W1P commands default low every clock.
            start_req_o <= 1'b0;
            abort_req_o <= 1'b0;

            // HW set wins over SW W1C.
            error_status_q <= (error_status_q & ~error_sw_clear) | hw_error_set_i;

            if (csr_write_i) begin
                case (csr_addr_i)
                    A_CTRL: begin
                        enable_q    <= csr_wdata_i[0];
                        start_req_o <= csr_wdata_i[1];
                        abort_req_o <= csr_wdata_i[2];
                    end
                    A_PHASE_COUNT: begin
                        phase_count_q <= csr_wdata_i[3:0];
                    end
                    A_SENSOR_READY_TIMEOUT: begin
                        sensor_ready_timeout_q <= csr_wdata_i;
                    end
                    A_FRAME_TIMEOUT: begin
                        frame_timeout_q <= csr_wdata_i;
                    end
                    A_EXC_READY_TIMEOUT: begin
                        exc_ready_timeout_q <= csr_wdata_i;
                    end
                    12'h040: phase_cfg_q[0]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h044: phase_settle_q[0] <= csr_wdata_i;
                    12'h048: phase_cfg_q[1]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h04C: phase_settle_q[1] <= csr_wdata_i;
                    12'h050: phase_cfg_q[2]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h054: phase_settle_q[2] <= csr_wdata_i;
                    12'h058: phase_cfg_q[3]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h05C: phase_settle_q[3] <= csr_wdata_i;
                    12'h060: phase_cfg_q[4]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h064: phase_settle_q[4] <= csr_wdata_i;
                    12'h068: phase_cfg_q[5]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h06C: phase_settle_q[5] <= csr_wdata_i;
                    12'h070: phase_cfg_q[6]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h074: phase_settle_q[6] <= csr_wdata_i;
                    12'h078: phase_cfg_q[7]    <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                    12'h07C: phase_settle_q[7] <= csr_wdata_i;
                    default: begin
                        // RO, W1C-owned-elsewhere, and reserved bits are ignored.
                    end
                endcase
            end
        end
    end

endmodule
