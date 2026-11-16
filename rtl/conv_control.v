//==============================================================================
// conv_control.v  -  CONTROL PATH of the code converter
//
// An FSM that sequences the datapath.  It owns:
//   * the mode register  (what the user asked for)
//   * the opcode decoder (mode -> datapath control word)
//   * the FSM            (IDLE -> INIT -> EXEC (xN) -> STORE -> DONE)
// It listens to two status flags from the datapath (cnt_last, bad_in).
//
// Handshake: pulse `start` for one cycle while busy==0 (mode/data_in are
// sampled on that cycle).  `done` is a one-cycle pulse; data_out/err are valid
// while done=1 and stay held until the next conversion completes.
//
// Latency (clock edges from the edge that samples start to the edge that
// samples done=1):   iterative modes (BCD/EX3, legal input) : 11
//                    gray modes, illegal input, reserved mode :  4
//==============================================================================
`timescale 1ns/1ps
`include "code_conv_defs.vh"

module conv_control (
    input  wire       clk,
    input  wire       rst_n,        // async, active low

    // ---------------- user interface ----------------
    input  wire       start,
    input  wire [2:0] mode,
    output wire       busy,
    output wire       done,

    // ---------------- status  (datapath -> control) ----------------
    input  wire       cnt_last,     // iteration counter reached BIN_W-1
    input  wire       bad_in,       // input register holds an illegal code

    // ---------------- control word (control -> datapath) ----------------
    output reg        ld_in,        // capture data_in into input register
    output reg        ld_sh,        // initialise shift register
    output reg        sh_step,      // one double-dabble / reverse-dabble step
    output reg        cnt_clr,      // clear iteration counter
    output reg        cnt_inc,      // increment iteration counter
    output reg        ld_out,       // capture result + error flag in output regs
    output wire       sh_dir,       // 0: bin->bcd (shift left)  1: bcd->bin (shift right)
    output wire       init_ex3,     // 1: convert excess-3 -> BCD while loading
    output wire       force_err,    // reserved mode selected
    output reg  [1:0] in_kind,      // legality check to apply to input register
    output reg  [2:0] res_sel       // result mux select
);

    // ---------------- state encoding ----------------
    localparam [2:0] S_IDLE  = 3'd0,
                     S_INIT  = 3'd1,
                     S_EXEC  = 3'd2,
                     S_STORE = 3'd3,
                     S_DONE  = 3'd4;

    reg [2:0] state, next;
    reg [2:0] mode_q;               // latched copy of `mode`

    // ---------------- mode register ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                         mode_q <= 3'd0;
        else if (state == S_IDLE && start)  mode_q <= mode;
    end

    // ---------------- opcode decoder ----------------
    wire is_bin2bcd = (mode_q == `MODE_BIN2BCD);
    wire is_bcd2bin = (mode_q == `MODE_BCD2BIN);
    wire is_bin2ex3 = (mode_q == `MODE_BIN2EX3);
    wire is_ex32bin = (mode_q == `MODE_EX32BIN);

    wire iterative  = is_bin2bcd | is_bcd2bin | is_bin2ex3 | is_ex32bin;
    wire bad_mode   = (mode_q == 3'b110) | (mode_q == 3'b111);
    wire abort      = bad_in | bad_mode;       // skip EXEC, report error

    assign sh_dir    = is_bcd2bin | is_ex32bin;
    assign init_ex3  = is_ex32bin;
    assign force_err = bad_mode;

    always @* begin
        case (mode_q)
            `MODE_BIN2GRAY : begin res_sel = `RES_GRAY;     in_kind = `KIND_PLAIN; end
            `MODE_GRAY2BIN : begin res_sel = `RES_BIN_GRAY; in_kind = `KIND_PLAIN; end
            `MODE_BIN2BCD  : begin res_sel = `RES_BCD;      in_kind = `KIND_PLAIN; end
            `MODE_BCD2BIN  : begin res_sel = `RES_BIN_SH;   in_kind = `KIND_BCD;   end
            `MODE_BIN2EX3  : begin res_sel = `RES_EX3;      in_kind = `KIND_PLAIN; end
            `MODE_EX32BIN  : begin res_sel = `RES_BIN_SH;   in_kind = `KIND_EX3;   end
            default        : begin res_sel = `RES_GRAY;     in_kind = `KIND_PLAIN; end
        endcase
    end

    // ---------------- state register ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next;
    end

    // ---------------- next-state + control-word logic ----------------
    always @* begin
        ld_in   = 1'b0;
        ld_sh   = 1'b0;
        sh_step = 1'b0;
        cnt_clr = 1'b0;
        cnt_inc = 1'b0;
        ld_out  = 1'b0;
        next    = state;

        case (state)
            S_IDLE : if (start) begin
                         ld_in = 1'b1;               // grab data_in this cycle
                         next  = S_INIT;
                     end

            S_INIT : begin                           // preload shift reg, clear counter
                         ld_sh   = 1'b1;
                         cnt_clr = 1'b1;
                         next    = S_EXEC;
                     end

            S_EXEC : begin
                         if (abort)
                             next = S_STORE;         // illegal input: no work, flag error
                         else if (iterative) begin
                             sh_step = 1'b1;
                             cnt_inc = 1'b1;
                             if (cnt_last) next = S_STORE;
                         end
                         else
                             next = S_STORE;         // gray modes are purely combinational
                     end

            S_STORE: begin
                         ld_out = 1'b1;
                         next   = S_DONE;
                     end

            S_DONE : next = S_IDLE;

            default: next = S_IDLE;
        endcase
    end

    assign busy = (state != S_IDLE);
    assign done = (state == S_DONE);

endmodule
