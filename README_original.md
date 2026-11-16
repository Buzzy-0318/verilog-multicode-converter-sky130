# Binary ⇄ Gray / BCD / Excess-3 Code Converter
Datapath + control-path RTL design (Verilog-2001) with a SystemVerilog verification environment.

## 1. File architecture

```
code_converter/
├── README.md
├── rtl/                          ← synthesizable design (plain Verilog-2001)
│   ├── code_conv_defs.vh         shared constants: mode codes, mux selects, input kinds
│   ├── conv_control.v            CONTROL PATH : mode reg, opcode decoder, 5-state FSM
│   ├── conv_datapath.v           DATAPATH     : registers, shifter, +3/-3 units, gray units, mux
│   └── code_converter_top.v      top level, wires control <-> datapath
├── tb/                           ← verification (SystemVerilog)
│   ├── conv_if.sv                interface + 8 SVA protocol assertions
│   ├── conv_tb_pkg.sv            reference model, txn, coverage, scoreboard,
│   │                             monitor, driver, environment, all 9 tests
│   └── tb_code_converter.sv      testbench top: clock, DUT, interface, watchdog
└── sim/
    ├── Makefile                  make lint | sim | wave | questa | vcs | xrun | clean
    ├── filelist_rtl.f
    ├── filelist_tb.f
    └── sample_run.log            log of a passing run
```

Compile order: `code_conv_defs.vh` (include) → `conv_control.v` → `conv_datapath.v` →
`code_converter_top.v` → `conv_if.sv` → `conv_tb_pkg.sv` → `tb_code_converter.sv`.

## 2. Supported conversions

| mode | operation   | input format                   | output format          |
|------|-------------|--------------------------------|------------------------|
| 000  | BIN → GRAY  | binary, bits [7:0]             | gray, bits [7:0]       |
| 001  | GRAY → BIN  | gray, bits [7:0]               | binary, bits [7:0]     |
| 010  | BIN → BCD   | binary, bits [7:0]             | 3 BCD digits [11:0]    |
| 011  | BCD → BIN   | 3 BCD digits [11:0], ≤ 255     | binary, bits [7:0]     |
| 100  | BIN → EX3   | binary, bits [7:0]             | 3 excess-3 digits      |
| 101  | EX3 → BIN   | 3 excess-3 digits, value ≤ 255 | binary, bits [7:0]     |
| 110/111 | reserved | –                              | `err = 1`              |

`err = 1` and `data_out = 0` for: reserved mode · non-zero bits [11:8] on a binary/gray input ·
BCD digit > 9 · excess-3 digit outside 3…12 · BCD/EX3 value > 255 (does not fit 8 bits).

Parameters: `BIN_W` (default 8), `DIGITS` (default 3). Constraint: `10**DIGITS > 2**BIN_W - 1`.

## 3. Architecture

```
                         code_converter_top
   ┌────────────────────────────────────────────────────────────────────────┐
   │                                                                        │
   │   ┌───────────────────┐   control word                                 │
 start─►│                   ├──ld_in ld_sh sh_step cnt_clr cnt_inc ld_out──┐ │
 mode ─►│    conv_control   ├──sh_dir init_ex3 force_err in_kind res_sel──►│ │
 busy ◄─┤   (CONTROL PATH)  │                                              │ │
 done ◄─┤  mode_q + decoder │◄──── status: cnt_last, bad_in ───────────┐   │ │
   │    │  FSM              │                                          │   │ │
   │    └───────────────────┘                                          │   ▼ │
   │                                                          ┌────────┴─────┴──┐
 data_in[11:0] ─────────────────────────────────────────────►│  conv_datapath  │──► data_out[11:0]
   │                                                          │                 │──► err
   │                                                          └─────────────────┘
   └────────────────────────────────────────────────────────────────────────┘
```

### Datapath (`conv_datapath.v`)
```
 data_in ─►[in_q 12b]──┬─► legality checker ─────────────────► bad_in (status)
                       ├─► bin→gray ───────────────┐
                       ├─► gray→bin ───────────────┤
                       ├─► −3/digit (EX3→BCD) ─┐   │
                       │                       ▼   │
                       └──────────► preload mux   │
                                        │         │
                         [sh_q 20b = BCD(12) | BIN(8)]  ◄─ dabble / reverse-dabble step
                                        │         │       (add-3 if ≥5 / shift-right, sub-3 if ≥8)
                          BCD field ────┤         │
                          BIN field ────┤         ▼
                          BCD+3/digit ──┴──► result mux (res_sel) ─► [out_q 12b] ─► data_out
                                                                    ► [err_q]     ─► err
                          [cnt_q 3b] ──► cnt_last (status)
```
* **BIN → BCD** (double-dabble): load `{0, bin}`; 8 × { digits ≥ 5 get +3, shift left }.
* **BCD → BIN** (reverse double-dabble): load `{bcd, 0}`; 8 × { shift right, digits ≥ 8 get −3 }.
  A non-zero BCD field afterwards means the value did not fit in 8 bits → `err`.
* **BIN → EX3**: BIN → BCD, then +3 on every digit in the result mux.
* **EX3 → BIN**: −3 on every digit while preloading, then BCD → BIN.
* **Gray**: combinational `g = b ^ (b>>1)` and prefix-XOR decode; the FSM just passes through EXEC once.

### Control path (`conv_control.v`)
```
          start                              abort = bad_in | reserved mode
  ┌──────┐ ────► ┌──────┐   ┌──────────────────────────────┐  done  ┌───────┐   ┌──────┐
  │ IDLE │       │ INIT │──►│ EXEC                         │──────►│ STORE │──►│ DONE │──► IDLE
  └──────┘       └──────┘   │  iterative: step + cnt_inc   │        └───────┘   └──────┘
   ld_in         ld_sh      │             until cnt_last   │        ld_out      done=1
                 cnt_clr    │  gray/abort: leave after 1   │
                            └──────────────────────────────┘
```
| state | control word asserted               | next state |
|-------|-------------------------------------|------------|
| IDLE  | `ld_in` when `start`; latches `mode`| INIT on start |
| INIT  | `ld_sh`, `cnt_clr`                  | EXEC |
| EXEC  | `sh_step`, `cnt_inc` (iterative modes) | STORE when `cnt_last`, or immediately for gray / abort |
| STORE | `ld_out`                            | DONE |
| DONE  | `done`                              | IDLE |

**Latency** (edge sampling `start` → edge sampling `done`): 11 cycles for legal BCD/EX3
conversions, 4 cycles for gray modes, illegal inputs and reserved modes.

### Handshake
Present `mode` + `data_in`, pulse `start` for one cycle while `busy = 0`. Wait for the one-cycle
`done` pulse; `data_out`/`err` are valid then and held until the next conversion. A `start` while
`busy = 1` is ignored. `rst_n` is asynchronous, active-low.

## 4. Verification

| # | test | what it proves |
|---|------|----------------|
| 1 | reset | outputs at reset values |
| 2 | directed | 22 hand-computed vectors (independent of the reference model) |
| 3 | errors | illegal BCD/EX3, overflow, upper bits, reserved modes, recovery |
| 4 | **exhaustive** | all 8 modes × all 4096 inputs = 32 768 conversions vs. reference model |
| 5 | round trip | X→Y→X == X for all 256 values, for gray, BCD and excess-3 |
| 6 | random | 3000 transactions, random mode/data/idle gaps |
| 7 | start while busy | glitch `start` with other data is ignored |
| 7b | held start / start in DONE | multi-cycle `start`, `start` in the DONE cycle |
| 8 | reset mid-conversion | async reset aborts cleanly, design recovers |

Checking is layered: **scoreboard** (value + error flag + latency, every transaction), **SVA** in
`conv_if.sv` (done is a 1-cycle pulse, done⇒busy, busy releases after done, outputs only change
on entering DONE, `err ⇒ data_out == 0`, …), **self-checking tests**, and **functional coverage**
bins (mode × legal/illegal, overflow, corner values). The reference model uses plain arithmetic
(`/ % *`), deliberately not the RTL's shift-add algorithm.

The reported result: 37 355 conversions, 0 mismatches, 100 % coverage bins, `TEST PASSED`.
The testbench was also mutation-checked: 8 injected RTL faults (wrong add-3 threshold, 2-cycle
`done`, restart in DONE, missing overflow check, wrong EX3 range, …) were all detected.

### Running
```bash
cd sim
make lint                       # Verilator + Icarus lint of the RTL
make sim                        # Verilator 5.x  (needs --binary/--timing support, v5.006+)
make wave                       # + code_converter.vcd
make questa | make vcs | make xrun    # commercial simulators, same file lists
```
Notes: the testbench uses classes, so Icarus Verilog cannot run it (it can lint the RTL).
Under Verilator an SVA failure stops the run at the first `$error`; commercial simulators
continue and report all. Coverage is hand-rolled counters (no `covergroup`) so it works in every tool.
