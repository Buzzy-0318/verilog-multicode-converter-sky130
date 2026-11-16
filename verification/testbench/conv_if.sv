//==============================================================================
// conv_if.sv  -  interface to the code converter + protocol assertions
//==============================================================================
`timescale 1ns/1ps

interface conv_if (input logic clk);

    logic        rst_n;
    logic        start;
    logic [2:0]  mode;
    logic [11:0] data_in;
    logic [11:0] data_out;
    logic        busy;
    logic        done;
    logic        err;

    //--------------------------------------------------------------------------
    // Protocol assertions (checked on every posedge, off during reset)
    //--------------------------------------------------------------------------

    // done is a single-cycle pulse
    a_done_pulse : assert property (@(posedge clk) disable iff (!rst_n)
        done |=> !done)
        else $error("[ASSERT] done lasted more than one cycle");

    // done can only be seen while busy
    a_done_busy : assert property (@(posedge clk) disable iff (!rst_n)
        done |-> busy)
        else $error("[ASSERT] done asserted while not busy");

    // start accepted from IDLE -> busy on the next cycle
    a_start_busy : assert property (@(posedge clk) disable iff (!rst_n)
        (start && !busy) |=> busy)
        else $error("[ASSERT] start accepted but busy did not rise");

    // data_out / err only change on the edge that enters DONE
    a_out_stable : assert property (@(posedge clk) disable iff (!rst_n)
        !$rose(done) |-> $stable(data_out))
        else $error("[ASSERT] data_out changed outside of DONE");

    a_err_stable : assert property (@(posedge clk) disable iff (!rst_n)
        !$rose(done) |-> $stable(err))
        else $error("[ASSERT] err changed outside of DONE");

    // an error always reads back as 0 on data_out
    a_err_zero : assert property (@(posedge clk) disable iff (!rst_n)
        err |-> (data_out == 12'h000))
        else $error("[ASSERT] err=1 but data_out != 0");

    // busy must be released the cycle after done
    a_busy_release : assert property (@(posedge clk) disable iff (!rst_n)
        done |=> !busy)
        else $error("[ASSERT] busy did not drop after done");

    // reset values
    a_reset_vals : assert property (@(posedge clk)
        !rst_n |-> (!busy && !done))
        else $error("[ASSERT] busy/done not low during reset");

endinterface
