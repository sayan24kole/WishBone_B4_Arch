/**
 *  bsg_test_mem_wb4.sv
 *
 *  Pipelined Wishbone B4 Compliant Memory Model for Testbenches.
 *  Supports:
 *    - Pipelined multi-request intake
 *    - Configurable response latency pipeline (latency_p)
 *    - Byte-level write strobing via wb_sel_i
 *    - Byte-to-word address translation
 */

`timescale 1ns / 1ps

module bsg_test_mem_wb4 #(
    parameter addr_width_p    = 32,
    parameter data_width_p    = 32,
    parameter mem_size_p      = 2048, // Number of words in memory
    parameter latency_p       = 2,    // Cycles between request and ACK
    parameter sel_width_lp    = data_width_p / 8,
    parameter byte_offset_lp  = $clog2(sel_width_lp)
) (
    input  logic                     clk_i,
    input  logic                     reset_i,

    // Wishbone B4 Slave Interface
    input  logic [addr_width_p-1:0]  wb_adr_i,
    input  logic [data_width_p-1:0]  wb_dat_i,
    output logic [data_width_p-1:0]  wb_dat_o,
    input  logic [sel_width_lp-1:0]  wb_sel_i,
    input  logic                     wb_we_i,
    input  logic                     wb_cyc_i,
    input  logic                     wb_stb_i,
    output logic                     wb_stall_o,
    output logic                     wb_ack_o,
    output logic                     wb_err_o
);

    assign wb_err_o = 1'b0; // No bus errors in basic model

    // Internal Memory Array (Word-addressed)
    logic [data_width_p-1:0] mem [0:mem_size_p-1];

    // Convert byte-level Wishbone address to internal word index
    wire [$clog2(mem_size_p)-1:0] word_idx = wb_adr_i[byte_offset_lp +: $clog2(mem_size_p)];

    // Response pipeline tracking structure
    typedef struct packed {
        logic                    valid;
        logic                    we;
        logic [data_width_p-1:0] rdata;
    } resp_pipe_s;

    resp_pipe_s pipe [0:latency_p];

    // Request handshake
    wire req_fire = wb_cyc_i & wb_stb_i & ~wb_stall_o;

    // Ideal zero-stall slave (can be driven to 1'b1 to inject test stalls)
    assign wb_stall_o = 1'b0;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            for (int i = 0; i <= latency_p; i++) begin
                pipe[i].valid <= 1'b0;
                pipe[i].we    <= 1'b0;
                pipe[i].rdata <= '0;
            end
        end else begin
            // Shift pipeline stages forward
            for (int i = latency_p; i > 0; i--) begin
                pipe[i] <= pipe[i-1];
            end

            // Stage 0: Process incoming request
            if (req_fire) begin
                pipe[0].valid <= 1'b1;
                pipe[0].we    <= wb_we_i;

                if (wb_we_i) begin
                    // Byte-masked write
                    for (int b = 0; b < sel_width_lp; b++) begin
                        if (wb_sel_i[b]) begin
                            mem[word_idx][b*8 +: 8] <= wb_dat_i[b*8 +: 8];
                        end
                    end
                    pipe[0].rdata <= '0;
                end else begin
                    // Memory Read
                    pipe[0].rdata <= mem[word_idx];
                end
            end else begin
                pipe[0].valid <= 1'b0;
                pipe[0].we    <= 1'b0;
                pipe[0].rdata <= '0;
            end
        end
    end

    // Drive ACK and Read Data when pipeline stage completes
    assign wb_ack_o = wb_cyc_i & pipe[latency_p].valid;
    assign wb_dat_o = pipe[latency_p].rdata;

endmodule