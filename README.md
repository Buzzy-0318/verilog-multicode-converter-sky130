# Multi-Code Converter | RTL Design & ASIC Physical Design

A parameterized Verilog-based code converter supporting Binary, Gray, BCD and Excess-3 conversions, implemented using a separate datapath and control path and taken through the SkyWater Sky130HD physical-design flow.

## Project Overview

This project implements a sequential multi-code converter with six supported conversion operations. The architecture separates the control logic from the datapath, using an FSM-based controller to coordinate iterative conversion operations.

### Supported Conversions

| Mode | Operation | Mode Encoding |
|---|---|---|
| BIN2GRAY | Binary → Gray | `000` |
| GRAY2BIN | Gray → Binary | `001` |
| BIN2BCD | Binary → BCD | `010` |
| BCD2BIN | BCD → Binary | `011` |
| BIN2EX3 | Binary → Excess-3 | `100` |
| EX32BIN | Excess-3 → Binary | `101` |
| Reserved | Invalid operation | `110`, `111` |

## Architecture

The design consists of three primary RTL modules:

- `code_converter_top.v` – Top-level integration of the controller and datapath.
- `conv_control.v` – FSM-based control path responsible for sequencing conversion operations.
- `conv_datapath.v` – Datapath containing conversion, validation, shifting and result-selection logic.
- `code_conv_defs.vh` – Shared mode and control definitions.

### Interface

| Signal | Width | Description |
|---|---:|---|
| `clk` | 1 | Clock |
| `rst_n` | 1 | Active-low asynchronous reset |
| `start` | 1 | Conversion request |
| `mode` | 3 | Conversion mode |
| `data_in` | 12 | Input data |
| `data_out` | 12 | Converted output |
| `busy` | 1 | Conversion in progress |
| `done` | 1 | Completion pulse |
| `err` | 1 | Invalid input or mode indication |

Default configuration: 8-bit binary data and three 4-bit decimal digits.

## Verification

SystemVerilog verification uses an interface, testbench package and top-level testbench.

Verification components:
- `conv_if.sv`
- `conv_tb_pkg.sv`
- `tb_code_converter.sv`

The recorded simulation log reports:

- 37,355 transactions accepted by the DUT.
- 37,354 results checked by the scoreboard.
- 0 scoreboard mismatches.
- 0 test self-check failures.
- 32,768 exhaustive mode/input combinations.
- 100% reported functional coverage.
- Directed, error-condition, round-trip, randomized and reset tests.

**Recorded simulation status: TEST PASSED.**

The included simulation log is a previously generated result. A fresh simulation has not yet been reproduced from this repository on the current machine because Verilator and Icarus Verilog are not installed.

## Physical Design

The RTL was synthesized and implemented using the open-source RTL-to-GDSII flow.

**Technology:** SkyWater SKY130HD

**Tools:**
- Yosys 0.66+115
- OpenROAD 26Q2
- KLayout 0.30.9

### Implementation Stages

1. RTL synthesis
2. Floorplanning
3. Global and detailed placement
4. Clock Tree Synthesis
5. Global routing
6. Detailed routing
7. Final GDS generation

### Synthesis Results

| Metric | Result |
|---|---:|
| Mapped standard-cell count | 479 |
| Synthesis cell area | 4,365.44 µm² |
| Sequential cell area | 1,351.30 µm² |
| Clock period constraint | 10 ns |

### Final Physical-Design Results

| Metric | Result |
|---|---:|
| Final design area | 4,921 µm² |
| Reported utilization | 41% |
| Total cell instances | 1,834 |
| Worst slack | 4.87 ns |
| Setup violations | 0 |
| Hold violations | 0 |
| Max slew violations | 0 |
| Max fanout violations | 0 |

These are flow results and should not be interpreted as foundry signoff.

### Physical Verification Status

- DRC: The generated KLayout DRC report contains zero reported violation entries. This is not a foundry signoff claim.
- LVS: The diagnostic LVS comparison reported a netlist mismatch and remains unresolved.

## Layout Visualizations

The repository includes placement, CTS, routing and final GDS views, along with OpenROAD-generated implementation visualizations.

See [`docs/images/`](docs/images/) for screenshots.

## Repository Structure

```text
verilog-multicode-converter-sky130/
├── rtl/
├── verification/
│   ├── testbench/
│   ├── results/
│   ├── Makefile
│   ├── filelist_rtl.f
│   └── filelist_tb.f
├── physical_design/
│   ├── config.mk
│   └── code_converter.sdc
├── reports/
│   ├── synthesis/
│   ├── floorplan/
│   ├── placement/
│   ├── cts/
│   ├── routing/
│   ├── final/
│   └── verification/
├── layout/
│   ├── placement/
│   ├── cts/
│   ├── routing/
│   └── final/
└── docs/
    └── images/
```

## Simulation

From the `verification` directory, use:

```bash
make sim
```

This requires Verilator with SystemVerilog timing and assertion support.

Other available Makefile targets include:

```bash
make lint
make wave
make clean
```

## Physical Design

The `physical_design/` directory contains the OpenROAD configuration and timing constraints. The implementation reports and layout outputs are provided for reference.

## Future Improvements

- Reproduce simulation from a clean environment.
- Resolve the outstanding LVS netlist mismatch.
- Extend physical verification and signoff checks.
- Explore timing and area optimization.

---

**Project Focus:** RTL Design | FSM | Datapath Architecture | SystemVerilog Verification | Yosys | OpenROAD | Sky130HD | Physical Design
