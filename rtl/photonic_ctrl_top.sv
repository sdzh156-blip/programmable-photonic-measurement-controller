`default_nettype none

module photonic_ctrl_top #(
    parameter integer APB_ADDR_WIDTH = 12,
    parameter integer PHASES         = 8
) (
    input  logic                       pclk_i,
    input  logic                       preset_ni,
    input  logic [APB_ADDR_WIDTH-1:0]  paddr_i,
    input  logic                       psel_i,
    input  logic                       penable_i,
    input  logic                       pwrite_i,
    input  logic [31:0]                pwdata_i,
    output logic [31:0]                prdata_o,
    output logic                       pready_o,
    output logic                       pslverr_o,

    input  logic                       sensor_ready_async_i,
    input  logic                       sensor_frame_done_toggle_async_i,
    input  logic                       sensor_error_async_i,
    input  logic                       excitation_ready_async_i,
    input  logic                       excitation_fault_async_i,

    output logic                       excitation_enable_o,
    output logic                       sensor_trigger_o,
    output logic                       frame_tag_valid_o,
    output logic [1:0]                 frame_type_o,
    output logic [31:0]                measurement_id_o,
    output logic [2:0]                 phase_index_o,
    output logic [7:0]                 frame_index_o,
    output logic                       irq_o
);
    logic                      csr_wr_en;
    logic                      csr_rd_en;
    logic [APB_ADDR_WIDTH-1:0] csr_addr;
    logic [31:0]               csr_wdata;
    logic [31:0]               csr_rdata;
    logic                      csr_error;

    logic                      enable;
    logic                      start_req;
    logic                      abort_req;
    logic [3:0]                phase_count;
    logic [31:0]               sensor_ready_timeout;
    logic [31:0]               frame_timeout;
    logic [31:0]               excitation_ready_timeout;
    logic [15:0]               trigger_width;
    logic [PHASES*32-1:0]      phase_cfg_flat;
    logic [PHASES*32-1:0]      phase_time_flat;

    logic                      busy;
    logic                      done;
    logic                      aborted;
    logic                      failed;
    logic [7:0]                error_set;
    logic [7:0]                error_status;
    logic [9:0]                int_set;
    logic [9:0]                int_status;
    logic [9:0]                int_enable;
    logic [9:0]                int_sw_clear;
    logic                      int_enable_we;
    logic [9:0]                int_enable_wdata;

    logic                      sensor_ready_sync;
    logic                      sensor_frame_done_toggle_sync;
    logic                      sensor_frame_done_event;
    logic                      sensor_error_sync;
    logic                      excitation_ready_sync;
    logic                      excitation_fault_sync;

    logic                      timer_start;
    logic                      timer_stop;
    logic [31:0]               timer_load;
    logic                      timer_done;
    logic                      timer_active;
    logic [31:0]               timer_count;

    logic                      trigger_start;
    logic                      trigger_stop;
    logic [15:0]               trigger_width_active;
    logic                      trigger_done;
    logic                      trigger_pulse;
    logic                      trigger_busy;
    logic                      unused_internal;

    apb_slave #(
        .ADDR_WIDTH(APB_ADDR_WIDTH)
    ) u_apb_slave (
        .pclk_i,
        .preset_ni,
        .paddr_i,
        .psel_i,
        .penable_i,
        .pwrite_i,
        .pwdata_i,
        .prdata_o,
        .pready_o,
        .pslverr_o,
        .csr_wr_en_o(csr_wr_en),
        .csr_rd_en_o(csr_rd_en),
        .csr_addr_o(csr_addr),
        .csr_wdata_o(csr_wdata),
        .csr_rdata_i(csr_rdata),
        .csr_error_i(csr_error)
    );

    sync2_level #(.WIDTH(1)) u_sync_sensor_ready (
        .clk_i(pclk_i), .rst_ni(preset_ni), .async_i(sensor_ready_async_i), .sync_o(sensor_ready_sync)
    );
    sync2_toggle_event u_sync_sensor_frame_done_toggle (
        .clk_i(pclk_i),
        .rst_ni(preset_ni),
        .async_toggle_i(sensor_frame_done_toggle_async_i),
        .sync_toggle_o(sensor_frame_done_toggle_sync),
        .event_o(sensor_frame_done_event)
    );
    sync2_level #(.WIDTH(1)) u_sync_sensor_error (
        .clk_i(pclk_i), .rst_ni(preset_ni), .async_i(sensor_error_async_i), .sync_o(sensor_error_sync)
    );
    sync2_level #(.WIDTH(1)) u_sync_excitation_ready (
        .clk_i(pclk_i), .rst_ni(preset_ni), .async_i(excitation_ready_async_i), .sync_o(excitation_ready_sync)
    );
    sync2_level #(.WIDTH(1)) u_sync_excitation_fault (
        .clk_i(pclk_i), .rst_ni(preset_ni), .async_i(excitation_fault_async_i), .sync_o(excitation_fault_sync)
    );

    photonic_csr #(
        .ADDR_WIDTH(APB_ADDR_WIDTH),
        .PHASES(PHASES)
    ) u_photonic_csr (
        .clk_i(pclk_i),
        .rst_ni(preset_ni),
        .csr_wr_en_i(csr_wr_en),
        .csr_rd_en_i(csr_rd_en),
        .csr_addr_i(csr_addr),
        .csr_wdata_i(csr_wdata),
        .csr_rdata_o(csr_rdata),
        .csr_error_o(csr_error),
        .enable_o(enable),
        .start_req_o(start_req),
        .abort_req_o(abort_req),
        .phase_count_o(phase_count),
        .sensor_ready_timeout_o(sensor_ready_timeout),
        .frame_timeout_o(frame_timeout),
        .excitation_ready_timeout_o(excitation_ready_timeout),
        .trigger_width_o(trigger_width),
        .phase_cfg_flat_o(phase_cfg_flat),
        .phase_time_flat_o(phase_time_flat),
        .busy_i(busy),
        .done_i(done),
        .aborted_i(aborted),
        .failed_i(failed),
        .measurement_id_i(measurement_id_o),
        .current_phase_i(phase_index_o),
        .current_frame_i(frame_index_o),
        .sensor_ready_i(sensor_ready_sync),
        .sensor_error_i(sensor_error_sync),
        .excitation_ready_i(excitation_ready_sync),
        .excitation_fault_i(excitation_fault_sync),
        .error_hw_set_i(error_set),
        .error_status_o(error_status),
        .int_status_i(int_status),
        .int_enable_i(int_enable),
        .int_sw_clear_o(int_sw_clear),
        .int_enable_we_o(int_enable_we),
        .int_enable_wdata_o(int_enable_wdata)
    );

    timing_engine u_timing_engine (
        .clk_i(pclk_i),
        .rst_ni(preset_ni),
        .start_i(timer_start),
        .stop_i(timer_stop),
        .load_i(timer_load),
        .active_o(timer_active),
        .done_o(timer_done),
        .count_o(timer_count)
    );

    pulse_engine u_pulse_engine (
        .clk_i(pclk_i),
        .rst_ni(preset_ni),
        .start_i(trigger_start),
        .stop_i(trigger_stop),
        .width_i(trigger_width_active),
        .busy_o(trigger_busy),
        .pulse_o(trigger_pulse),
        .done_o(trigger_done)
    );

    phase_sequencer #(
        .PHASES(PHASES)
    ) u_phase_sequencer (
        .clk_i(pclk_i),
        .rst_ni(preset_ni),
        .enable_i(enable),
        .start_req_i(start_req),
        .abort_req_i(abort_req),
        .prog_phase_count_i(phase_count),
        .prog_sensor_ready_timeout_i(sensor_ready_timeout),
        .prog_frame_timeout_i(frame_timeout),
        .prog_excitation_ready_timeout_i(excitation_ready_timeout),
        .prog_trigger_width_i(trigger_width),
        .prog_phase_cfg_flat_i(phase_cfg_flat),
        .prog_phase_time_flat_i(phase_time_flat),
        .sensor_ready_i(sensor_ready_sync),
        .sensor_frame_done_event_i(sensor_frame_done_event),
        .sensor_error_i(sensor_error_sync),
        .excitation_ready_i(excitation_ready_sync),
        .excitation_fault_i(excitation_fault_sync),
        .timer_start_o(timer_start),
        .timer_stop_o(timer_stop),
        .timer_load_o(timer_load),
        .timer_done_i(timer_done),
        .trigger_start_o(trigger_start),
        .trigger_stop_o(trigger_stop),
        .trigger_width_o(trigger_width_active),
        .trigger_done_i(trigger_done),
        .trigger_pulse_i(trigger_pulse),
        .excitation_enable_o(excitation_enable_o),
        .sensor_trigger_o(sensor_trigger_o),
        .frame_tag_valid_o(frame_tag_valid_o),
        .frame_type_o(frame_type_o),
        .measurement_id_o(measurement_id_o),
        .phase_index_o(phase_index_o),
        .frame_index_o(frame_index_o),
        .busy_o(busy),
        .done_o(done),
        .aborted_o(aborted),
        .failed_o(failed),
        .error_set_o(error_set),
        .int_set_o(int_set)
    );

    irq_ctrl #(.WIDTH(10)) u_irq_ctrl (
        .clk_i(pclk_i),
        .rst_ni(preset_ni),
        .hw_set_i(int_set),
        .sw_clear_i(int_sw_clear),
        .enable_we_i(int_enable_we),
        .enable_wdata_i(int_enable_wdata),
        .status_o(int_status),
        .enable_o(int_enable),
        .irq_o(irq_o)
    );

    assign unused_internal = timer_active ^ timer_count[0] ^ trigger_busy ^
                             error_status[0] ^ sensor_frame_done_toggle_sync;
endmodule

`default_nettype wire
