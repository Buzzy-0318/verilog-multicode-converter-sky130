//==============================================================================
// conv_datapath.v  -  DATAPATH of the code converter
//
// Registers : in_q (input), sh_q (BCD|BIN shift register), cnt_q (iteration
//             counter), out_q (result), err_q (error flag)
// Functional units (all combinational):
//             bin->gray, gray->bin, BCD +3 / -3 per digit,
//             double-dabble step (add-3 if >=5, shift left),
//             reverse double-dabble step (shift right, sub-3 if >=8),
//             input-legality checker, result mux.
//
// The datapath has NO decision making of its own: every register enable and
// mux select comes from conv_control.  It only reports two status bits back.
//
// Shift register layout (SH_W = DATA_W + BIN_W = 20 for the defaults):
//      [19:8]  BCD field (3 digits)  |  [7:0]  binary field
//   bin -> bcd : load {0, bin};            repeat 8x { add3 digits>=5 ; <<1 }
//   bcd -> bin : load {bcd, 0};            repeat 8x { >>1 ; sub3 digits>=8 }
//                (non-zero BCD field afterwards  <=>  value > 2^BIN_W-1)
//==============================================================================
`timescale 1ns/1ps
`include "code_conv_defs.vh"

module conv_datapath #(
    parameter BIN_W  = 8,               // binary / gray width
    parameter DIGITS = 3,               // BCD digits
    parameter DATA_W = 4*DIGITS         // width of data_in / data_out (must be > BIN_W)
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ---------------- data ----------------
    input  wire [DATA_W-1:0]    data_in,
    output wire [DATA_W-1:0]    data_out,
    output wire                 err,

    // ---------------- control word (from conv_control) ----------------
    input  wire                 ld_in,
    input  wire                 ld_sh,
    input  wire                 sh_step,
    input  wire                 cnt_clr,
    input  wire                 cnt_inc,
    input  wire                 ld_out,
    input  wire                 sh_dir,
    input  wire                 init_ex3,
    input  wire                 force_err,
    input  wire [1:0]           in_kind,
    input  wire [2:0]           res_sel,

    // ---------------- status (to conv_control) ----------------
    output wire                 cnt_last,
    output reg                  bad_in
);

    localparam SH_W  = DATA_W + BIN_W;
    localparam CNT_W = $clog2(BIN_W);

    //--------------------------------------------------------------------------
    // Registers
    //--------------------------------------------------------------------------
    reg [DATA_W-1:0] in_q;
    reg [SH_W-1:0]   sh_q;
    reg [CNT_W-1:0]  cnt_q;
    reg [DATA_W-1:0] out_q;
    reg              err_q;

    //--------------------------------------------------------------------------
    // Functional units
    //--------------------------------------------------------------------------
    function [BIN_W-1:0] f_bin2gray;
        input [BIN_W-1:0] b;
        begin
            f_bin2gray = b ^ (b >> 1);
        end
    endfunction

    function [BIN_W-1:0] f_gray2bin;
        input [BIN_W-1:0] g;
        reg   [BIN_W-1:0] b;
        integer i;
        begin
            b[BIN_W-1] = g[BIN_W-1];
            for (i = BIN_W-2; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            f_gray2bin = b;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Per-digit BCD logic, one slice per decimal digit (generate loop)
    //--------------------------------------------------------------------------
    wire [DATA_W-1:0] bcd_field = sh_q[SH_W-1:BIN_W];
    wire [BIN_W-1:0]  bin_field = sh_q[BIN_W-1:0];

    wire [DATA_W-1:0] bcd_add3;            // bcd_field + 3 per digit        (bin -> ex3)
    wire [DATA_W-1:0] in_sub3;             // in_q      - 3 per digit        (ex3 -> bcd)
    wire [DATA_W-1:0] dab_adj;             // bcd_field, digits>=5 get +3    (double dabble)
    wire [DATA_W-1:0] rdab_adj;            // shifted bcd, digits>=8 get -3  (reverse dabble)
    wire [DIGITS-1:0] dig_not_bcd;         // digit > 9
    wire [DIGITS-1:0] dig_not_ex3;         // digit < 3 or digit > 12

    // reverse dabble first shifts the whole register right by one: the BCD
    // field therefore receives {1'b0, bcd_field[DATA_W-1:1]}
    wire [DATA_W-1:0] bcd_shr = {1'b0, bcd_field[DATA_W-1:1]};

    genvar gi;
    generate
        for (gi = 0; gi < DIGITS; gi = gi + 1) begin : g_digit
            wire [3:0] d_sh  = bcd_field[4*gi +: 4];
            wire [3:0] d_in  = in_q[4*gi +: 4];
            wire [3:0] d_shr = bcd_shr[4*gi +: 4];

            assign bcd_add3[4*gi +: 4] = d_sh + 4'd3;
            assign in_sub3 [4*gi +: 4] = d_in - 4'd3;
            assign dab_adj [4*gi +: 4] = (d_sh  >= 4'd5) ? (d_sh  + 4'd3) : d_sh;
            assign rdab_adj[4*gi +: 4] = (d_shr >= 4'd8) ? (d_shr - 4'd3) : d_shr;

            assign dig_not_bcd[gi] = (d_in > 4'd9);
            assign dig_not_ex3[gi] = (d_in < 4'd3) | (d_in > 4'd12);
        end
    endgenerate

    // next value of the whole shift register
    wire [SH_W-1:0] sh_dabble  = {dab_adj, bin_field} << 1;                         // add3, then <<1
    wire [SH_W-1:0] sh_rdabble = {rdab_adj, bcd_field[0], bin_field[BIN_W-1:1]};   // >>1, then sub3

    //--------------------------------------------------------------------------
    // Status: iteration counter + input legality checker
    //--------------------------------------------------------------------------
    // verilator lint_off WIDTHTRUNC
    localparam [CNT_W-1:0] CNT_LAST = BIN_W-1;
    // verilator lint_on WIDTHTRUNC
    assign cnt_last = (cnt_q == CNT_LAST);

    always @* begin
        case (in_kind)
            `KIND_PLAIN : bad_in = |in_q[DATA_W-1:BIN_W];     // upper bits must be 0
            `KIND_BCD   : bad_in = |dig_not_bcd;
            `KIND_EX3   : bad_in = |dig_not_ex3;
            default     : bad_in = 1'b1;
        endcase
    end

    //--------------------------------------------------------------------------
    // Shift-register preload mux
    //--------------------------------------------------------------------------
    wire [DATA_W-1:0] bcd_src  = init_ex3 ? in_sub3 : in_q;
    wire [SH_W-1:0]   sh_init  = sh_dir ? {bcd_src, {BIN_W{1'b0}}}
                                        : {{DATA_W{1'b0}}, in_q[BIN_W-1:0]};

    //--------------------------------------------------------------------------
    // Result mux + error flag
    //--------------------------------------------------------------------------
    wire              ovf       = |bcd_field;        // after BCD->BIN: value did not fit

    reg  [DATA_W-1:0] result;
    always @* begin
        case (res_sel)
            `RES_GRAY     : result = {{(DATA_W-BIN_W){1'b0}}, f_bin2gray(in_q[BIN_W-1:0])};
            `RES_BIN_GRAY : result = {{(DATA_W-BIN_W){1'b0}}, f_gray2bin(in_q[BIN_W-1:0])};
            `RES_BCD      : result = bcd_field;
            `RES_BIN_SH   : result = {{(DATA_W-BIN_W){1'b0}}, bin_field};
            `RES_EX3      : result = bcd_add3;
            default       : result = {DATA_W{1'b0}};
        endcase
    end

    wire err_next = force_err | bad_in | (sh_dir & ovf);

    //--------------------------------------------------------------------------
    // Sequential part
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_q  <= {DATA_W{1'b0}};
            sh_q  <= {SH_W{1'b0}};
            cnt_q <= {CNT_W{1'b0}};
            out_q <= {DATA_W{1'b0}};
            err_q <= 1'b0;
        end else begin
            if (ld_in)                 in_q <= data_in;

            if (ld_sh)                 sh_q <= sh_init;
            else if (sh_step)          sh_q <= sh_dir ? sh_rdabble : sh_dabble;

            if (cnt_clr)               cnt_q <= {CNT_W{1'b0}};
            else if (cnt_inc)          cnt_q <= cnt_q + 1'b1;

            if (ld_out) begin
                out_q <= err_next ? {DATA_W{1'b0}} : result;   // errors read back as 0
                err_q <= err_next;
            end
        end
    end

    assign data_out = out_q;
    assign err      = err_q;

endmodule
