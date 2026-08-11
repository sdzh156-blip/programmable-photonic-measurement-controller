`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// photonic_ctrl_top.v
// Top-level integration for the Programmable Photonic Measurement Controller.
// -----------------------------------------------------------------------------
module photonic_ctrl_top (
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
    output wire [31:0] hrdata_o,
    output wire        hreadyout_o,
    output wire        hresp_o,

    input  wire        sensor_ready_i,
    input  wire        sensor_frame_done_i,
    input  wire        sensor_error_i,
    output wire        sensor_trigger_o,
    output wire        frame_tag_valid_o,
    output wire        frame_type_o,
    output wire [2:0]  phase_index_o,
    output wire [7:0]  frame_index_o,
    output wire [15:0] measurement_id_o,

    output wire        excitation_enable_o,
    input  wire        excitation_ready_i,
    input  wire        excitation_fault_i,

    output wire        irq_o
);

    wire [11:0] csr_addr;
    wire        csr_write;
    wire        csr_read;
    wire [31:0] csr_wdata;
    wire [31:0] csr_rdata;
    wire        csr_addr_valid;

    wire        start_req;
    wire        abort_req;
    wire        enable;
    wire [3:0]  phase_count;
    wire [31:0] sensor_ready_timeout;
    wire [31:0] frame_timeout;
    wire [31:0] exc_ready_timeout;
    wire [255:0] phase_cfg_flat;
    wire [255:0] phase_settle_flat;

    wire busy;
    wire done;
    wire aborted;
    wire failed;
    wire [1:0] current_phase_type;
    wire       current_phase_valid;

    wire timer_start;
    wire timer_stop;
    wire [31:0] timer_load_value;
    wire timer_running;
    wire timer_expire;

    wire [7:0] hw_error_set;
    wire [7:0] error_status;
    wire [9:0] irq_hw_set;
    wire [9:0] int_status;
    wire [9:0] int_enable;
    wire [9:0] int_sw_clear;
    wire       int_enable_we;
    wire [9:0] int_enable_wdata;

    ahb_lite_slave u_ahb_lite_slave (
        .hclk_i             (hclk_i),
        .hreset_ni          (hreset_ni),
        .hsel_i             (hsel_i),
        .haddr_i            (haddr_i),
        .htrans_i           (htrans_i),
        .hwrite_i           (hwrite_i),
        .hsize_i            (hsize_i),
        .hburst_i           (hburst_i),
        .hprot_i            (hprot_i),
        .hmastlock_i        (hmastlock_i),
        .hwdata_i           (hwdata_i),
        .hready_i           (hready_i),
        .hrdata_o           (hrdata_o),
        .hreadyout_o        (hreadyout_o),
        .hresp_o            (hresp_o),
        .csr_addr_o         (csr_addr),
        .csr_write_o        (csr_write),
        .csr_read_o         (csr_read),
        .csr_wdata_o        (csr_wdata),
        .csr_rdata_i        (csr_rdata),
        .csr_addr_valid_i   (csr_addr_valid)
    );

    photonic_csr u_photonic_csr (
        .hclk_i                     (hclk_i),
        .hreset_ni                  (hreset_ni),
        .csr_addr_i                 (csr_addr),
        .csr_write_i                (csr_write),
        .csr_read_i                 (csr_read),
        .csr_wdata_i                (csr_wdata),
        .csr_rdata_o                (csr_rdata),
        .csr_addr_valid_o           (csr_addr_valid),
        .start_req_o                (start_req),
        .abort_req_o                (abort_req),
        .enable_o                   (enable),
        .phase_count_o              (phase_count),
        .sensor_ready_timeout_o     (sensor_ready_timeout),
        .frame_timeout_o            (frame_timeout),
        .exc_ready_timeout_o        (exc_ready_timeout),
        .phase_cfg_flat_o           (phase_cfg_flat),
        .phase_settle_flat_o        (phase_settle_flat),
        .busy_i                     (busy),
        .done_i                     (done),
        .aborted_i                  (aborted),
        .failed_i                   (failed),
        .measurement_id_i           (measurement_id_o),
        .current_phase_index_i      (phase_index_o),
        .current_phase_type_i       (current_phase_type),
        .current_frame_index_i      (frame_index_o),
        .current_phase_valid_i      (current_phase_valid),
        .hw_error_set_i             (hw_error_set),
        .error_status_o             (error_status),
        .int_status_i               (int_status),
        .int_enable_i               (int_enable),
        .int_status_sw_clear_o      (int_sw_clear),
        .int_enable_we_o            (int_enable_we),
        .int_enable_wdata_o         (int_enable_wdata)
    );

    timing_engine u_timing_engine (
        .hclk_i          (hclk_i),
        .hreset_ni       (hreset_ni),
        .start_i         (timer_start),
        .stop_i          (timer_stop),
        .load_value_i    (timer_load_value),
        .running_o       (timer_running),
        .expire_o        (timer_expire)
    );

    measurement_ctrl u_measurement_ctrl (
        .hclk_i                         (hclk_i),
        .hreset_ni                      (hreset_ni),
        .start_req_i                    (start_req),
        .abort_req_i                    (abort_req),
        .enable_i                       (enable),
        .prog_phase_count_i             (phase_count),
        .prog_sensor_ready_timeout_i    (sensor_ready_timeout),
        .prog_frame_timeout_i           (frame_timeout),
        .prog_exc_ready_timeout_i       (exc_ready_timeout),
        .prog_phase_cfg_flat_i          (phase_cfg_flat),
        .prog_phase_settle_flat_i       (phase_settle_flat),
        .sensor_ready_i                 (sensor_ready_i),
        .sensor_frame_done_i            (sensor_frame_done_i),
        .sensor_error_i                 (sensor_error_i),
        .excitation_ready_i             (excitation_ready_i),
        .excitation_fault_i             (excitation_fault_i),
        .timer_start_o                   (timer_start),
        .timer_stop_o                    (timer_stop),
        .timer_load_value_o              (timer_load_value),
        .timer_running_i                 (timer_running),
        .timer_expire_i                  (timer_expire),
        .busy_o                          (busy),
        .done_o                          (done),
        .aborted_o                       (aborted),
        .failed_o                        (failed),
        .measurement_id_o               (measurement_id_o),
        .current_phase_index_o          (phase_index_o),
        .current_phase_type_o           (current_phase_type),
        .current_frame_index_o          (frame_index_o),
        .current_phase_valid_o          (current_phase_valid),
        .sensor_trigger_o               (sensor_trigger_o),
        .frame_tag_valid_o              (frame_tag_valid_o),
        .frame_type_o                   (frame_type_o),
        .excitation_enable_o            (excitation_enable_o),
        .hw_error_set_o                 (hw_error_set),
        .irq_hw_set_o                   (irq_hw_set)
    );

    irq_ctrl u_irq_ctrl (
        .hclk_i             (hclk_i),
        .hreset_ni          (hreset_ni),
        .hw_set_i           (irq_hw_set),
        .sw_clear_i         (int_sw_clear),
        .int_enable_we_i    (int_enable_we),
        .int_enable_wdata_i (int_enable_wdata),
        .int_status_o       (int_status),
        .int_enable_o       (int_enable),
        .irq_o              (irq_o)
    );

endmodule
