/**
 *  bsg_cache_to_wb4.sv
 *
 *  Pipelined Wishbone B4 adapter for BaseJump STL / BlackParrot cache DMA interface.
 *  Translates bsg_cache_dma_pkt_s bursts into Wishbone B4 pipelined transactions.
 *
 *  @author Sayan Kole
 */

`include "bsg_defines.sv"
`include "bsg_cache.svh"

module bsg_cache_to_wb4
  import bsg_cache_pkg::*;
  #(parameter `BSG_INV_PARAM(num_cache_p)
    , parameter `BSG_INV_PARAM(addr_width_p)           // Cache address width (byte-level)
    , parameter `BSG_INV_PARAM(data_width_p)           // Cache data width
    , parameter `BSG_INV_PARAM(block_size_in_words_p)  // Cache line block size (in words)
    , parameter ways_p = 1                             // Cache ways (default 1)
    , parameter mask_width_p = (data_width_p >> 3)     // Mask width in bytes

    , parameter wb_data_width_p = data_width_p         // Wishbone data bus width
    , parameter wb_addr_width_p = addr_width_p         // Wishbone address width

    // Derived localparams
    , parameter dma_data_width_p = data_width_p
    , parameter num_req_lp = (block_size_in_words_p * data_width_p / wb_data_width_p)
    , parameter lg_num_req_lp = `BSG_SAFE_CLOG2(num_req_lp)
    , parameter wb_byte_offset_width_lp = `BSG_SAFE_CLOG2(wb_data_width_p >> 3)
    , parameter wb_sel_width_lp = (wb_data_width_p >> 3)

    , parameter lg_num_cache_lp = `BSG_SAFE_CLOG2(num_cache_p)
    , parameter dma_pkt_width_lp = `bsg_cache_dma_pkt_width(addr_width_p, mask_width_p)
  )
  (
    input logic clk_i
    , input logic reset_i

    // Cache DMA Interface
    , input  logic [num_cache_p-1:0][dma_pkt_width_lp-1:0] dma_pkt_i
    , input  logic [num_cache_p-1:0]                       dma_pkt_v_i
    , output logic [num_cache_p-1:0]                       dma_pkt_yumi_o

    , output logic [num_cache_p-1:0][dma_data_width_p-1:0] dma_data_o
    , output logic [num_cache_p-1:0]                       dma_data_v_o
    , input  logic [num_cache_p-1:0]                       dma_data_ready_and_i

    , input  logic [num_cache_p-1:0][dma_data_width_p-1:0] dma_data_i
    , input  logic [num_cache_p-1:0]                       dma_data_v_i
    , output logic [num_cache_p-1:0]                       dma_data_yumi_o

    // Wishbone B4 Pipelined Master Interface
    , output logic [wb_addr_width_p-1:0]                   wb_adr_o
    , output logic [wb_data_width_p-1:0]                   wb_dat_o
    , input  logic [wb_data_width_p-1:0]                   wb_dat_i
    , output logic [wb_sel_width_lp-1:0]                   wb_sel_o
    , output logic                                         wb_we_o
    , output logic                                         wb_cyc_o
    , output logic                                         wb_stb_o
    , input  logic                                         wb_stall_i
    , input  logic                                         wb_ack_i
    , input  logic                                         wb_err_i
  );

  // =========================================================================
  // Block 2: Packet Unpacking & Multi-Cache Arbiter
  // =========================================================================
  // Pass all 3 parameters to the macro!
  `declare_bsg_cache_dma_pkt_s(addr_width_p, mask_width_p);
  bsg_cache_dma_pkt_s [num_cache_p-1:0] dma_pkt;
  assign dma_pkt = dma_pkt_i;

  // Arbiter signals
  logic                                 rr_v_lo;
  logic                                 rr_yumi_li;
  bsg_cache_dma_pkt_s                   rr_dma_pkt_lo;
  logic [lg_num_cache_lp-1:0]           rr_tag_lo;

  // Active transaction holding registers
  logic                                 active_r;
  logic [lg_num_cache_lp-1:0]           curr_tag_r;
  bsg_cache_dma_pkt_s                   curr_pkt_r;

  // Single round-robin arbiter across all incoming caches
  bsg_round_robin_n_to_1 #(
    .width_p(dma_pkt_width_lp)
    ,.num_in_p(num_cache_p)
    ,.strict_p(0)
    ,.use_scan_p(1)
  ) rr0 (
    .clk_i(clk_i)
    ,.reset_i(reset_i)

    ,.data_i(dma_pkt)
    ,.v_i(dma_pkt_v_i)
    ,.yumi_o(dma_pkt_yumi_o)

    ,.v_o(rr_v_lo)
    ,.data_o(rr_dma_pkt_lo)
    ,.tag_o(rr_tag_lo)
    ,.yumi_i(rr_yumi_li)
  );

  // =========================================================================
  // Block 3: Pipelined Counters & Address Generator
  // =========================================================================
  // We track TWO counters because Wishbone B4 is pipelined:
  // 1. req_cnt_r: counts address requests accepted by slave (stb && !stall)
  // 2. ack_cnt_r: counts responses acknowledged by slave (ack)
  logic [lg_num_req_lp-1:0] req_cnt_r;
  logic [lg_num_req_lp-1:0] ack_cnt_r;

  wire req_fire = wb_cyc_o & wb_stb_o & ~wb_stall_i;
  wire ack_fire = wb_cyc_o & wb_ack_i;

  // Wire for the calculated word address
  logic [wb_addr_width_p-1:0] burst_addr;

  if (num_req_lp == 1) begin : single_req
    assign burst_addr = curr_pkt_r.addr;
  end else begin : multi_req
    // Splice req_cnt_r into the word-offset bits of the base address
    assign burst_addr = {
      curr_pkt_r.addr[wb_addr_width_p-1 : wb_byte_offset_width_lp + lg_num_req_lp],
      req_cnt_r,
      {wb_byte_offset_width_lp{1'b0}}
    };
  end
  // =========================================================================
  // Block 4: Write Data Path (Cache -> Wishbone Bus)
  // =========================================================================
  // Route data from the winning cache to the Wishbone write data bus
  assign wb_dat_o = dma_data_i[curr_tag_r];

  // Byte select: For full-line cache evictions, all byte enables are active.
  // (In 32-bit systems, this drives 4'b1111)
  assign wb_sel_o = {wb_sel_width_lp{1'b1}};

  // Handshake to Cache: Every time the Wishbone slave accepts a write word
  // (req_fire == 1), pulse yumi to consume that word from the winning cache.
  for (genvar i = 0; i < num_cache_p; i++) begin : dma_tx_yumi
    assign dma_data_yumi_o[i] = (active_r && curr_pkt_r.write_not_read && (curr_tag_r == i))
                                ? req_fire
                                : 1'b0;
  end

  // =========================================================================
  // Block 5: Read Return Path (Wishbone Bus -> Cache)
  // =========================================================================
  // Route incoming read data from Wishbone directly to the winning cache.
  // Whenever the slave pulses wb_ack_i on a read, assert dma_data_v_o.
  for (genvar i = 0; i < num_cache_p; i++) begin : dma_rx_data
    assign dma_data_o[i]   = wb_dat_i;
    assign dma_data_v_o[i] = (active_r && ~curr_pkt_r.write_not_read && (curr_tag_r == i))
                             ? ack_fire
                             : 1'b0;
  end
  // =========================================================================
  // Block 6: Master FSM, Request Strobe & ACK Tracker
  // =========================================================================
  logic req_done_r;

  // Drive Wishbone Control Signals
  assign wb_cyc_o = active_r;
  assign wb_we_o  = curr_pkt_r.write_not_read;
  assign wb_adr_o = burst_addr;

  // On writes, only assert strobe if the cache has valid write data ready.
  // On reads, assert strobe as long as we have addresses left to send.
  wire tx_data_ready = ~curr_pkt_r.write_not_read | dma_data_v_i[curr_tag_r];
  assign wb_stb_o = active_r & ~req_done_r & tx_data_ready;

  // Arbiter consumption handshake:
  // Accept a new packet from the arbiter when IDLE and a request is valid.
  assign rr_yumi_li = ~active_r & rr_v_lo;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      active_r    <= 1'b0;
      req_done_r  <= 1'b0;
      req_cnt_r   <= '0;
      ack_cnt_r   <= '0;
      curr_tag_r  <= '0;
      curr_pkt_r  <= '0;
    end else begin
      if (~active_r) begin
        // IDLE: Wait for arbiter to grant a cache request
        if (rr_v_lo) begin
          active_r    <= 1'b1;
          req_done_r  <= 1'b0;
          req_cnt_r   <= '0;
          ack_cnt_r   <= '0;
          curr_tag_r  <= rr_tag_lo;
          curr_pkt_r  <= rr_dma_pkt_lo;
        end
      end else begin
        // ACTIVE BURST TRANSACTION

        // 1. Advance the Address/Request Phase
        if (req_fire) begin
          if (req_cnt_r == (num_req_lp - 1)) begin
            req_done_r <= 1'b1; // All addresses in the burst have been sent!
          end else begin
            req_cnt_r  <= req_cnt_r + 1'b1;
          end
        end

        // 2. Advance the Data/Response Phase
        if (ack_fire) begin
          if (ack_cnt_r == (num_req_lp - 1)) begin
            // All responses for this cache line burst have been received!
            active_r   <= 1'b0;
            req_done_r <= 1'b0;
          end else begin
            ack_cnt_r  <= ack_cnt_r + 1'b1;
          end
        end

      end
    end
  end

endmodule

`BSG_ABSTRACT_MODULE(bsg_cache_to_wb4)
