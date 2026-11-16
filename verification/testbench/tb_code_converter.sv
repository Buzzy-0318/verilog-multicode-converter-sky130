//==============================================================================
// tb_code_converter.sv  -  testbench top: clock, DUT, interface, test launch
//==============================================================================
`timescale 1ns/1ps

module tb_code_converter;
    import conv_tb_pkg::*;

    // ---------------- clock ----------------
    logic clk = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz

    // ---------------- interface + DUT ----------------
    conv_if vif (.clk(clk));

    code_converter_top #(.BIN_W(8), .DIGITS(3)) dut (
        .clk      (clk),
        .rst_n    (vif.rst_n),
        .start    (vif.start),
        .mode     (vif.mode),
        .data_in  (vif.data_in),
        .data_out (vif.data_out),
        .busy     (vif.busy),
        .done     (vif.done),
        .err      (vif.err)
    );

    // ---------------- test ----------------
    initial begin : main
        conv_env env;
        // drive known values before time 0 activity of the DUT
        vif.rst_n   = 1'b0;
        vif.start   = 1'b0;
        vif.mode    = 3'd0;
        vif.data_in = 12'd0;

        env = new(vif);
        env.run_all();
        $finish;
    end

    // ---------------- watchdog ----------------
    initial begin : watchdog
        #50_000_000;
        $display("[TB] WATCHDOG TIMEOUT");
        $display(" *** TEST FAILED ***");
        $finish;
    end

    // optional waveform dump:  +define+DUMP_VCD
`ifdef DUMP_VCD
    initial begin
        $dumpfile("code_converter.vcd");
        $dumpvars(0, tb_code_converter);
    end
`endif
endmodule
