# Pipelined Wishbone B4 Adapter for BaseJump STL (`bsg_cache_to_wb4`)

An open-source, synthesizable SystemVerilog bridge that adapts the **Bespoke Silicon Group (BSG) Cache DMA interface** (used in the [BlackParrot RISC-V](https://github.com/black-parrot/black-parrot) processor) to the **Wishbone B4 Pipelined Bus Protocol**.

---

## 1. Overview & Architecture

BlackParrot caches (`bsg_cache`) emit internal DMA transaction packets (`bsg_cache_dma_pkt_s`) for line refills and evictions. This module acts as a bridge, translating those packets into standard pipelined Wishbone B4 bus transactions.

### Key Architectural Highlights
1. **Decoupled Pipelining:**
   - **Request Phase (`req_cnt_r`):** Pushes word addresses consecutively every cycle that `wb_stb_o && !wb_stall_i` holds true.
   - **Response Phase (`ack_cnt_r`):** Gathers returning data on `wb_ack_i` pulses without stalling address generation.
2. **Backpressure & Stall Safety:**
   - Automatically pauses address generation when `wb_stall_i` is asserted by slave memory.
   - On write operations, `wb_stb_o` is gated by `dma_data_v_i` so no unready data is ever driven to the bus.
3. **Multi-Cache Support:**
   - Uses `bsg_round_robin_n_to_1` to arbitrate between multiple incoming cache streams.

---

## 2. Repository File Structure

```text
├── bsg_cache/
│   └── bsg_cache_to_wb4.sv          # Synthesizable Wishbone B4 Adapter
│   └── bsg_defines.sv          
│   └── bsg_cache.svh          
│   └── bsg_cache_pkg.sv
│   └── bsg_round_robin_n_to_1.sv      
│
├── testing/
│   └── bsg_cache/
│       ├── bsg_test_mem_wb4.sv      # Compliant Wishbone B4 Slave RAM Model
│       └── test_bsg_cache_to_wb4.sv # Self-Checking Behavioral Testbench
│
└── README.md


```

# How to Open, Build, and Simulate

## Method 1: Using Xilinx Vivado (GUI)

### 1.  Clone the repository:

    git clone https://github.com/sayankole/basejump_stl.git
    cd basejump_stl

### 2.  Create a new Vivado project:

      - Open Vivado and click Create Project.
      - Name your project (e.g., WishBone_B4_arch) and select RTL Project.
      - Check "Do not specify sources at this time", choose any FPGA target
        (e.g., Artix-7 or Kintex-7), and click Finish.

### 3.  Add Design Sources:

      - In the Sources window, click Add Sources (+) \rightarrow choose Add or
        create design sources \rightarrow click Next.
      - Click Add Files and select all files from the bsg_cache/ folder:
          - bsg_defines.sv
          - bsg_cache.svh
          - bsg_cache_pkg.sv
          - bsg_round_robin_n_to_1.sv
          - bsg_cache_to_wb4.sv
      - Click Finish.
      - In the Sources hierarchy tree, right-click bsg_defines.sv and
        bsg_cache.svh \rightarrow click Set Global Include.

### 4.  Add Simulation Sources:

      - Click Add Sources (+) \rightarrow choose Add or create simulation
        sources \rightarrow click Next.
      - Click Add Files and select both files from testing/bsg_cache/:
          - bsg_test_mem_wb4.sv
          - test_bsg_cache_to_wb4.sv
      - Click Finish.

### 5.  Run the Simulation:

      - In the Simulation Sources tree, right-click test_bsg_cache_to_wb4.sv
        \rightarrow select Set as Top.
      - In the left Flow Navigator pane, click Run Simulation \rightarrow Run
        Behavioral Simulation.
      - Check the Tcl Console for test logs and inspect waveforms in the wave
        viewer.

## Method 2: Command Line

If Vivado tools (xvlog, xelab, xsim) are in your system PATH, you can run the
testbench directly without opening the GUI:

### 1. Compile SystemVerilog sources
xvlog -sv -i bsg_cache bsg_cache/bsg_defines.sv bsg_cache/bsg_cache_pkg.sv bsg_cache/bsg_round_robin_n_to_1.sv bsg_cache/bsg_cache_to_wb4.sv testing/bsg_cache/bsg_test_mem_wb4.sv testing/bsg_cache/test_bsg_cache_to_wb4.sv

### 2. Elaborate testbench snapshot
xelab -debug typical test_bsg_cache_to_wb4 -s sim_snapshot

# 3. Run simulation
xsim sim_snapshot -runall
