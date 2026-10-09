`include "bsg_defines.sv"

module bsg_round_robin_n_to_1 #(
    parameter width_p     = 0,
    parameter num_in_p    = 1,
    parameter strict_p    = 0,
    parameter use_scan_p  = 1,
    parameter tag_width_lp = `BSG_SAFE_CLOG2(num_in_p)
) (
    input  logic                      clk_i,
    input  logic                      reset_i,

    input  logic [num_in_p-1:0][width_p-1:0] data_i,
    input  logic [num_in_p-1:0]              v_i,
    output logic [num_in_p-1:0]              yumi_o,

    output logic                      v_o,
    output logic [width_p-1:0]        data_o,
    output logic [tag_width_lp-1:0]   tag_o,
    input  logic                      yumi_i
);

    if (num_in_p == 1) begin : single_in
        assign v_o      = v_i[0];
        assign data_o   = data_i[0];
        assign tag_o    = '0;
        assign yumi_o[0] = yumi_i;
    end else begin : multi_in
        logic [tag_width_lp-1:0] ptr_r;

        always_comb begin
            v_o    = 1'b0;
            tag_o  = ptr_r;
            data_o = data_i[ptr_r];
            yumi_o = '0;

            for (int i = 0; i < num_in_p; i++) begin
                logic [tag_width_lp-1:0] idx;
                idx = (ptr_r + i) % num_in_p;
                if (v_i[idx]) begin
                    v_o    = 1'b1;
                    tag_o  = idx;
                    data_o = data_i[idx];
                    yumi_o[idx] = yumi_i;
                    break;
                end
            end
        end

        always_ff @(posedge clk_i) begin
            if (reset_i) begin
                ptr_r <= '0;
            end else if (yumi_i && v_o) begin
                ptr_r <= (tag_o + 1'b1) % num_in_p;
            end
        end
    end

endmodule