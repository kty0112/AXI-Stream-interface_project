# AXI-Stream-interface_project
# AXI4-Stream Asynchronous Data Width Converter

An AXI4-Stream compliant asynchronous data width converter (DWC) with full UVM verification environment. Supports clock domain crossing (CDC) with configurable upsizing, downsizing, and passthrough modes.

## Architecture Overview

The top module (`axis_async_dwc_top`) automatically selects the datapath based on `TX_WIDTH` and `RX_WIDTH`:

| Condition | Instantiated Module | Description |
|---|---|---|
| `TX_WIDTH < RX_WIDTH` | `axis_async_upsizer` | Narrow-to-wide conversion |
| `TX_WIDTH > RX_WIDTH` | `axis_async_downsizer` | Wide-to-narrow conversion |
| `TX_WIDTH == RX_WIDTH` | `axis_async_fifo_wrapper` | CDC-only passthrough |

## Features

- **AXI4-Stream compliant** — Full TVALID/TREADY handshake with TDATA, TSTRB, TKEEP, TLAST, TID, TDEST, TUSER
- **Asynchronous CDC** — Gray-code pointer based async FIFO with 2-stage synchronizers
- **Configurable width conversion** — Any power-of-2 ratio between TX and RX widths
- **Timing closure** — Configurable skid buffer chains on TX, MID, and RX stages
- **Optional sync FIFO** — Pre-buffer for downsizer to absorb back-pressure from serialization

## Project Structure

```
├── ip/
│   ├── axis_async_dwc_top.v          # Top-level module (auto-selects up/down/bypass)
│   ├── async_fifo/
│   │   ├── async_fifo.v              # Gray-code async FIFO + AXI-Stream wrapper
│   │   ├── gray_ptr.v                # Gray-code pointer with low-latency option
│   │   └── synchronizer.v            # Multi-stage synchronizer
│   ├── components/
│   │   ├── comp_dff.v                # Complementary D flip-flop
│   │   ├── skid_buffer.v             # Pipeline skid buffer
│   │   └── sync_fifo.v               # Synchronous FIFO
│   ├── upsizer/
│   │   ├── axis_upsizer.v            # Width upsizer core
│   │   └── axis_async_upsizer.v      # Upsizer + skid chains + async FIFO
│   └── downsizer/
│       ├── axis_downsizer.v           # Width downsizer core + wrapper with optional sync FIFO
│       └── axis_async_downsizer.v     # Downsizer + skid chains + async FIFO
├── testbench/
│   ├── testbench.sv                   # Top-level testbench with DUT instantiation
│   ├── axis_if.sv                     # AXI-Stream interface with SVA properties
│   ├── axis_pkg.sv                    # UVM package
│   └── components/
│       ├── axis_transaction.sv        # AXI-Stream transaction item
│       ├── axis_sequence.sv           # Random & full-rate sequences
│       ├── axis_test.sv               # Stress test & performance test
│       ├── agent/
│       │   ├── axis_agent.sv          # Configurable master/slave agent
│       │   ├── axis_master_driver.sv  # Master (TX) driver
│       │   ├── axis_slave_driver.sv   # Slave (RX) driver with back-pressure
│       │   ├── axis_monitor.sv        # Protocol monitor with coverage
│       │   └── axis_sequencer.sv      # Transaction sequencer
│       └── env/
│           ├── axis_env.sv            # UVM environment
│           └── axis_scoreboard.sv     # Data integrity checker + performance metrics
├── script/
│   ├── run_uvm_verification.tcl       # UVM verification runner (parameter sweep)
│   ├── run_impl.tcl                   # Vivado implementation (non-project mode)
│   ├── gen_clk_params.py              # Clock/phase parameter sweep generator
│   ├── analyze_perf.py                # Post-simulation performance analyzer
│   ├── dummy_top.v                    # Wrapper for implementation analysis
│   ├── view_wave.tcl                  # Waveform viewer helper
│   └── clear_artifacts.tcl            # Clean build artifacts
├── config_verification.yaml           # Verification configuration
└── config_implementation.yaml         # Implementation configuration
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `FIFO_DEPTH` | 16 | Async FIFO depth (must be power of 2, ≥ 4) |
| `TX_WIDTH` | 32 | Input data width (bits) |
| `RX_WIDTH` | 128 | Output data width (bits) |
| `TX_SKID_NUM` | 1 | Number of skid buffers on input side |
| `RX_SKID_NUM` | 1 | Number of skid buffers on output side |
| `MID_SKID_NUM` | 1 | Number of skid buffers between converter and FIFO |
| `TID_WIDTH` | 1 | AXI-Stream TID width |
| `TDEST_WIDTH` | 1 | AXI-Stream TDEST width |
| `TUSER_WIDTH` | 1 | AXI-Stream TUSER width |
| `USE_SYNC_FIFO` | 1 | Enable sync FIFO pre-buffer in downsizer |

## Configuration

All configuration is driven through YAML files.

### Verification (`config_verification.yaml`)

Controls the UVM simulation parameter sweep:

- **Clock modes**: `fast_write_slow_read`, `slow_write_fast_read`, `almost_equal`, `async_ratio`
- **Phase modes**: `zero`, `varied`, `symmetric`, `asymmetric`
- **Test selection**: `axis_stress_test` (back-pressure + FIFO full/empty), `axis_perf_test` (full-rate throughput)
- **Sweep control**: `num_parameter_sets` for clock and phase independently

### Implementation (`config_implementation.yaml`)

Controls Vivado synthesis and place-and-route targeting Zynq-7020 (`xc7z020clg400-1`).

## Running Verification

Requires: Vivado (with Xsim), Python 3

```bash
# Generate clock parameters and run full UVM parameter sweep
vivado -mode tcl -source script/run_uvm_verification.tcl -notrace
```

The flow:
1. Generates clock/phase parameter sets via `gen_clk_params.py`
2. Compiles RTL and UVM testbench
3. Runs elaboration + simulation for each parameter combination
4. Reports pass/fail summary with timing statistics

Results are written to `result/<clock_config>/<phase_config>/`:
- `status.txt` — Error count (0 = pass)
- `performance.csv` — Throughput, latency, transaction counts
- `integrity.log` — Detailed mismatch log
- `waveform.wdb` — Waveform dump (if `dump_waveform: true`)

### Post-Simulation Analysis

```bash
python3 script/analyze_perf.py --csv result/<path>/performance.csv --yaml config_verification.yaml
```

## Running Implementation

Requires: Vivado

```bash
vivado -mode batch -source script/run_impl.tcl
```

Generates utilization, timing, power, and DRC reports in `impl_result/`.

## Verification Environment

The UVM testbench verifies:

- **Data integrity** — Byte-level comparison accounting for width conversion ratio and TKEEP masking
- **Protocol compliance** — SVA assertions for TVALID/TREADY stability, TSTRB/TKEEP relationship
- **Back-pressure handling** — Randomized slave ready with increasing back-pressure bias
- **FIFO boundary conditions** — Full and empty detection via cycle-counting monitors
- **Performance metrics** — Throughput (Mbps), frame latency (ns), min/max latency

### Available Tests

| Test | Description |
|---|---|
| `axis_stress_test` | Random traffic → triggers FIFO full → drains to FIFO empty |
| `axis_perf_test` | Zero-delay full-rate traffic with fixed slave ready |
