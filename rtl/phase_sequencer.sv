`default_nettype none

module phase_sequencer #(
    parameter integer PHASES = 8
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,

    input  logic                    enable_i,
    input  logic                    start_req_i,
    input  logic                    abort_req_i,
    input  logic [3:0]              prog_phase_count_i,
    input  logic [31:0]             prog_sensor_ready_timeout_i,
    input  logic [31:0]             prog_frame_timeout_i,
    input  logic [31:0]             prog_excitation_ready_timeout_i,
    input  logic [15:0]             prog_trigger_width_i,
    input  logic [PHASES*32-1:0]    prog_phase_cfg_flat_i,
    input  logic [PHASES*32-1:0]    prog_phase_time_flat_i,

    input  logic                    sensor_ready_i,
    input  logic                    sensor_frame_done_event_i,
    input  logic                    sensor_error_i,
    input  logic                    excitation_ready_i,
    input  logic                    excitation_fault_i,

    output logic                    timer_start_o,
    output logic                    timer_stop_o,
    output logic [31:0]             timer_load_o,
    input  logic                    timer_done_i,

    output logic                    trigger_start_o,
    output logic                    trigger_stop_o,
    output logic [15:0]             trigger_width_o,
    input  logic                    trigger_done_i,
    input  logic                    trigger_pulse_i,

    output logic                    excitation_enable_o,
    output logic                    sensor_trigger_o,
    output logic                    frame_tag_valid_o,
    output logic [1:0]              frame_type_o,
    output logic [31:0]             measurement_id_o,
    output logic [2:0]              phase_index_o,
    output logic [7:0]              frame_index_o,

    output logic                    busy_o,
    output logic                    done_o,
    output logic                    aborted_o,
    output logic                    failed_o,
    output logic [7:0]              error_set_o,
    output logic [9:0]              int_set_o
);
    localparam logic [1:0] PHASE_DARK   = 2'b00;
    localparam logic [1:0] PHASE_SIGNAL = 2'b01;
    localparam logic [1:0] PHASE_WAIT   = 2'b10;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_LOAD_PHASE,
        ST_WAIT_EXC_NOT_READY,
        ST_WAIT_EXC_READY,
        ST_SETTLE,
        ST_WAIT_SENSOR_READY,
        ST_TRIGGER,
        ST_WAIT_FRAME,
        ST_WAIT_ONLY,
        ST_PHASE_ADVANCE,
        ST_SAFE_EXIT
    } state_t;

    state_t state_q, state_d;

    logic                    busy_q, busy_d;
    logic                    done_q, done_d;
    logic                    aborted_q, aborted_d;
    logic                    failed_q, failed_d;
    logic [31:0]             measurement_id_q, measurement_id_d;
    logic [2:0]              phase_index_q, phase_index_d;
    logic [7:0]              frame_index_q, frame_index_d;
    logic                    excitation_enable_q, excitation_enable_d;

    logic [3:0]              active_phase_count_q, active_phase_count_d;
    logic [31:0]             active_sensor_ready_timeout_q, active_sensor_ready_timeout_d;
    logic [31:0]             active_frame_timeout_q, active_frame_timeout_d;
    logic [31:0]             active_excitation_ready_timeout_q, active_excitation_ready_timeout_d;
    logic [15:0]             active_trigger_width_q, active_trigger_width_d;
    logic [PHASES*32-1:0]    active_phase_cfg_flat_q, active_phase_cfg_flat_d;
    logic [PHASES*32-1:0]    active_phase_time_flat_q, active_phase_time_flat_d;

    logic [31:0] current_phase_cfg;
    logic [31:0] current_phase_time;
    logic [1:0]  current_phase_type;
    logic [7:0]  current_frame_count;

    logic config_valid;
    logic has_capture_phase;
    logic has_signal_phase;
    logic start_accept;
    logic start_config_error;
    logic cmd_reject;
    logic hard_fault;
    logic more_frames;
    logic more_phases;

    integer i;

    function automatic logic [31:0] get_phase_word(
        input logic [PHASES*32-1:0] flat,
        input logic [2:0] idx
    );
        get_phase_word = flat[idx*32 +: 32];
    endfunction

    assign current_phase_cfg   = get_phase_word(active_phase_cfg_flat_q, phase_index_q);
    assign current_phase_time  = get_phase_word(active_phase_time_flat_q, phase_index_q);
    assign current_phase_type  = current_phase_cfg[1:0];
    assign current_frame_count = current_phase_cfg[15:8];

    always_comb begin
        config_valid      = 1'b1;
        has_capture_phase = 1'b0;
        has_signal_phase  = 1'b0;

        if ((prog_phase_count_i == 4'd0) || (prog_phase_count_i > PHASES)) begin
            config_valid = 1'b0;
        end

        for (i = 0; i < PHASES; i = i + 1) begin
            if (i < prog_phase_count_i) begin
                case (prog_phase_cfg_flat_i[i*32 +: 2])
                    PHASE_DARK: begin
                        has_capture_phase = 1'b1;
                        if (prog_phase_cfg_flat_i[i*32+8 +: 8] == 8'd0) begin
                            config_valid = 1'b0;
                        end
                    end
                    PHASE_SIGNAL: begin
                        has_capture_phase = 1'b1;
                        has_signal_phase  = 1'b1;
                        if (prog_phase_cfg_flat_i[i*32+8 +: 8] == 8'd0) begin
                            config_valid = 1'b0;
                        end
                    end
                    PHASE_WAIT: begin
                        if (prog_phase_cfg_flat_i[i*32+8 +: 8] != 8'd0) begin
                            config_valid = 1'b0;
                        end
                    end
                    default: config_valid = 1'b0;
                endcase
            end
        end

        if (!has_capture_phase) begin
            config_valid = 1'b0;
        end
        if (has_capture_phase && (prog_trigger_width_i == 16'd0)) begin
            config_valid = 1'b0;
        end
        if (has_capture_phase && (prog_sensor_ready_timeout_i == 32'd0)) begin
            config_valid = 1'b0;
        end
        if (has_capture_phase && (prog_frame_timeout_i == 32'd0)) begin
            config_valid = 1'b0;
        end
        if (has_signal_phase && (prog_excitation_ready_timeout_i == 32'd0)) begin
            config_valid = 1'b0;
        end
    end

    assign hard_fault         = sensor_error_i || excitation_fault_i;
    assign start_accept       = start_req_i && !abort_req_i && !busy_q &&
                                (state_q == ST_IDLE) && enable_i &&
                                !hard_fault && config_valid;
    assign start_config_error = start_req_i && !abort_req_i && !busy_q &&
                                (state_q == ST_IDLE) && enable_i &&
                                !hard_fault && !config_valid;
    assign cmd_reject         = (start_req_i && !start_accept && !start_config_error) ||
                                (abort_req_i && !busy_q);

    assign more_frames = ({1'b0, frame_index_q} + 9'd1) < {1'b0, current_frame_count};
    assign more_phases = ({1'b0, phase_index_q} + 4'd1) < active_phase_count_q;

    always_comb begin
        state_d                           = state_q;
        busy_d                            = busy_q;
        done_d                            = done_q;
        aborted_d                         = aborted_q;
        failed_d                          = failed_q;
        measurement_id_d                  = measurement_id_q;
        phase_index_d                     = phase_index_q;
        frame_index_d                     = frame_index_q;
        excitation_enable_d               = excitation_enable_q;
        active_phase_count_d              = active_phase_count_q;
        active_sensor_ready_timeout_d     = active_sensor_ready_timeout_q;
        active_frame_timeout_d            = active_frame_timeout_q;
        active_excitation_ready_timeout_d = active_excitation_ready_timeout_q;
        active_trigger_width_d            = active_trigger_width_q;
        active_phase_cfg_flat_d           = active_phase_cfg_flat_q;
        active_phase_time_flat_d          = active_phase_time_flat_q;

        timer_start_o   = 1'b0;
        timer_stop_o    = 1'b0;
        timer_load_o    = 32'd0;
        trigger_start_o = 1'b0;
        trigger_stop_o  = 1'b0;
        trigger_width_o = active_trigger_width_q;
        error_set_o     = 8'd0;
        int_set_o       = 10'd0;

        if (start_config_error) begin
            error_set_o[0] = 1'b1;
            int_set_o[2]   = 1'b1;
        end
        if (cmd_reject) begin
            error_set_o[1] = 1'b1;
            int_set_o[3]   = 1'b1;
        end

        if (busy_q && hard_fault) begin
            busy_d              = 1'b0;
            done_d              = 1'b0;
            aborted_d           = 1'b0;
            failed_d            = 1'b1;
            excitation_enable_d = 1'b0;
            timer_stop_o        = 1'b1;
            trigger_stop_o      = 1'b1;
            state_d             = ST_SAFE_EXIT;
            if (sensor_error_i) begin
                error_set_o[4] = 1'b1;
                int_set_o[6]   = 1'b1;
            end
            if (excitation_fault_i) begin
                error_set_o[6] = 1'b1;
                int_set_o[8]   = 1'b1;
            end
        end else if (busy_q && (abort_req_i || !enable_i)) begin
            busy_d              = 1'b0;
            done_d              = 1'b0;
            aborted_d           = 1'b1;
            failed_d            = 1'b0;
            excitation_enable_d = 1'b0;
            timer_stop_o        = 1'b1;
            trigger_stop_o      = 1'b1;
            int_set_o[1]        = 1'b1;
            state_d             = ST_SAFE_EXIT;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    excitation_enable_d = 1'b0;
                    if (start_accept) begin
                        busy_d                            = 1'b1;
                        done_d                            = 1'b0;
                        aborted_d                         = 1'b0;
                        failed_d                          = 1'b0;
                        measurement_id_d                  = measurement_id_q + 32'd1;
                        phase_index_d                     = 3'd0;
                        frame_index_d                     = 8'd0;
                        active_phase_count_d              = prog_phase_count_i;
                        active_sensor_ready_timeout_d     = prog_sensor_ready_timeout_i;
                        active_frame_timeout_d            = prog_frame_timeout_i;
                        active_excitation_ready_timeout_d = prog_excitation_ready_timeout_i;
                        active_trigger_width_d            = prog_trigger_width_i;
                        active_phase_cfg_flat_d           = prog_phase_cfg_flat_i;
                        active_phase_time_flat_d          = prog_phase_time_flat_i;
                        state_d                           = ST_LOAD_PHASE;
                    end
                end

                ST_LOAD_PHASE: begin
                    frame_index_d = 8'd0;
                    case (current_phase_type)
                        PHASE_DARK: begin
                            excitation_enable_d = 1'b0;
                            if (current_phase_time == 32'd0) begin
                                timer_start_o = 1'b1;
                                timer_load_o  = active_sensor_ready_timeout_q;
                                state_d       = ST_WAIT_SENSOR_READY;
                            end else begin
                                timer_start_o = 1'b1;
                                timer_load_o  = current_phase_time;
                                state_d       = ST_SETTLE;
                            end
                        end

                        PHASE_SIGNAL: begin
                            // Re-arm every SIGNAL phase: first prove READY has returned low,
                            // then assert enable and wait for a fresh READY-high qualification.
                            excitation_enable_d = 1'b0;
                            timer_start_o        = 1'b1;
                            timer_load_o         = active_excitation_ready_timeout_q;
                            state_d              = ST_WAIT_EXC_NOT_READY;
                        end

                        PHASE_WAIT: begin
                            excitation_enable_d = 1'b0;
                            if (current_phase_time == 32'd0) begin
                                state_d = ST_PHASE_ADVANCE;
                            end else begin
                                timer_start_o = 1'b1;
                                timer_load_o  = current_phase_time;
                                state_d       = ST_WAIT_ONLY;
                            end
                        end

                        default: begin
                            busy_d              = 1'b0;
                            failed_d            = 1'b1;
                            excitation_enable_d = 1'b0;
                            error_set_o[7]      = 1'b1;
                            int_set_o[9]        = 1'b1;
                            state_d             = ST_SAFE_EXIT;
                        end
                    endcase
                end

                ST_WAIT_EXC_NOT_READY: begin
                    if (!excitation_ready_i) begin
                        excitation_enable_d = 1'b1;
                        timer_start_o        = 1'b1;
                        timer_load_o         = active_excitation_ready_timeout_q;
                        state_d              = ST_WAIT_EXC_READY;
                    end else if (timer_done_i) begin
                        busy_d              = 1'b0;
                        failed_d            = 1'b1;
                        excitation_enable_d = 1'b0;
                        error_set_o[5]      = 1'b1;
                        int_set_o[7]        = 1'b1;
                        state_d             = ST_SAFE_EXIT;
                    end
                end

                ST_WAIT_EXC_READY: begin
                    if (excitation_ready_i) begin
                        if (current_phase_time == 32'd0) begin
                            timer_start_o = 1'b1;
                            timer_load_o  = active_sensor_ready_timeout_q;
                            state_d       = ST_WAIT_SENSOR_READY;
                        end else begin
                            timer_start_o = 1'b1;
                            timer_load_o  = current_phase_time;
                            state_d       = ST_SETTLE;
                        end
                    end else if (timer_done_i) begin
                        busy_d              = 1'b0;
                        failed_d            = 1'b1;
                        excitation_enable_d = 1'b0;
                        error_set_o[5]      = 1'b1;
                        int_set_o[7]        = 1'b1;
                        state_d             = ST_SAFE_EXIT;
                    end
                end

                ST_SETTLE: begin
                    if (timer_done_i) begin
                        timer_start_o = 1'b1;
                        timer_load_o  = active_sensor_ready_timeout_q;
                        state_d       = ST_WAIT_SENSOR_READY;
                    end
                end

                ST_WAIT_SENSOR_READY: begin
                    if (sensor_ready_i) begin
                        timer_stop_o    = 1'b1;
                        trigger_start_o = 1'b1;
                        state_d         = ST_TRIGGER;
                    end else if (timer_done_i) begin
                        busy_d              = 1'b0;
                        failed_d            = 1'b1;
                        excitation_enable_d = 1'b0;
                        error_set_o[2]      = 1'b1;
                        int_set_o[4]        = 1'b1;
                        state_d             = ST_SAFE_EXIT;
                    end
                end

                ST_TRIGGER: begin
                    if (trigger_done_i) begin
                        timer_start_o = 1'b1;
                        timer_load_o  = active_frame_timeout_q;
                        state_d       = ST_WAIT_FRAME;
                    end
                end

                ST_WAIT_FRAME: begin
                    if (sensor_frame_done_event_i) begin
                        timer_stop_o = 1'b1;
                        if (more_frames) begin
                            frame_index_d = frame_index_q + 8'd1;
                            timer_start_o = 1'b1;
                            timer_load_o  = active_sensor_ready_timeout_q;
                            state_d       = ST_WAIT_SENSOR_READY;
                        end else begin
                            excitation_enable_d = 1'b0;
                            state_d             = ST_PHASE_ADVANCE;
                        end
                    end else if (timer_done_i) begin
                        busy_d              = 1'b0;
                        failed_d            = 1'b1;
                        excitation_enable_d = 1'b0;
                        error_set_o[3]      = 1'b1;
                        int_set_o[5]        = 1'b1;
                        state_d             = ST_SAFE_EXIT;
                    end
                end

                ST_WAIT_ONLY: begin
                    if (timer_done_i) begin
                        state_d = ST_PHASE_ADVANCE;
                    end
                end

                ST_PHASE_ADVANCE: begin
                    excitation_enable_d = 1'b0;
                    if (more_phases) begin
                        phase_index_d = phase_index_q + 3'd1;
                        frame_index_d = 8'd0;
                        state_d       = ST_LOAD_PHASE;
                    end else begin
                        busy_d       = 1'b0;
                        done_d       = 1'b1;
                        aborted_d    = 1'b0;
                        failed_d     = 1'b0;
                        int_set_o[0] = 1'b1;
                        state_d      = ST_IDLE;
                    end
                end

                ST_SAFE_EXIT: begin
                    excitation_enable_d = 1'b0;
                    timer_stop_o        = 1'b1;
                    trigger_stop_o      = 1'b1;
                    state_d             = ST_IDLE;
                end

                default: begin
                    busy_d              = 1'b0;
                    done_d              = 1'b0;
                    aborted_d           = 1'b0;
                    failed_d            = 1'b1;
                    excitation_enable_d = 1'b0;
                    timer_stop_o        = 1'b1;
                    trigger_stop_o      = 1'b1;
                    error_set_o[7]      = 1'b1;
                    int_set_o[9]        = 1'b1;
                    state_d             = ST_SAFE_EXIT;
                end
            endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q                           <= ST_IDLE;
            busy_q                            <= 1'b0;
            done_q                            <= 1'b0;
            aborted_q                         <= 1'b0;
            failed_q                          <= 1'b0;
            measurement_id_q                  <= 32'd0;
            phase_index_q                     <= 3'd0;
            frame_index_q                     <= 8'd0;
            excitation_enable_q               <= 1'b0;
            active_phase_count_q              <= 4'd0;
            active_sensor_ready_timeout_q     <= 32'd0;
            active_frame_timeout_q            <= 32'd0;
            active_excitation_ready_timeout_q <= 32'd0;
            active_trigger_width_q            <= 16'd1;
            active_phase_cfg_flat_q           <= '0;
            active_phase_time_flat_q          <= '0;
        end else begin
            state_q                           <= state_d;
            busy_q                            <= busy_d;
            done_q                            <= done_d;
            aborted_q                         <= aborted_d;
            failed_q                          <= failed_d;
            measurement_id_q                  <= measurement_id_d;
            phase_index_q                     <= phase_index_d;
            frame_index_q                     <= frame_index_d;
            excitation_enable_q               <= excitation_enable_d;
            active_phase_count_q              <= active_phase_count_d;
            active_sensor_ready_timeout_q     <= active_sensor_ready_timeout_d;
            active_frame_timeout_q            <= active_frame_timeout_d;
            active_excitation_ready_timeout_q <= active_excitation_ready_timeout_d;
            active_trigger_width_q            <= active_trigger_width_d;
            active_phase_cfg_flat_q           <= active_phase_cfg_flat_d;
            active_phase_time_flat_q          <= active_phase_time_flat_d;
        end
    end

    assign excitation_enable_o = excitation_enable_q && busy_q && !hard_fault;
    assign sensor_trigger_o     = trigger_pulse_i && busy_q && !hard_fault;
    assign frame_tag_valid_o    = sensor_trigger_o;
    assign frame_type_o         = current_phase_type;
    assign measurement_id_o     = measurement_id_q;
    assign phase_index_o        = phase_index_q;
    assign frame_index_o        = frame_index_q;
    assign busy_o               = busy_q;
    assign done_o               = done_q;
    assign aborted_o            = aborted_q;
    assign failed_o             = failed_q;
endmodule

`default_nettype wire
