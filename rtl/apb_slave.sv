`default_nettype none

module apb_slave #(
    parameter integer ADDR_WIDTH = 12
) (
    input  logic                  pclk_i,
    input  logic                  preset_ni,
    input  logic [ADDR_WIDTH-1:0] paddr_i,
    input  logic                  psel_i,
    input  logic                  penable_i,
    input  logic                  pwrite_i,
    input  logic [31:0]           pwdata_i,
    output logic [31:0]           prdata_o,
    output logic                  pready_o,
    output logic                  pslverr_o,

    output logic                  csr_wr_en_o,
    output logic                  csr_rd_en_o,
    output logic [ADDR_WIDTH-1:0] csr_addr_o,
    output logic [31:0]           csr_wdata_o,
    input  logic [31:0]           csr_rdata_i,
    input  logic                  csr_error_i
);
    logic access_phase;
    logic aligned_access;
    logic unused_clk_reset;

    assign unused_clk_reset = pclk_i ^ preset_ni;
    assign access_phase      = psel_i && penable_i;
    assign aligned_access    = (paddr_i[1:0] == 2'b00);

    assign csr_wr_en_o = access_phase && aligned_access && pwrite_i;
    assign csr_rd_en_o = access_phase && aligned_access && !pwrite_i;
    assign csr_addr_o  = paddr_i;
    assign csr_wdata_o = pwdata_i;

    assign prdata_o  = (access_phase && aligned_access && !csr_error_i) ? csr_rdata_i : 32'd0;
    assign pready_o  = 1'b1;
    assign pslverr_o = access_phase && (!aligned_access || csr_error_i);
endmodule

`default_nettype wire
