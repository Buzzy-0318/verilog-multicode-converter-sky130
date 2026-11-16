//==============================================================================
// code_converter_top.v  -  Binary <-> Gray / BCD / Excess-3 converter
//
//        +-------------------------------------------------------+
//  start |   +------------------+  control word  +-------------+ | data_in
//  mode  |-->|   conv_control   |--------------->| conv_data-  |<|--------
//  busy  |<--|   (control path) |<---------------|    path     | | data_out
//  done  |<--|                  |  cnt_last,     |             |-|-------->
//        |   +------------------+  bad_in        +-------------+ | err
//        +-------------------------------------------------------+
//
// Modes (see code_conv_defs.vh):
//   000 BIN->GRAY   001 GRAY->BIN   010 BIN->BCD   011 BCD->BIN
//   100 BIN->EX3    101 EX3->BIN    110/111 reserved (err=1)
//
// Format of data_in / data_out (12 bits with the default parameters):
//   binary / gray : bits [7:0], bits [11:8] must be 0 on input, are 0 on output
//   BCD / excess-3: bits [11:8] = hundreds, [7:4] = tens, [3:0] = units
//
// err=1 (data_out reads 0) when: reserved mode; binary/gray input with non-zero
// upper bits; BCD digit > 9; excess-3 digit outside 3..12; BCD/EX3 value > 255.
//==============================================================================
`timescale 1ns/1ps

module code_converter_top #(
    parameter BIN_W  = 8,
    parameter DIGITS = 3,
    parameter DATA_W = 4*DIGITS
)(
    input  wire              clk,
    input  wire              rst_n,       // async, active low
    input  wire              start,       // 1-cycle pulse, accepted only when busy==0
    input  wire [2:0]        mode,
    input  wire [DATA_W-1:0] data_in,
    output wire [DATA_W-1:0] data_out,
    output wire              busy,
    output wire              done,        // 1-cycle pulse, data_out/err valid
    output wire              err
);

    // parameter sanity: BCD field must hold 2^BIN_W-1 and data bus must be wider than BIN_W
    initial begin
        if (DATA_W <= BIN_W || (10**DIGITS) <= ((1 << BIN_W) - 1)) begin
            $display("code_converter_top: illegal BIN_W/DIGITS combination");
            $finish;
        end
    end

    // control <-> datapath nets
    wire       ld_in, ld_sh, sh_step, cnt_clr, cnt_inc, ld_out;
    wire       sh_dir, init_ex3, force_err;
    wire [1:0] in_kind;
    wire [2:0] res_sel;
    wire       cnt_last, bad_in;

    conv_control u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .mode      (mode),
        .busy      (busy),
        .done      (done),
        .cnt_last  (cnt_last),
        .bad_in    (bad_in),
        .ld_in     (ld_in),
        .ld_sh     (ld_sh),
        .sh_step   (sh_step),
        .cnt_clr   (cnt_clr),
        .cnt_inc   (cnt_inc),
        .ld_out    (ld_out),
        .sh_dir    (sh_dir),
        .init_ex3  (init_ex3),
        .force_err (force_err),
        .in_kind   (in_kind),
        .res_sel   (res_sel)
    );

    conv_datapath #(
        .BIN_W  (BIN_W),
        .DIGITS (DIGITS),
        .DATA_W (DATA_W)
    ) u_dp (
        .clk       (clk),
        .rst_n     (rst_n),
        .data_in   (data_in),
        .data_out  (data_out),
        .err       (err),
        .ld_in     (ld_in),
        .ld_sh     (ld_sh),
        .sh_step   (sh_step),
        .cnt_clr   (cnt_clr),
        .cnt_inc   (cnt_inc),
        .ld_out    (ld_out),
        .sh_dir    (sh_dir),
        .init_ex3  (init_ex3),
        .force_err (force_err),
        .in_kind   (in_kind),
        .res_sel   (res_sel),
        .cnt_last  (cnt_last),
        .bad_in    (bad_in)
    );

endmodule
