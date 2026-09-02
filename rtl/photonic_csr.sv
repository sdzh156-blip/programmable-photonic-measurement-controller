`default_nettype none

module photonic_csr #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer PHASES     = 8
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,

    input  logic                     csr_wr_en_i,
    input  logic                     csr_rd_en_i,
    input  logic [ADDR_WIDTH-1:0]    csr_addr_i,
    input  logic [31:0]              csr_wdata_i,
    output logic [31:0]              csr_rdata_o,
    output logic                     csr_error_o,

    output logic                     enable_o,
    output logic                     start_req_o,
    output logic                     abort_req_o,
    output logic                     start_enable_value_o,
    output logic [3:0]               phase_count_o,
    output logic [31:0]              sensor_ready_timeout_o,
    output logic [31:0]              frame_timeout_o,
    output logic [31:0]              excitation_ready_timeout_o,
    output logic [15:0]              trigger_width_o,
    output logic [PHASES*32-1:0]     phase_cfg_flat_o,
    output logic [PHASES*32-1:0]     phase_time_flat_o,

    input  logic                     busy_i,
    input  logic                     done_i,
    input  logic                     aborted_i,
    input  logic                     failed_i,
    input  logic [31:0]              measurement_id_i,
    input  logic [2:0]               current_phase_i,
    input  logic [7:0]               current_frame_i,

    input  logic [7:0]               error_hw_set_i,
    output logic [7:0]               error_status_o,

    input  logic [9:0]               int_status_i,
    input  logic [9:0]               int_enable_i,
    output logic [9:0]               int_sw_clear_o,
    output logic                     int_enable_we_o,
    output logic [9:0]               int_enable_wdata_o
);
    localparam logic [ADDR_WIDTH-1:0] A_CTRL            = 12'h000;
    localparam logic [ADDR_WIDTH-1:0] A_STATUS          = 12'h004;
    localparam logic [ADDR_WIDTH-1:0] A_PHASE_COUNT     = 12'h008;
    localparam logic [ADDR_WIDTH-1:0] A_SENSOR_RDY_TO   = 12'h00C;
    localparam logic [ADDR_WIDTH-1:0] A_FRAME_TO        = 12'h010;
    localparam logic [ADDR_WIDTH-1:0] A_EXC_RDY_TO      = 12'h014;
    localparam logic [ADDR_WIDTH-1:0] A_TRIGGER_WIDTH   = 12'h018;
    localparam logic [ADDR_WIDTH-1:0] A_MEASUREMENT_ID  = 12'h01C;
    localparam logic [ADDR_WIDTH-1:0] A_CURRENT_PHASE   = 12'h020;
    localparam logic [ADDR_WIDTH-1:0] A_CURRENT_FRAME   = 12'h024;
    localparam logic [ADDR_WIDTH-1:0] A_ERROR_STATUS    = 12'h028;
    localparam logic [ADDR_WIDTH-1:0] A_INT_STATUS      = 12'h02C;
    localparam logic [ADDR_WIDTH-1:0] A_INT_ENABLE      = 12'h030;
    localparam logic [ADDR_WIDTH-1:0] A_VERSION         = 12'h034;
    localparam logic [ADDR_WIDTH-1:0] A_PHASE_BASE      = 12'h040;

    logic                         enable_q;
    logic [3:0]                   phase_count_q;
    logic [31:0]                  sensor_ready_timeout_q;
    logic [31:0]                  frame_timeout_q;
    logic [31:0]                  excitation_ready_timeout_q;
    logic [15:0]                  trigger_width_q;
    logic [PHASES*32-1:0]         phase_cfg_flat_q;
    logic [PHASES*32-1:0]         phase_time_flat_q;
    logic [7:0]                   error_status_q;
    logic [7:0]                   error_sw_clear;

    logic                         addr_mapped;
    logic                         write_legal;
    logic [2:0]                   phase_index;
    logic                         phase_window;
    logic                         phase_cfg_sel;

    assign phase_window = (csr_addr_i >= A_PHASE_BASE) && (csr_addr_i <= 12'h07C);
    assign phase_index  = (csr_addr_i - A_PHASE_BASE) >> 3;
    assign phase_cfg_sel = (csr_addr_i[2] == 1'b0);

    always_comb begin
        addr_mapped = 1'b1;
        case (csr_addr_i)
            A_CTRL,
            A_STATUS,
            A_PHASE_COUNT,
            A_SENSOR_RDY_TO,
            A_FRAME_TO,
            A_EXC_RDY_TO,
            A_TRIGGER_WIDTH,
            A_MEASUREMENT_ID,
            A_CURRENT_PHASE,
            A_CURRENT_FRAME,
            A_ERROR_STATUS,
            A_INT_STATUS,
            A_INT_ENABLE,
            A_VERSION: addr_mapped = 1'b1;
            default: addr_mapped = phase_window;
        endcase
    end

    always_comb begin
        write_legal = 1'b0;
        case (csr_addr_i)
            A_CTRL,
            A_PHASE_COUNT,
            A_SENSOR_RDY_TO,
            A_FRAME_TO,
            A_EXC_RDY_TO,
            A_TRIGGER_WIDTH,
            A_ERROR_STATUS,
            A_INT_STATUS,
            A_INT_ENABLE: write_legal = 1'b1;
            default: write_legal = phase_window;
        endcase
    end

    assign csr_error_o = (csr_wr_en_i || csr_rd_en_i) &&
                         (!addr_mapped || (csr_wr_en_i && !write_legal));

    assign start_req_o          = csr_wr_en_i && (csr_addr_i == A_CTRL) && csr_wdata_i[1];
    assign abort_req_o          = csr_wr_en_i && (csr_addr_i == A_CTRL) && csr_wdata_i[2];
    assign start_enable_value_o = csr_wdata_i[0];

    assign error_sw_clear       = (csr_wr_en_i && (csr_addr_i == A_ERROR_STATUS)) ? csr_wdata_i[7:0] : 8'd0;
    assign int_sw_clear_o       = (csr_wr_en_i && (csr_addr_i == A_INT_STATUS)) ? csr_wdata_i[9:0] : 10'd0;
    assign int_enable_we_o      = csr_wr_en_i && (csr_addr_i == A_INT_ENABLE);
    assign int_enable_wdata_o   = csr_wdata_i[9:0];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            enable_q                    <= 1'b0;
            phase_count_q               <= 4'd0;
            sensor_ready_timeout_q      <= 32'd0;
            frame_timeout_q             <= 32'd0;
            excitation_ready_timeout_q  <= 32'd0;
            trigger_width_q              <= 16'd1;
            phase_cfg_flat_q             <= '0;
            phase_time_flat_q            <= '0;
            error_status_q               <= 8'd0;
        end else begin
            error_status_q <= (error_status_q & ~error_sw_clear) | error_hw_set_i;

            if (csr_wr_en_i && !csr_error_o) begin
                case (csr_addr_i)
                    A_CTRL: begin
                        enable_q <= csr_wdata_i[0];
                    end
                    A_PHASE_COUNT: begin
                        phase_count_q <= csr_wdata_i[3:0];
                    end
                    A_SENSOR_RDY_TO: begin
                        sensor_ready_timeout_q <= csr_wdata_i;
                    end
                    A_FRAME_TO: begin
                        frame_timeout_q <= csr_wdata_i;
                    end
                    A_EXC_RDY_TO: begin
                        excitation_ready_timeout_q <= csr_wdata_i;
                    end
                    A_TRIGGER_WIDTH: begin
                        trigger_width_q <= csr_wdata_i[15:0];
                    end
                    default: begin
                        if (phase_window && (phase_index < PHASES)) begin
                            if (phase_cfg_sel) begin
                                phase_cfg_flat_q[phase_index*32 +: 32] <= {16'd0, csr_wdata_i[15:8], 6'd0, csr_wdata_i[1:0]};
                            end else begin
                                phase_time_flat_q[phase_index*32 +: 32] <= csr_wdata_i;
                            end
                        end
                    end
                endcase
            end
        end
    end

    always_comb begin
        csr_rdata_o = 32'd0;
        case (csr_addr_i)
            A_CTRL:           csr_rdata_o = {31'd0, enable_q};
            A_STATUS:         csr_rdata_o = {28'd0, failed_i, aborted_i, done_i, busy_i};
            A_PHASE_COUNT:    csr_rdata_o = {28'd0, phase_count_q};
            A_SENSOR_RDY_TO:  csr_rdata_o = sensor_ready_timeout_q;
            A_FRAME_TO:       csr_rdata_o = frame_timeout_q;
            A_EXC_RDY_TO:     csr_rdata_o = excitation_ready_timeout_q;
            A_TRIGGER_WIDTH:  csr_rdata_o = {16'd0, trigger_width_q};
            A_MEASUREMENT_ID: csr_rdata_o = measurement_id_i;
            A_CURRENT_PHASE:  csr_rdata_o = {29'd0, current_phase_i};
            A_CURRENT_FRAME:  csr_rdata_o = {24'd0, current_frame_i};
            A_ERROR_STATUS:   csr_rdata_o = {24'd0, error_status_q};
            A_INT_STATUS:     csr_rdata_o = {22'd0, int_status_i};
            A_INT_ENABLE:     csr_rdata_o = {22'd0, int_enable_i};
            A_VERSION:        csr_rdata_o = 32'h0002_0000;
            default: begin
                if (phase_window && (phase_index < PHASES)) begin
                    if (phase_cfg_sel) begin
                        csr_rdata_o = phase_cfg_flat_q[phase_index*32 +: 32];
                    end else begin
                        csr_rdata_o = phase_time_flat_q[phase_index*32 +: 32];
                    end
                end
            end
        endcase
    end

    assign enable_o                   = enable_q;
    assign phase_count_o              = phase_count_q;
    assign sensor_ready_timeout_o     = sensor_ready_timeout_q;
    assign frame_timeout_o            = frame_timeout_q;
    assign excitation_ready_timeout_o = excitation_ready_timeout_q;
    assign trigger_width_o            = trigger_width_q;
    assign phase_cfg_flat_o           = phase_cfg_flat_q;
    assign phase_time_flat_o          = phase_time_flat_q;
    assign error_status_o             = error_status_q;

endmodule

`default_nettype wire
