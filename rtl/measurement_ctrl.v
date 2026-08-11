`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// measurement_ctrl.v
// Core programmable measurement sequencer.
//
// Owns:
//   * START acceptance / recipe validation
//   * Atomic active-configuration snapshot
//   * Sequential phase execution (DARK / SIGNAL / WAIT)
//   * Shared-timer control, frame counter, trigger/tag generation
//   * Event priority and terminal commit
//   * Safe-state control
// -----------------------------------------------------------------------------
module measurement_ctrl (
    input  wire         hclk_i,
    input  wire         hreset_ni,

    input  wire         start_req_i,
    input  wire         abort_req_i,
    input  wire         enable_i,

    input  wire [3:0]   prog_phase_count_i,
    input  wire [31:0]  prog_sensor_ready_timeout_i,
    input  wire [31:0]  prog_frame_timeout_i,
    input  wire [31:0]  prog_exc_ready_timeout_i,
    input  wire [255:0] prog_phase_cfg_flat_i,
    input  wire [255:0] prog_phase_settle_flat_i,

    input  wire         sensor_ready_i,
    input  wire         sensor_frame_done_i,
    input  wire         sensor_error_i,
    input  wire         excitation_ready_i,
    input  wire         excitation_fault_i,

    output reg          timer_start_o,
    output reg          timer_stop_o,
    output reg  [31:0]  timer_load_value_o,
    input  wire         timer_running_i,
    input  wire         timer_expire_i,

    output wire         busy_o,
    output wire         done_o,
    output wire         aborted_o,
    output wire         failed_o,
    output wire [15:0]  measurement_id_o,
    output wire [2:0]   current_phase_index_o,
    output wire [1:0]   current_phase_type_o,
    output wire [7:0]   current_frame_index_o,
    output wire         current_phase_valid_o,

    output wire         sensor_trigger_o,
    output wire         frame_tag_valid_o,
    output wire         frame_type_o,
    output wire         excitation_enable_o,

    output reg  [7:0]   hw_error_set_o,
    output reg  [9:0]   irq_hw_set_o
);

    localparam [1:0] PH_DARK   = 2'b00;
    localparam [1:0] PH_SIGNAL = 2'b01;
    localparam [1:0] PH_WAIT   = 2'b10;

    localparam [3:0] ST_IDLE              = 4'd0;
    localparam [3:0] ST_LOAD_PHASE        = 4'd1;
    localparam [3:0] ST_WAIT_EXC_READY    = 4'd2;
    localparam [3:0] ST_SETTLE            = 4'd3;
    localparam [3:0] ST_WAIT_SENSOR_READY = 4'd4;
    localparam [3:0] ST_WAIT_FRAME        = 4'd5;
    localparam [3:0] ST_FRAME_NEXT        = 4'd6;
    localparam [3:0] ST_PHASE_NEXT        = 4'd7;
    localparam [3:0] ST_COMPLETE          = 4'd8;
    localparam [3:0] ST_SAFE_EXIT         = 4'd9;

    localparam integer E_CONFIG_ERROR         = 0;
    localparam integer E_CMD_REJECT           = 1;
    localparam integer E_SENSOR_READY_TIMEOUT = 2;
    localparam integer E_SENSOR_FRAME_TIMEOUT = 3;
    localparam integer E_SENSOR_ERROR         = 4;
    localparam integer E_EXC_READY_TIMEOUT    = 5;
    localparam integer E_EXCITATION_FAULT     = 6;
    localparam integer E_ILLEGAL_STATE        = 7;

    localparam integer I_MEAS_DONE            = 0;
    localparam integer I_ABORT_DONE           = 1;
    localparam integer I_CONFIG_ERROR         = 2;
    localparam integer I_CMD_REJECT           = 3;
    localparam integer I_SENSOR_READY_TIMEOUT = 4;
    localparam integer I_SENSOR_FRAME_TIMEOUT = 5;
    localparam integer I_SENSOR_ERROR         = 6;
    localparam integer I_EXC_READY_TIMEOUT    = 7;
    localparam integer I_EXCITATION_FAULT     = 8;
    localparam integer I_ILLEGAL_STATE        = 9;

    reg [3:0]  state_q, state_d;
    reg        busy_q, busy_d;
    reg        done_q, done_d;
    reg        aborted_q, aborted_d;
    reg        failed_q, failed_d;
    reg [15:0] measurement_id_q, measurement_id_d;
    reg [2:0]  phase_index_q, phase_index_d;
    reg [7:0]  frame_index_q, frame_index_d;
    reg        phase_valid_q, phase_valid_d;
    reg        excitation_enable_q, excitation_enable_d;
    reg        sensor_trigger_q, sensor_trigger_d;
    reg        frame_tag_valid_q, frame_tag_valid_d;
    reg        frame_type_q, frame_type_d;

    reg [3:0]   active_phase_count_q;
    reg [31:0]  active_sensor_ready_timeout_q;
    reg [31:0]  active_frame_timeout_q;
    reg [31:0]  active_exc_ready_timeout_q;
    reg [255:0] active_phase_cfg_flat_q;
    reg [255:0] active_phase_settle_flat_q;
    reg         snapshot_take;

    reg recipe_valid_comb;
    reg has_capture_comb;
    reg has_signal_comb;
    integer vi;
    reg [31:0] vcfg;
    reg [1:0]  vtype;
    reg [7:0]  vframes;

    reg [31:0] current_cfg;
    reg [31:0] current_settle;
    reg [31:0] next_cfg;
    wire [1:0] current_type;
    wire [7:0] current_frame_num;
    wire [1:0] next_type;
    wire       has_next_phase;
    wire       more_frames;

    reg state_legal_comb;
    wire illegal_state_comb;

    wire start_accept_comb;
    wire start_cmd_reject_comb;
    wire start_config_error_comb;
    wire abort_active_comb;

    wire unused_timer_running;
    assign unused_timer_running = timer_running_i;

    function [31:0] select_word256;
        input [255:0] bus;
        input [2:0]   idx;
        begin
            case (idx)
                3'd0: select_word256 = bus[31:0];
                3'd1: select_word256 = bus[63:32];
                3'd2: select_word256 = bus[95:64];
                3'd3: select_word256 = bus[127:96];
                3'd4: select_word256 = bus[159:128];
                3'd5: select_word256 = bus[191:160];
                3'd6: select_word256 = bus[223:192];
                3'd7: select_word256 = bus[255:224];
                default: select_word256 = 32'd0;
            endcase
        end
    endfunction

    assign busy_o                 = busy_q;
    assign done_o                 = done_q;
    assign aborted_o              = aborted_q;
    assign failed_o               = failed_q;
    assign measurement_id_o       = measurement_id_q;
    assign current_phase_index_o  = phase_index_q;
    assign current_phase_type_o   = phase_valid_q ? current_type : 2'b00;
    assign current_frame_index_o  = phase_valid_q ? frame_index_q : 8'd0;
    assign current_phase_valid_o  = phase_valid_q;
    assign sensor_trigger_o       = sensor_trigger_q;
    assign frame_tag_valid_o      = frame_tag_valid_q;
    assign frame_type_o           = frame_type_q;
    assign excitation_enable_o    = excitation_enable_q;

    assign current_type      = current_cfg[1:0];
    assign current_frame_num = current_cfg[15:8];
    assign next_type         = next_cfg[1:0];
    assign has_next_phase    = ({1'b0, phase_index_q} + 4'd1) < active_phase_count_q;
    assign more_frames       = (frame_index_q + 8'd1) < current_frame_num;

    always @(*) begin
        current_cfg    = select_word256(active_phase_cfg_flat_q, phase_index_q);
        current_settle = select_word256(active_phase_settle_flat_q, phase_index_q);
        if (phase_index_q < 3'd7)
            next_cfg = select_word256(active_phase_cfg_flat_q, phase_index_q + 3'd1);
        else
            next_cfg = 32'd0;
    end

    always @(*) begin
        recipe_valid_comb = 1'b1;
        has_capture_comb  = 1'b0;
        has_signal_comb   = 1'b0;

        if ((prog_phase_count_i < 4'd1) || (prog_phase_count_i > 4'd8))
            recipe_valid_comb = 1'b0;

        for (vi = 0; vi < 8; vi = vi + 1) begin
            if (vi < prog_phase_count_i) begin
                vcfg    = prog_phase_cfg_flat_i[(vi*32) +: 32];
                vtype   = vcfg[1:0];
                vframes = vcfg[15:8];

                case (vtype)
                    PH_DARK: begin
                        has_capture_comb = 1'b1;
                        if (vframes == 8'd0)
                            recipe_valid_comb = 1'b0;
                    end
                    PH_SIGNAL: begin
                        has_capture_comb = 1'b1;
                        has_signal_comb  = 1'b1;
                        if (vframes == 8'd0)
                            recipe_valid_comb = 1'b0;
                    end
                    PH_WAIT: begin
                        if (vframes != 8'd0)
                            recipe_valid_comb = 1'b0;
                    end
                    default: recipe_valid_comb = 1'b0;
                endcase
            end
        end

        if (!has_capture_comb)
            recipe_valid_comb = 1'b0;

        if (has_capture_comb &&
            ((prog_sensor_ready_timeout_i == 32'd0) ||
             (prog_frame_timeout_i == 32'd0)))
            recipe_valid_comb = 1'b0;

        if (has_signal_comb && (prog_exc_ready_timeout_i == 32'd0))
            recipe_valid_comb = 1'b0;
    end

    always @(*) begin
        state_legal_comb = 1'b1;
        case (state_q)
            ST_IDLE,
            ST_LOAD_PHASE,
            ST_WAIT_EXC_READY,
            ST_SETTLE,
            ST_WAIT_SENSOR_READY,
            ST_WAIT_FRAME,
            ST_FRAME_NEXT,
            ST_PHASE_NEXT,
            ST_COMPLETE,
            ST_SAFE_EXIT: state_legal_comb = 1'b1;
            default:      state_legal_comb = 1'b0;
        endcase
    end

    assign illegal_state_comb = !state_legal_comb;

    assign start_accept_comb = start_req_i &&
                               !abort_req_i &&
                               (state_q == ST_IDLE) &&
                               !busy_q &&
                               enable_i &&
                               !sensor_error_i &&
                               !excitation_fault_i &&
                               recipe_valid_comb;

    assign start_config_error_comb = start_req_i &&
                                     !abort_req_i &&
                                     (state_q == ST_IDLE) &&
                                     !busy_q &&
                                     enable_i &&
                                     !sensor_error_i &&
                                     !excitation_fault_i &&
                                     !recipe_valid_comb;

    assign start_cmd_reject_comb = start_req_i &&
                                   !start_accept_comb &&
                                   !start_config_error_comb;

    assign abort_active_comb = busy_q && (abort_req_i || !enable_i);

    always @(*) begin
        state_d              = state_q;
        busy_d               = busy_q;
        done_d               = done_q;
        aborted_d            = aborted_q;
        failed_d             = failed_q;
        measurement_id_d     = measurement_id_q;
        phase_index_d        = phase_index_q;
        frame_index_d        = frame_index_q;
        phase_valid_d        = phase_valid_q;
        excitation_enable_d  = excitation_enable_q;
        sensor_trigger_d     = 1'b0;
        frame_tag_valid_d    = 1'b0;
        frame_type_d         = frame_type_q;
        snapshot_take        = 1'b0;

        timer_start_o        = 1'b0;
        timer_stop_o         = 1'b0;
        timer_load_value_o   = 32'd0;
        hw_error_set_o       = 8'd0;
        irq_hw_set_o         = 10'd0;

        if (sensor_error_i) begin
            hw_error_set_o[E_SENSOR_ERROR] = 1'b1;
            irq_hw_set_o[I_SENSOR_ERROR]   = 1'b1;
        end
        if (excitation_fault_i) begin
            hw_error_set_o[E_EXCITATION_FAULT] = 1'b1;
            irq_hw_set_o[I_EXCITATION_FAULT]   = 1'b1;
        end

        if (start_config_error_comb) begin
            hw_error_set_o[E_CONFIG_ERROR] = 1'b1;
            irq_hw_set_o[I_CONFIG_ERROR]   = 1'b1;
        end
        if (start_cmd_reject_comb) begin
            hw_error_set_o[E_CMD_REJECT] = 1'b1;
            irq_hw_set_o[I_CMD_REJECT]   = 1'b1;
        end

        if (illegal_state_comb) begin
            hw_error_set_o[E_ILLEGAL_STATE] = 1'b1;
            irq_hw_set_o[I_ILLEGAL_STATE]   = 1'b1;
            timer_stop_o                    = 1'b1;
            busy_d                          = 1'b0;
            done_d                          = 1'b0;
            aborted_d                       = 1'b0;
            failed_d                        = 1'b1;
            phase_valid_d                   = 1'b0;
            excitation_enable_d             = 1'b0;
            sensor_trigger_d                = 1'b0;
            frame_tag_valid_d               = 1'b0;
            state_d                         = ST_SAFE_EXIT;
        end else if (busy_q && (sensor_error_i || excitation_fault_i)) begin
            timer_stop_o        = 1'b1;
            busy_d              = 1'b0;
            done_d              = 1'b0;
            aborted_d           = 1'b0;
            failed_d            = 1'b1;
            phase_valid_d       = 1'b0;
            excitation_enable_d = 1'b0;
            state_d             = ST_SAFE_EXIT;
        end else if (abort_active_comb) begin
            timer_stop_o        = 1'b1;
            busy_d              = 1'b0;
            done_d              = 1'b0;
            aborted_d           = 1'b1;
            failed_d            = 1'b0;
            phase_valid_d       = 1'b0;
            excitation_enable_d = 1'b0;
            irq_hw_set_o[I_ABORT_DONE] = 1'b1;
            state_d             = ST_SAFE_EXIT;
        end else if (start_accept_comb) begin
            timer_stop_o        = 1'b1;
            busy_d              = 1'b1;
            done_d              = 1'b0;
            aborted_d           = 1'b0;
            failed_d            = 1'b0;
            measurement_id_d    = measurement_id_q + 16'd1;
            phase_index_d       = 3'd0;
            frame_index_d       = 8'd0;
            phase_valid_d       = 1'b0;
            excitation_enable_d = 1'b0;
            snapshot_take       = 1'b1;
            state_d             = ST_LOAD_PHASE;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    excitation_enable_d = 1'b0;
                    phase_valid_d       = 1'b0;
                end

                ST_LOAD_PHASE: begin
                    phase_valid_d = 1'b1;
                    frame_index_d = 8'd0;

                    case (current_type)
                        PH_DARK: begin
                            excitation_enable_d = 1'b0;
                            if (current_settle == 32'd0) begin
                                timer_start_o      = 1'b1;
                                timer_load_value_o = active_sensor_ready_timeout_q;
                                state_d            = ST_WAIT_SENSOR_READY;
                            end else begin
                                timer_start_o      = 1'b1;
                                timer_load_value_o = current_settle;
                                state_d            = ST_SETTLE;
                            end
                        end

                        PH_SIGNAL: begin
                            excitation_enable_d = 1'b1;
                            timer_start_o        = 1'b1;
                            timer_load_value_o   = active_exc_ready_timeout_q;
                            state_d              = ST_WAIT_EXC_READY;
                        end

                        PH_WAIT: begin
                            excitation_enable_d = 1'b0;
                            if (current_settle == 32'd0) begin
                                phase_valid_d = 1'b0;
                                if (has_next_phase) begin
                                    state_d = ST_PHASE_NEXT;
                                end else begin
                                    busy_d                    = 1'b0;
                                    done_d                    = 1'b1;
                                    aborted_d                 = 1'b0;
                                    failed_d                  = 1'b0;
                                    irq_hw_set_o[I_MEAS_DONE] = 1'b1;
                                    state_d                   = ST_COMPLETE;
                                end
                            end else begin
                                timer_start_o      = 1'b1;
                                timer_load_value_o = current_settle;
                                state_d            = ST_SETTLE;
                            end
                        end

                        default: begin
                            hw_error_set_o[E_ILLEGAL_STATE] = 1'b1;
                            irq_hw_set_o[I_ILLEGAL_STATE]   = 1'b1;
                            timer_stop_o                    = 1'b1;
                            busy_d                          = 1'b0;
                            done_d                          = 1'b0;
                            aborted_d                       = 1'b0;
                            failed_d                        = 1'b1;
                            phase_valid_d                   = 1'b0;
                            excitation_enable_d             = 1'b0;
                            state_d                         = ST_SAFE_EXIT;
                        end
                    endcase
                end

                ST_WAIT_EXC_READY: begin
                    if (excitation_ready_i) begin
                        if (current_settle == 32'd0) begin
                            timer_start_o      = 1'b1;
                            timer_load_value_o = active_sensor_ready_timeout_q;
                            state_d            = ST_WAIT_SENSOR_READY;
                        end else begin
                            timer_start_o      = 1'b1;
                            timer_load_value_o = current_settle;
                            state_d            = ST_SETTLE;
                        end
                    end else if (timer_expire_i) begin
                        hw_error_set_o[E_EXC_READY_TIMEOUT] = 1'b1;
                        irq_hw_set_o[I_EXC_READY_TIMEOUT]   = 1'b1;
                        timer_stop_o                        = 1'b1;
                        busy_d                              = 1'b0;
                        done_d                              = 1'b0;
                        aborted_d                           = 1'b0;
                        failed_d                            = 1'b1;
                        phase_valid_d                       = 1'b0;
                        excitation_enable_d                 = 1'b0;
                        state_d                             = ST_SAFE_EXIT;
                    end
                end

                ST_SETTLE: begin
                    if (timer_expire_i) begin
                        if (current_type == PH_WAIT) begin
                            phase_valid_d = 1'b0;
                            if (has_next_phase) begin
                                state_d = ST_PHASE_NEXT;
                            end else begin
                                busy_d                    = 1'b0;
                                done_d                    = 1'b1;
                                aborted_d                 = 1'b0;
                                failed_d                  = 1'b0;
                                excitation_enable_d       = 1'b0;
                                irq_hw_set_o[I_MEAS_DONE] = 1'b1;
                                state_d                   = ST_COMPLETE;
                            end
                        end else begin
                            timer_start_o      = 1'b1;
                            timer_load_value_o = active_sensor_ready_timeout_q;
                            state_d            = ST_WAIT_SENSOR_READY;
                        end
                    end
                end

                ST_WAIT_SENSOR_READY: begin
                    if (sensor_ready_i) begin
                        sensor_trigger_d    = 1'b1;
                        frame_tag_valid_d   = 1'b1;
                        frame_type_d        = (current_type == PH_SIGNAL);
                        timer_start_o       = 1'b1;
                        timer_load_value_o  = active_frame_timeout_q;
                        state_d             = ST_WAIT_FRAME;
                    end else if (timer_expire_i) begin
                        hw_error_set_o[E_SENSOR_READY_TIMEOUT] = 1'b1;
                        irq_hw_set_o[I_SENSOR_READY_TIMEOUT]   = 1'b1;
                        timer_stop_o                           = 1'b1;
                        busy_d                                 = 1'b0;
                        done_d                                 = 1'b0;
                        aborted_d                              = 1'b0;
                        failed_d                               = 1'b1;
                        phase_valid_d                          = 1'b0;
                        excitation_enable_d                    = 1'b0;
                        state_d                                = ST_SAFE_EXIT;
                    end
                end

                ST_WAIT_FRAME: begin
                    if (sensor_frame_done_i) begin
                        timer_stop_o = 1'b1;
                        if (more_frames) begin
                            frame_index_d = frame_index_q + 8'd1;
                            state_d       = ST_FRAME_NEXT;
                        end else begin
                            phase_valid_d = 1'b0;

                            if (current_type == PH_SIGNAL) begin
                                if (!(has_next_phase && (next_type == PH_SIGNAL)))
                                    excitation_enable_d = 1'b0;
                            end

                            if (has_next_phase) begin
                                state_d = ST_PHASE_NEXT;
                            end else begin
                                busy_d                    = 1'b0;
                                done_d                    = 1'b1;
                                aborted_d                 = 1'b0;
                                failed_d                  = 1'b0;
                                excitation_enable_d       = 1'b0;
                                irq_hw_set_o[I_MEAS_DONE] = 1'b1;
                                state_d                   = ST_COMPLETE;
                            end
                        end
                    end else if (timer_expire_i) begin
                        hw_error_set_o[E_SENSOR_FRAME_TIMEOUT] = 1'b1;
                        irq_hw_set_o[I_SENSOR_FRAME_TIMEOUT]   = 1'b1;
                        timer_stop_o                           = 1'b1;
                        busy_d                                 = 1'b0;
                        done_d                                 = 1'b0;
                        aborted_d                              = 1'b0;
                        failed_d                               = 1'b1;
                        phase_valid_d                          = 1'b0;
                        excitation_enable_d                    = 1'b0;
                        state_d                                = ST_SAFE_EXIT;
                    end
                end

                ST_FRAME_NEXT: begin
                    timer_start_o      = 1'b1;
                    timer_load_value_o = active_sensor_ready_timeout_q;
                    state_d            = ST_WAIT_SENSOR_READY;
                end

                ST_PHASE_NEXT: begin
                    phase_index_d = phase_index_q + 3'd1;
                    frame_index_d = 8'd0;
                    state_d       = ST_LOAD_PHASE;
                end

                ST_COMPLETE: begin
                    excitation_enable_d = 1'b0;
                    phase_valid_d       = 1'b0;
                    state_d             = ST_IDLE;
                end

                ST_SAFE_EXIT: begin
                    excitation_enable_d = 1'b0;
                    phase_valid_d       = 1'b0;
                    state_d             = ST_IDLE;
                end

                default: begin
                    state_d = ST_SAFE_EXIT;
                end
            endcase
        end
    end

    always @(posedge hclk_i or negedge hreset_ni) begin
        if (!hreset_ni) begin
            state_q                       <= ST_IDLE;
            busy_q                        <= 1'b0;
            done_q                        <= 1'b0;
            aborted_q                     <= 1'b0;
            failed_q                      <= 1'b0;
            measurement_id_q              <= 16'd0;
            phase_index_q                 <= 3'd0;
            frame_index_q                 <= 8'd0;
            phase_valid_q                 <= 1'b0;
            excitation_enable_q           <= 1'b0;
            sensor_trigger_q              <= 1'b0;
            frame_tag_valid_q             <= 1'b0;
            frame_type_q                  <= 1'b0;
            active_phase_count_q          <= 4'd0;
            active_sensor_ready_timeout_q <= 32'd0;
            active_frame_timeout_q        <= 32'd0;
            active_exc_ready_timeout_q    <= 32'd0;
            active_phase_cfg_flat_q       <= 256'd0;
            active_phase_settle_flat_q    <= 256'd0;
        end else begin
            state_q              <= state_d;
            busy_q               <= busy_d;
            done_q               <= done_d;
            aborted_q            <= aborted_d;
            failed_q             <= failed_d;
            measurement_id_q     <= measurement_id_d;
            phase_index_q        <= phase_index_d;
            frame_index_q        <= frame_index_d;
            phase_valid_q        <= phase_valid_d;
            excitation_enable_q  <= excitation_enable_d;
            sensor_trigger_q     <= sensor_trigger_d;
            frame_tag_valid_q    <= frame_tag_valid_d;
            frame_type_q         <= frame_type_d;

            if (snapshot_take) begin
                active_phase_count_q          <= prog_phase_count_i;
                active_sensor_ready_timeout_q <= prog_sensor_ready_timeout_i;
                active_frame_timeout_q        <= prog_frame_timeout_i;
                active_exc_ready_timeout_q    <= prog_exc_ready_timeout_i;
                active_phase_cfg_flat_q       <= prog_phase_cfg_flat_i;
                active_phase_settle_flat_q    <= prog_phase_settle_flat_i;
            end
        end
    end

endmodule
