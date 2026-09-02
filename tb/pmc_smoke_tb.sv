`timescale 1ns/1ps
`default_nettype none

module pmc_smoke_tb;
    logic        pclk;
    logic        preset_n;
    logic [11:0] paddr;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    logic sensor_ready;
    logic sensor_frame_done_toggle;
    logic sensor_error;
    logic excitation_ready;
    logic excitation_fault;

    logic excitation_enable;
    logic sensor_trigger;
    logic frame_tag_valid;
    logic [1:0] frame_type;
    logic [31:0] measurement_id;
    logic [2:0] phase_index;
    logic [7:0] frame_index;
    logic irq;

    integer trigger_count;
    integer excitation_start_count;
    integer excitation_countdown;
    integer watchdog;

    photonic_ctrl_top dut (
        .pclk_i(pclk),
        .preset_ni(preset_n),
        .paddr_i(paddr),
        .psel_i(psel),
        .penable_i(penable),
        .pwrite_i(pwrite),
        .pwdata_i(pwdata),
        .prdata_o(prdata),
        .pready_o(pready),
        .pslverr_o(pslverr),
        .sensor_ready_async_i(sensor_ready),
        .sensor_frame_done_toggle_async_i(sensor_frame_done_toggle),
        .sensor_error_async_i(sensor_error),
        .excitation_ready_async_i(excitation_ready),
        .excitation_fault_async_i(excitation_fault),
        .excitation_enable_o(excitation_enable),
        .sensor_trigger_o(sensor_trigger),
        .frame_tag_valid_o(frame_tag_valid),
        .frame_type_o(frame_type),
        .measurement_id_o(measurement_id),
        .phase_index_o(phase_index),
        .frame_index_o(frame_index),
        .irq_o(irq)
    );

    initial pclk = 1'b0;
    always #5 pclk = ~pclk;

    task automatic apb_write(input [11:0] addr, input [31:0] data);
        begin
            @(negedge pclk);
            paddr   = addr;
            pwdata  = data;
            pwrite  = 1'b1;
            psel    = 1'b1;
            penable = 1'b0;
            @(negedge pclk);
            penable = 1'b1;
            @(posedge pclk);
            if (!pready || pslverr) begin
                $fatal(1, "APB write failed at %03h", addr);
            end
            @(negedge pclk);
            psel    = 1'b0;
            penable = 1'b0;
            pwrite  = 1'b0;
            paddr   = 12'd0;
            pwdata  = 32'd0;
        end
    endtask

    task automatic apb_read(input [11:0] addr, output [31:0] data);
        begin
            @(negedge pclk);
            paddr   = addr;
            pwrite  = 1'b0;
            psel    = 1'b1;
            penable = 1'b0;
            @(negedge pclk);
            penable = 1'b1;
            @(posedge pclk);
            if (!pready || pslverr) begin
                $fatal(1, "APB read failed at %03h", addr);
            end
            data = prdata;
            @(negedge pclk);
            psel    = 1'b0;
            penable = 1'b0;
            paddr   = 12'd0;
        end
    endtask

    // Model excitation READY as a level that drops when disabled and rises
    // after a fresh enable qualification. This checks SIGNAL->SIGNAL re-arm.
    always @(posedge pclk or negedge preset_n) begin
        if (!preset_n) begin
            excitation_ready      <= 1'b0;
            excitation_countdown  <= 0;
        end else begin
            if (excitation_enable) begin
                if (!excitation_ready) begin
                    if (excitation_countdown >= 2) begin
                        excitation_ready <= 1'b1;
                    end else begin
                        excitation_countdown <= excitation_countdown + 1;
                    end
                end
            end else begin
                excitation_ready     <= 1'b0;
                excitation_countdown <= 0;
            end
        end
    end

    always @(posedge excitation_enable) begin
        excitation_start_count = excitation_start_count + 1;
    end

    // Frame completion is an asynchronous toggle event. The 37 ns delay is
    // intentionally not aligned to the 10 ns PMC clock period.
    always @(posedge sensor_trigger) begin
        trigger_count = trigger_count + 1;
        #37 sensor_frame_done_toggle = ~sensor_frame_done_toggle;
    end

    initial begin
        logic [31:0] status;
        logic [31:0] err;
        logic [31:0] ints;
        logic [31:0] dev;
        logic [31:0] version;

        preset_n                 = 1'b0;
        paddr                    = 12'd0;
        psel                     = 1'b0;
        penable                  = 1'b0;
        pwrite                   = 1'b0;
        pwdata                   = 32'd0;
        sensor_ready             = 1'b1;
        sensor_frame_done_toggle = 1'b0;
        sensor_error             = 1'b0;
        excitation_ready         = 1'b0;
        excitation_fault         = 1'b0;
        trigger_count            = 0;
        excitation_start_count   = 0;
        watchdog                 = 0;

        repeat (5) @(posedge pclk);
        preset_n = 1'b1;
        repeat (5) @(posedge pclk);

        // DARK(1 frame) -> SIGNAL(1 frame) -> SIGNAL(1 frame)
        apb_write(12'h008, 32'd3);
        apb_write(12'h00C, 32'd20);
        apb_write(12'h010, 32'd40);
        apb_write(12'h014, 32'd20);
        apb_write(12'h018, 32'd2);
        apb_write(12'h040, 32'h0000_0100);
        apb_write(12'h044, 32'd2);
        apb_write(12'h048, 32'h0000_0101);
        apb_write(12'h04C, 32'd3);
        apb_write(12'h050, 32'h0000_0101);
        apb_write(12'h054, 32'd2);

        // Enable, then issue START through the separate COMMAND register.
        apb_write(12'h030, 32'h0000_0001);
        apb_write(12'h000, 32'h0000_0001);
        apb_write(12'h038, 32'h0000_0001);

        while (!irq && watchdog < 1500) begin
            @(posedge pclk);
            watchdog = watchdog + 1;
        end
        if (!irq) begin
            $fatal(1, "Timeout waiting for PMC completion IRQ");
        end

        apb_read(12'h004, status);
        apb_read(12'h028, err);
        apb_read(12'h02C, ints);
        apb_read(12'h03C, dev);
        apb_read(12'h034, version);

        if (status[0] !== 1'b0 || status[1] !== 1'b1 || status[2] !== 1'b0 || status[3] !== 1'b0) begin
            $fatal(1, "Unexpected STATUS=%08h", status);
        end
        if (err[7:0] != 8'd0) begin
            $fatal(1, "Unexpected ERROR_STATUS=%08h", err);
        end
        if (ints[0] !== 1'b1) begin
            $fatal(1, "MEAS_DONE interrupt missing: INT_STATUS=%08h", ints);
        end
        if (trigger_count != 3) begin
            $fatal(1, "Expected 3 triggers, observed %0d", trigger_count);
        end
        if (excitation_start_count != 2) begin
            $fatal(1, "Expected two fresh SIGNAL excitation enables, observed %0d", excitation_start_count);
        end
        if (excitation_enable !== 1'b0) begin
            $fatal(1, "Excitation not in fault-safe off state after completion");
        end
        if (measurement_id != 32'd1) begin
            $fatal(1, "Expected measurement_id=1, observed %0d", measurement_id);
        end
        if (dev[0] !== 1'b1 || dev[1] !== 1'b0 || dev[3] !== 1'b0) begin
            $fatal(1, "Unexpected DEVICE_STATUS=%08h", dev);
        end
        if (version != 32'h0002_0100) begin
            $fatal(1, "Unexpected VERSION=%08h", version);
        end

        $display("PMC V2.1 SMOKE PASS: toggle CDC, COMMAND CSR and SIGNAL re-arm verified.");
        $finish;
    end
endmodule

`default_nettype wire
