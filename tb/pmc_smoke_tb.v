`timescale 1ns/1ps

// Simple directed smoke test. This is intentionally not the final UVM environment.
module pmc_smoke_tb;

    reg hclk_i;
    reg hreset_ni;

    reg        hsel_i;
    reg [31:0] haddr_i;
    reg [1:0]  htrans_i;
    reg        hwrite_i;
    reg [2:0]  hsize_i;
    reg [2:0]  hburst_i;
    reg [3:0]  hprot_i;
    reg        hmastlock_i;
    reg [31:0] hwdata_i;
    wire       hready_i;
    wire [31:0] hrdata_o;
    wire       hreadyout_o;
    wire       hresp_o;

    reg sensor_ready_i;
    reg sensor_frame_done_i;
    reg sensor_error_i;
    wire sensor_trigger_o;
    wire frame_tag_valid_o;
    wire frame_type_o;
    wire [2:0] phase_index_o;
    wire [7:0] frame_index_o;
    wire [15:0] measurement_id_o;

    wire excitation_enable_o;
    reg  excitation_ready_i;
    reg  excitation_fault_i;
    wire irq_o;

    integer trigger_count;
    integer timeout_guard;
    reg [31:0] status_value;

    assign hready_i = hreadyout_o;

    photonic_ctrl_top dut (
        .hclk_i(hclk_i),
        .hreset_ni(hreset_ni),
        .hsel_i(hsel_i),
        .haddr_i(haddr_i),
        .htrans_i(htrans_i),
        .hwrite_i(hwrite_i),
        .hsize_i(hsize_i),
        .hburst_i(hburst_i),
        .hprot_i(hprot_i),
        .hmastlock_i(hmastlock_i),
        .hwdata_i(hwdata_i),
        .hready_i(hready_i),
        .hrdata_o(hrdata_o),
        .hreadyout_o(hreadyout_o),
        .hresp_o(hresp_o),
        .sensor_ready_i(sensor_ready_i),
        .sensor_frame_done_i(sensor_frame_done_i),
        .sensor_error_i(sensor_error_i),
        .sensor_trigger_o(sensor_trigger_o),
        .frame_tag_valid_o(frame_tag_valid_o),
        .frame_type_o(frame_type_o),
        .phase_index_o(phase_index_o),
        .frame_index_o(frame_index_o),
        .measurement_id_o(measurement_id_o),
        .excitation_enable_o(excitation_enable_o),
        .excitation_ready_i(excitation_ready_i),
        .excitation_fault_i(excitation_fault_i),
        .irq_o(irq_o)
    );

    always #5 hclk_i = ~hclk_i;

    reg trigger_delay_q;
    always @(posedge hclk_i or negedge hreset_ni) begin
        if (!hreset_ni) begin
            trigger_delay_q     <= 1'b0;
            sensor_frame_done_i <= 1'b0;
            trigger_count       <= 0;
        end else begin
            sensor_frame_done_i <= trigger_delay_q;
            trigger_delay_q     <= sensor_trigger_o;
            if (sensor_trigger_o)
                trigger_count <= trigger_count + 1;
        end
    end

    task ahb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            while (!hreadyout_o) @(posedge hclk_i);
            @(negedge hclk_i);
            hsel_i   = 1'b1;
            haddr_i  = addr;
            htrans_i = 2'b10;
            hwrite_i = 1'b1;
            hsize_i  = 3'b010;
            @(posedge hclk_i);
            @(negedge hclk_i);
            hsel_i   = 1'b0;
            htrans_i = 2'b00;
            hwrite_i = 1'b0;
            hwdata_i = data;
            @(posedge hclk_i);
            @(negedge hclk_i);
            hwdata_i = 32'd0;
        end
    endtask

    task ahb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            while (!hreadyout_o) @(posedge hclk_i);
            @(negedge hclk_i);
            hsel_i   = 1'b1;
            haddr_i  = addr;
            htrans_i = 2'b10;
            hwrite_i = 1'b0;
            hsize_i  = 3'b010;
            @(posedge hclk_i);
            @(negedge hclk_i);
            hsel_i   = 1'b0;
            htrans_i = 2'b00;
            #1 data  = hrdata_o;
            @(posedge hclk_i);
        end
    endtask

    initial begin
        hclk_i = 1'b0;
        hreset_ni = 1'b0;
        hsel_i = 1'b0;
        haddr_i = 32'd0;
        htrans_i = 2'b00;
        hwrite_i = 1'b0;
        hsize_i = 3'b010;
        hburst_i = 3'b000;
        hprot_i = 4'b0011;
        hmastlock_i = 1'b0;
        hwdata_i = 32'd0;
        sensor_ready_i = 1'b1;
        sensor_frame_done_i = 1'b0;
        sensor_error_i = 1'b0;
        excitation_ready_i = 1'b1;
        excitation_fault_i = 1'b0;
        trigger_count = 0;

        repeat (4) @(posedge hclk_i);
        @(negedge hclk_i);
        hreset_ni = 1'b1;

        ahb_write(32'h0000_0008, 32'd2);
        ahb_write(32'h0000_000C, 32'd8);
        ahb_write(32'h0000_0010, 32'd8);
        ahb_write(32'h0000_0014, 32'd8);
        ahb_write(32'h0000_0040, 32'h0000_0100);
        ahb_write(32'h0000_0044, 32'd0);
        ahb_write(32'h0000_0048, 32'h0000_0101);
        ahb_write(32'h0000_004C, 32'd1);
        ahb_write(32'h0000_0028, 32'h0000_0001);
        ahb_write(32'h0000_0000, 32'h0000_0003);

        timeout_guard = 0;
        while (!irq_o && timeout_guard < 100) begin
            @(posedge hclk_i);
            timeout_guard = timeout_guard + 1;
        end

        if (!irq_o) begin
            $display("[FAIL] Smoke test timed out waiting for irq_o");
            $finish;
        end

        ahb_read(32'h0000_0004, status_value);

        if (!status_value[1]) begin
            $display("[FAIL] DONE status was not set: STATUS=0x%08x", status_value);
            $finish;
        end
        if (status_value[0]) begin
            $display("[FAIL] BUSY remained set: STATUS=0x%08x", status_value);
            $finish;
        end
        if (trigger_count != 2) begin
            $display("[FAIL] Expected 2 triggers, observed %0d", trigger_count);
            $finish;
        end
        if (excitation_enable_o !== 1'b0) begin
            $display("[FAIL] Excitation not safe-off at completion");
            $finish;
        end

        $display("[PASS] PMC smoke test completed. triggers=%0d measurement_id=%0d", trigger_count, measurement_id_o);
        $finish;
    end

endmodule
