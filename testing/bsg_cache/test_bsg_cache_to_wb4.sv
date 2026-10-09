/**
 *  test_bsg_cache_to_wb4.sv
 *
 *  Self-checking behavioral testbench for bsg_cache_to_wb4 adapter.
 *  Verifies:
 *    - 4-word burst cache line eviction (Write)
 *    - 4-word burst cache line refill (Read)
 *    - Pipelined Wishbone B4 protocol handshaking
 *
 *  @author Sayan Kole
 */

`timescale 1ns / 1ps

`include "bsg_defines.sv"
`include "bsg_cache.svh"

module test_bsg_cache_to_wb4;
  import bsg_cache_pkg::*;

  // Testbench Configuration Parameters
  localparam num_cache_p            = 1;
  localparam addr_width_p           = 32;
  localparam data_width_p           = 32;
  localparam block_size_in_words_p  = 4;
  localparam ways_p                 = 1;
  localparam mask_width_p           = data_width_p / 8;
  localparam dma_pkt_width_lp       = `bsg_cache_dma_pkt_width(addr_width_p, mask_width_p);

  // Clock & Reset
  bit clk = 0;
  logic reset;

  // Cache <-> Adapter signals
  `declare_bsg_cache_dma_pkt_s(addr_width_p, mask_width_p);
  bsg_cache_dma_pkt_s [num_cache_p-1:0] dma_pkt_in;
  logic [num_cache_p-1:0]               dma_pkt_v;
  logic [num_cache_p-1:0]               dma_pkt_yumi;

  logic [num_cache_p-1:0][data_width_p-1:0] dma_data_out;
  logic [num_cache_p-1:0]                   dma_data_v_out;
  logic [num_cache_p-1:0]                   dma_data_ready_and;

  logic [num_cache_p-1:0][data_width_p-1:0] dma_data_in;
  logic [num_cache_p-1:0]                   dma_data_v_in;
  logic [num_cache_p-1:0]                   dma_data_yumi_out;

  // Adapter <-> Wishbone Bus signals
  logic [addr_width_p-1:0]  wb_adr;
  logic [data_width_p-1:0]  wb_dat_m2s;
  logic [data_width_p-1:0]  wb_dat_s2m;
  logic [mask_width_p-1:0]  wb_sel;
  logic                     wb_we;
  logic                     wb_cyc;
  logic                     wb_stb;
  logic                     wb_stall;
  logic                     wb_ack;
  logic                     wb_err;

  // 100 MHz Clock Generation (10ns period)
  always #5 clk = ~clk;

  // =========================================================================
  // Device Under Test (DUT): Your Adapter
  // =========================================================================
  bsg_cache_to_wb4 #(
    .num_cache_p(num_cache_p)
    ,.addr_width_p(addr_width_p)
    ,.data_width_p(data_width_p)
    ,.block_size_in_words_p(block_size_in_words_p)
    ,.ways_p(ways_p)
    ,.mask_width_p(mask_width_p)
  ) dut (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.dma_pkt_i(dma_pkt_in)
    ,.dma_pkt_v_i(dma_pkt_v)
    ,.dma_pkt_yumi_o(dma_pkt_yumi)

    ,.dma_data_o(dma_data_out)
    ,.dma_data_v_o(dma_data_v_out)
    ,.dma_data_ready_and_i(dma_data_ready_and)

    ,.dma_data_i(dma_data_in)
    ,.dma_data_v_i(dma_data_v_in)
    ,.dma_data_yumi_o(dma_data_yumi_out)

    ,.wb_adr_o(wb_adr)
    ,.wb_dat_o(wb_dat_m2s)
    ,.wb_dat_i(wb_dat_s2m)
    ,.wb_sel_o(wb_sel)
    ,.wb_we_o(wb_we)
    ,.wb_cyc_o(wb_cyc)
    ,.wb_stb_o(wb_stb)
    ,.wb_stall_i(wb_stall)
    ,.wb_ack_i(wb_ack)
    ,.wb_err_i(wb_err)
  );

  // =========================================================================
  // Wishbone B4 Slave Memory Model
  // =========================================================================
  bsg_test_mem_wb4 #(
    .addr_width_p(addr_width_p)
    ,.data_width_p(data_width_p)
    ,.mem_size_p(2048)
    ,.latency_p(2)
  ) mem_model (
    .clk_i(clk)
    ,.reset_i(reset)

    ,.wb_adr_i(wb_adr)
    ,.wb_dat_i(wb_dat_m2s)
    ,.wb_dat_o(wb_dat_s2m)
    ,.wb_sel_i(wb_sel)
    ,.wb_we_i(wb_we)
    ,.wb_cyc_i(wb_cyc)
    ,.wb_stb_i(wb_stb)
    ,.wb_stall_o(wb_stall)
    ,.wb_ack_o(wb_ack)
    ,.wb_err_o(wb_err)
  );

  // Test Data Vectors
  logic [31:0] test_write_data [0:3];
  logic [31:0] read_back_data  [0:3];
  int read_word_count;
  logic clear_read_count;

  // Stream write data: Keeps streaming until all 4 words are consumed
  logic write_active;
  int   write_word_count;

  always_ff @(posedge clk) begin
    if (reset) begin
      write_active     <= 1'b0;
      write_word_count <= 0;
      dma_data_v_in[0] <= 1'b0;
      dma_data_in[0]   <= '0;
    end else begin
      // Trigger write stream when packet header is presented
      if (dma_pkt_v[0] && dma_pkt_in[0].write_not_read) begin
        write_active     <= 1'b1;
        write_word_count <= 0;
        dma_data_v_in[0] <= 1'b1;
        dma_data_in[0]   <= test_write_data[0];
      end else if (write_active) begin
        // When adapter accepts a word, present the next one
        if (dma_data_yumi_out[0]) begin
          if (write_word_count < 3) begin
            write_word_count <= write_word_count + 1;
            dma_data_in[0]   <= test_write_data[write_word_count + 1];
            dma_data_v_in[0] <= 1'b1;
          end else begin
            // All 4 words streamed!
            write_active     <= 1'b0;
            dma_data_v_in[0] <= 1'b0;
          end
        end
      end else begin
        dma_data_v_in[0] <= 1'b0;
      end
    end
  end

  // Collect returning read words from adapter
  always_ff @(posedge clk) begin
    if (reset || clear_read_count) begin
      read_word_count <= 0;
    end else begin
      if (dma_data_v_out[0]) begin
        read_back_data[read_word_count] <= dma_data_out[0];
        read_word_count <= read_word_count + 1;
      end
    end
  end

  // =========================================================================
  // Main Verification Process
  // =========================================================================
  initial begin
    reset = 1;
    clear_read_count = 0;
    dma_pkt_v = '0;
    dma_pkt_in = '0;
    dma_data_ready_and = '1; // Cache is always ready to receive read data

    test_write_data[0] = 32'hDEAD_BEEF;
    test_write_data[1] = 32'hCAFE_BABE;
    test_write_data[2] = 32'h1122_3344;
    test_write_data[3] = 32'h5566_7788;

    $display("==================================================");
    $display("   STARTING BSG_CACHE_TO_WB4 VERIFICATION         ");
    $display("==================================================");

    // Apply Reset for 5 clock cycles
    repeat (5) @(posedge clk);
    reset = 0;
    repeat (2) @(posedge clk);

    // -----------------------------------------------------------------------
    // TEST 1: Cache Eviction (4-Word Burst Write)
    // -----------------------------------------------------------------------
    $display("[INFO] Starting Test 1: 4-Word Burst Write to 0x0000_1000...");
    @(posedge clk);
    dma_pkt_in[0].write_not_read = 1'b1;
    dma_pkt_in[0].addr           = 32'h0000_1000;
    dma_pkt_in[0].mask           = 4'b1111;
    dma_pkt_v[0]                 = 1'b1;

    // Wait for adapter to acknowledge and consume the packet header
    wait (dma_pkt_yumi[0]);
    @(posedge clk);
    dma_pkt_v[0] = 1'b0;

    // Wait for the Wishbone bus cycle to start, then finish
    wait (wb_cyc == 1'b1);
    wait (wb_cyc == 1'b0);
    repeat (3) @(posedge clk);

    // Check memory array directly
    assert(mem_model.mem[32'h1000 >> 2] == 32'hDEAD_BEEF)
      else $fatal(1, "[FAIL] Word 0 mismatch in RAM!");
    assert(mem_model.mem[(32'h1000 >> 2) + 1] == 32'hCAFE_BABE)
      else $fatal(1, "[FAIL] Word 1 mismatch in RAM!");
    assert(mem_model.mem[(32'h1000 >> 2) + 2] == 32'h1122_3344)
      else $fatal(1, "[FAIL] Word 2 mismatch in RAM!");
    assert(mem_model.mem[(32'h1000 >> 2) + 3] == 32'h5566_7788)
      else $fatal(1, "[FAIL] Word 3 mismatch in RAM!");

    $display("[PASS] Test 1: 4-Word Burst Write completed and verified in RAM!");

    // -----------------------------------------------------------------------
    // TEST 2: Cache Refill (4-Word Burst Read)
    // -----------------------------------------------------------------------
    $display("[INFO] Starting Test 2: 4-Word Burst Read from 0x0000_1000...");
    
    // Clear read counter synchronously
    clear_read_count = 1'b1;
    @(posedge clk);
    clear_read_count = 1'b0;

    @(posedge clk);
    dma_pkt_in[0].write_not_read = 1'b0;
    dma_pkt_in[0].addr           = 32'h0000_1000;
    dma_pkt_in[0].mask           = 4'b1111;
    dma_pkt_v[0]                 = 1'b1;

    wait (dma_pkt_yumi[0]);
    @(posedge clk);
    dma_pkt_v[0] = 1'b0;

    // Wait until Wishbone cycle runs and finishes
    wait (wb_cyc == 1'b1);
    wait (wb_cyc == 1'b0);
    repeat (3) @(posedge clk);

    // Check read data returned to the cache
    assert(read_back_data[0] == 32'hDEAD_BEEF) else $fatal(1, "[FAIL] Read Word 0 mismatch!");
    assert(read_back_data[1] == 32'hCAFE_BABE) else $fatal(1, "[FAIL] Read Word 1 mismatch!");
    assert(read_back_data[2] == 32'h1122_3344) else $fatal(1, "[FAIL] Read Word 2 mismatch!");
    assert(read_back_data[3] == 32'h5566_7788) else $fatal(1, "[FAIL] Read Word 3 mismatch!");

    $display("[PASS] Test 2: 4-Word Burst Read completed and verified against written data!");

    // -----------------------------------------------------------------------
    // Final Verdict
    // -----------------------------------------------------------------------
    $display("==================================================");
    $display("   *** ALL TESTS PASSED! ZERO ERRORS! ***        ");
    $display("==================================================");
    $finish;
  end

endmodule