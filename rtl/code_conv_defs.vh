//==============================================================================
// code_conv_defs.vh  -  shared constants for the code-converter project
//==============================================================================
`ifndef CODE_CONV_DEFS_VH
`define CODE_CONV_DEFS_VH

// ---- conversion modes (the mode input port) ----------------------------------
`define MODE_BIN2GRAY  3'b000   // binary   -> gray
`define MODE_GRAY2BIN  3'b001   // gray     -> binary
`define MODE_BIN2BCD   3'b010   // binary   -> BCD       (double-dabble, iterative)
`define MODE_BCD2BIN   3'b011   // BCD      -> binary    (reverse double-dabble)
`define MODE_BIN2EX3   3'b100   // binary   -> excess-3  (double-dabble + 3 per digit)
`define MODE_EX32BIN   3'b101   // excess-3 -> binary    (-3 per digit + reverse dabble)
                                // 3'b110, 3'b111 are reserved -> flagged as error

// ---- datapath result-mux select (control path -> datapath) -------------------
`define RES_GRAY       3'd0     // gray code of the input register
`define RES_BIN_GRAY   3'd1     // binary decoded from gray in the input register
`define RES_BCD        3'd2     // BCD field of the shift register
`define RES_BIN_SH     3'd3     // binary field of the shift register
`define RES_EX3        3'd4     // BCD field of the shift register + 3 per digit

// ---- input-kind select (what the input register is supposed to contain) -----
`define KIND_PLAIN     2'd0     // plain binary / gray : upper bits must be 0
`define KIND_BCD       2'd1     // every digit must be 0..9
`define KIND_EX3       2'd2     // every digit must be 3..12

`endif
