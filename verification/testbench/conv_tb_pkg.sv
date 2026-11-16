//==============================================================================
// conv_tb_pkg.sv  -  verification environment for the code converter
//
//   conv_txn         one conversion request + its expected result
//   conv_cov         functional-coverage bins (hand-rolled, simulator-neutral)
//   conv_scoreboard  compares every DUT result and latency with ref_model()
//   conv_monitor     passive: watches the pins, builds expected txns, calls sb
//   conv_driver      active : drives start/mode/data_in, applies reset
//   conv_env         owns the above + all test sequences
//
// Drive/sample scheme (race free):  driver changes pins on NEGEDGE clk,
// monitor samples pins on POSEDGE clk (DUT outputs are NBA-updated).
//==============================================================================
`timescale 1ns/1ps

package conv_tb_pkg;

    localparam int unsigned LAT_ITER = 11;   // legal BCD/EX3 conversion
    localparam int unsigned LAT_FAST = 4;    // gray modes, illegal input, reserved mode
    localparam int unsigned TIMEOUT  = 40;   // cycles before the driver gives up on done

    localparam logic [2:0] M_BIN2GRAY = 3'd0,
                           M_GRAY2BIN = 3'd1,
                           M_BIN2BCD  = 3'd2,
                           M_BCD2BIN  = 3'd3,
                           M_BIN2EX3  = 3'd4,
                           M_EX32BIN  = 3'd5;

    function automatic string mode_name(logic [2:0] m);
        case (m)
            3'd0:    return "BIN2GRAY";
            3'd1:    return "GRAY2BIN";
            3'd2:    return "BIN2BCD ";
            3'd3:    return "BCD2BIN ";
            3'd4:    return "BIN2EX3 ";
            3'd5:    return "EX32BIN ";
            default: return "RESERVED";
        endcase
    endfunction

    //--------------------------------------------------------------------------
    // Golden reference model - written with plain arithmetic (/, %, *), i.e.
    // deliberately NOT the same algorithm as the RTL (double-dabble / xor-chain)
    //--------------------------------------------------------------------------
    function automatic void ref_model(input  logic [2:0]  mode,
                                      input  logic [11:0] din,
                                      output logic [11:0] dout,
                                      output bit          err,
                                      output int unsigned lat);
        logic [7:0]  g, b;
        int unsigned v, h, t, u;
        logic [3:0]  d2, d1, d0;

        dout = 12'h000;
        err  = 1'b0;
        lat  = LAT_FAST;
        d2 = din[11:8];  d1 = din[7:4];  d0 = din[3:0];

        case (mode)
            M_BIN2GRAY: begin
                if (din[11:8] != 0) err = 1;
                else dout = {4'b0, din[7:0] ^ (din[7:0] >> 1)};
            end

            M_GRAY2BIN: begin
                if (din[11:8] != 0) err = 1;
                else begin
                    g = din[7:0];  b = g;
                    for (int s = 1; s < 8; s++) b = b ^ (g >> s);   // b[i] = ^g[7:i]
                    dout = {4'b0, b};
                end
            end

            M_BIN2BCD: begin
                if (din[11:8] != 0) err = 1;
                else begin
                    v = din[7:0];  lat = LAT_ITER;
                    h = v / 100;  t = (v / 10) % 10;  u = v % 10;
                    dout = {h[3:0], t[3:0], u[3:0]};
                end
            end

            M_BIN2EX3: begin
                if (din[11:8] != 0) err = 1;
                else begin
                    v = din[7:0];  lat = LAT_ITER;
                    h = v / 100 + 3;  t = (v / 10) % 10 + 3;  u = v % 10 + 3;
                    dout = {h[3:0], t[3:0], u[3:0]};
                end
            end

            M_BCD2BIN: begin
                if (d2 > 9 || d1 > 9 || d0 > 9) err = 1;
                else begin
                    lat = LAT_ITER;
                    v = d2 * 100 + d1 * 10 + d0;
                    if (v > 255) err = 1;                // runs, but overflows 8 bits
                    else         dout = v[11:0];
                end
            end

            M_EX32BIN: begin
                if (d2 < 3 || d2 > 12 || d1 < 3 || d1 > 12 || d0 < 3 || d0 > 12) err = 1;
                else begin
                    lat = LAT_ITER;
                    v = (d2 - 3) * 100 + (d1 - 3) * 10 + (d0 - 3);
                    if (v > 255) err = 1;
                    else         dout = v[11:0];
                end
            end

            default: err = 1;                            // reserved modes
        endcase
    endfunction

    //--------------------------------------------------------------------------
    // Transaction
    //--------------------------------------------------------------------------
    class conv_txn;
        logic [2:0]  mode;
        logic [11:0] din;
        logic [11:0] exp_out;
        bit          exp_err;
        int unsigned exp_lat;

        function new(logic [2:0] m, logic [11:0] d);
            mode = m;  din = d;
            ref_model(m, d, exp_out, exp_err, exp_lat);
        endfunction

        function string sprint();
            return $sformatf("%s din=0x%03h -> exp out=0x%03h err=%0b lat=%0d",
                             mode_name(mode), din, exp_out, exp_err, exp_lat);
        endfunction
    endclass

    //--------------------------------------------------------------------------
    // Functional coverage (simulator-neutral counters)
    //--------------------------------------------------------------------------
    class conv_cov;
        int unsigned ok_hit  [8];
        int unsigned err_hit [8];
        int unsigned ovf_bcd, ovf_ex3;               // legal digits, value > 255
        int unsigned corner_zero, corner_max, corner_alt;

        function void sample(conv_txn t);
            if (t.exp_err) err_hit[t.mode]++; else ok_hit[t.mode]++;
            if (t.exp_err && t.exp_lat == LAT_ITER && t.mode == M_BCD2BIN) ovf_bcd++;
            if (t.exp_err && t.exp_lat == LAT_ITER && t.mode == M_EX32BIN) ovf_ex3++;
            if (t.mode <= M_BIN2EX3) begin
                if (t.din[7:0] == 8'h00) corner_zero++;
                if (t.din[7:0] == 8'hFF) corner_max++;
                if (t.din[7:0] == 8'hAA || t.din[7:0] == 8'h55) corner_alt++;
            end
        endfunction

        function real report();
            int unsigned total = 0, hit = 0;
            $display("\n------------------ FUNCTIONAL COVERAGE ------------------");
            $display(" mode       | legal-input hits | illegal-input hits");
            for (int m = 0; m < 8; m++) begin
                $display(" %s |      %7d     |      %7d", mode_name(m[2:0]), ok_hit[m], err_hit[m]);
                if (m < 6) begin total++; if (ok_hit[m]  > 0) hit++; end   // 6 legal bins
                total++;               if (err_hit[m] > 0) hit++;          // 8 illegal bins
            end
            total += 5;
            if (ovf_bcd     > 0) hit++;
            if (ovf_ex3     > 0) hit++;
            if (corner_zero > 0) hit++;
            if (corner_max  > 0) hit++;
            if (corner_alt  > 0) hit++;
            $display(" BCD value>255 overflow hits : %0d", ovf_bcd);
            $display(" EX3 value>255 overflow hits : %0d", ovf_ex3);
            $display(" corners  zero / 0xFF / 0xAA|0x55 : %0d / %0d / %0d",
                     corner_zero, corner_max, corner_alt);
            $display(" bins hit: %0d / %0d  (%0.1f %%)", hit, total, 100.0 * hit / total);
            $display("---------------------------------------------------------");
            return 100.0 * hit / total;
        endfunction
    endclass

    //--------------------------------------------------------------------------
    // Scoreboard
    //--------------------------------------------------------------------------
    class conv_scoreboard;
        conv_txn     exp_q[$];
        conv_cov     cov;
        int unsigned n_checked = 0;
        int unsigned n_errors  = 0;

        function new(conv_cov c);
            cov = c;
        endfunction

        function void push(conv_txn t);
            exp_q.push_back(t);
            cov.sample(t);
        endfunction

        function void flush();
            exp_q.delete();
        endfunction

        function void note_error(string msg);
            n_errors++;
            $display("[SCB][FAIL] %s", msg);
        endfunction

        function void check(logic [11:0] dout, bit err, int unsigned lat);
            conv_txn t;
            if (exp_q.size() == 0) begin
                note_error("done pulse with no outstanding request");
                return;
            end
            t = exp_q.pop_front();
            n_checked++;
            if (dout !== t.exp_out || err !== t.exp_err)
                note_error($sformatf("%s | got out=0x%03h err=%0b", t.sprint(), dout, err));
            else if (lat != t.exp_lat)
                note_error($sformatf("%s | latency got %0d", t.sprint(), lat));
        endfunction
    endclass

    //--------------------------------------------------------------------------
    // Monitor (passive)
    //--------------------------------------------------------------------------
    class conv_monitor;
        virtual conv_if  vif;
        conv_scoreboard  sb;
        bit              active = 0;
        int unsigned     cnt    = 0;
        int unsigned     n_start = 0, n_done = 0, n_aborted = 0;   // aborted = cancelled by reset

        function new(virtual conv_if v, conv_scoreboard s);
            vif = v;  sb = s;
        endfunction

        task run();
            conv_txn tx;
            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    if (active) n_aborted++;
                    sb.flush();  active = 0;
                end else begin
                    if (active) cnt++;
                    if (vif.done) begin                       // result sample point
                        n_done++;
                        sb.check(vif.data_out, vif.err, cnt);
                        active = 0;
                    end else if (vif.start && !vif.busy) begin // request accepted
                        tx = new(vif.mode, vif.data_in);
                        sb.push(tx);
                        n_start++;
                        active = 1;  cnt = 0;
                    end
                end
            end
        endtask
    endclass

    //--------------------------------------------------------------------------
    // Driver (active)
    //--------------------------------------------------------------------------
    class conv_driver;
        virtual conv_if vif;

        function new(virtual conv_if v);
            vif = v;
        endfunction

        task idle_pins();
            vif.start = 0;  vif.mode = 0;  vif.data_in = 0;
        endtask

        task reset(int cycles = 3);
            vif.rst_n = 0;  idle_pins();
            repeat (cycles) @(negedge vif.clk);
            vif.rst_n = 1;
            @(negedge vif.clk);
        endtask

        // one conversion; returns the result seen on the `done` cycle
        task convert(input  logic [2:0]  m,
                     input  logic [11:0] d,
                     output logic [11:0] q,
                     output bit          e,
                     input  int unsigned gap = 0);
            int unsigned n = 0;
            repeat (gap) @(negedge vif.clk);
            @(negedge vif.clk);
            vif.start = 1;  vif.mode = m;  vif.data_in = d;
            @(negedge vif.clk);
            vif.start = 0;  vif.data_in = $urandom;     // scramble: DUT must have latched it
            vif.mode  = $urandom;
            while (!vif.done && n < TIMEOUT) begin
                @(negedge vif.clk);  n++;
            end
            q = vif.data_out;  e = vif.err;
            if (n >= TIMEOUT) $display("[DRV][FAIL] timeout waiting for done (mode %0d din 0x%03h)", m, d);
        endtask

        // same, but also pokes `start` with different values while busy
        task convert_glitch(input  logic [2:0]  m,  input logic [11:0] d,
                            input  logic [2:0]  gm, input logic [11:0] gd,
                            output logic [11:0] q,  output bit e);
            int unsigned n = 0;
            @(negedge vif.clk);
            vif.start = 1;  vif.mode = m;  vif.data_in = d;
            @(negedge vif.clk);
            vif.start = 0;
            repeat (2) @(negedge vif.clk);
            vif.start = 1;  vif.mode = gm;  vif.data_in = gd;   // must be ignored
            @(negedge vif.clk);
            vif.start = 0;
            while (!vif.done && n < TIMEOUT) begin
                @(negedge vif.clk);  n++;
            end
            q = vif.data_out;  e = vif.err;
        endtask

        // start held high for `hold` cycles with different mode/data each cycle:
        // only the first cycle may be accepted
        task convert_held(input  logic [2:0]  m, input logic [11:0] d,
                          input  int unsigned hold,
                          output logic [11:0] q, output bit e);
            int unsigned n = 0;
            @(negedge vif.clk);
            for (int i = 0; i < hold; i++) begin
                vif.start   = 1;
                vif.mode    = (i == 0) ? m : $urandom;
                vif.data_in = (i == 0) ? d : $urandom;
                @(negedge vif.clk);
            end
            vif.start = 0;
            while (!vif.done && n < TIMEOUT) begin
                @(negedge vif.clk);  n++;
            end
            q = vif.data_out;  e = vif.err;
        endtask

        // a start pulse exactly in the DONE cycle (busy=1) must be ignored
        task convert_start_in_done(input  logic [2:0]  m, input logic [11:0] d,
                                   output logic [11:0] q, output bit e);
            int unsigned n = 0;
            @(negedge vif.clk);
            vif.start = 1;  vif.mode = m;  vif.data_in = d;
            @(negedge vif.clk);
            vif.start = 0;
            while (!vif.done && n < TIMEOUT) begin
                @(negedge vif.clk);  n++;
            end
            q = vif.data_out;  e = vif.err;
            vif.start = 1;  vif.mode = $urandom;  vif.data_in = $urandom;   // in the DONE cycle
            @(negedge vif.clk);
            vif.start = 0;
        endtask
    endclass

    //--------------------------------------------------------------------------
    // Environment + test sequences
    //--------------------------------------------------------------------------
    class conv_env;
        virtual conv_if  vif;
        conv_driver      drv;
        conv_monitor     mon;
        conv_scoreboard  sb;
        conv_cov         cov;
        int unsigned     n_self_errors = 0;   // failures found by the tests themselves

        function new(virtual conv_if v);
            vif = v;
            cov = new();
            sb  = new(cov);
            mon = new(v, sb);
            drv = new(v);
        endfunction

        // ---- self-check helper for tests that compare explicit values --------
        function void test_fail(string msg);
            n_self_errors++;
            $display("[TEST][FAIL] %s", msg);
        endfunction

        task expect_conv(string name, logic [2:0] m, logic [11:0] d,
                         logic [11:0] exp_q, bit exp_e);
            logic [11:0] q;  bit e;
            drv.convert(m, d, q, e);
            if (q !== exp_q || e !== exp_e)
                test_fail($sformatf("%s: %s din=0x%03h expected out=0x%03h err=%0b, got out=0x%03h err=%0b",
                                    name, mode_name(m), d, exp_q, exp_e, q, e));
            else
                $display("[DIRECTED] %-22s %s 0x%03h -> 0x%03h err=%0b  ok", name, mode_name(m), d, q, e);
        endtask

        //----------------------------------------------------------------------
        // TEST 1 : reset behaviour
        //----------------------------------------------------------------------
        task test_reset();
            $display("\n=== TEST 1: reset ===");
            drv.reset(3);
            if (vif.busy !== 0 || vif.done !== 0 || vif.err !== 0 || vif.data_out !== 12'h000)
                test_fail("outputs not at reset values after reset");
        endtask

        //----------------------------------------------------------------------
        // TEST 2 : directed vectors with hand-computed expected values
        //----------------------------------------------------------------------
        task test_directed();
            $display("\n=== TEST 2: directed (hand-computed expectations) ===");
            //                name                    mode        din    exp_out  exp_err
            expect_conv("zero",               M_BIN2GRAY, 12'h000, 12'h000, 0);
            expect_conv("bin 0x01 gray",      M_BIN2GRAY, 12'h001, 12'h001, 0);
            expect_conv("bin 0x02 gray",      M_BIN2GRAY, 12'h002, 12'h003, 0);
            expect_conv("bin 0xFF gray",      M_BIN2GRAY, 12'h0FF, 12'h080, 0);
            expect_conv("bin 0x80 gray",      M_BIN2GRAY, 12'h080, 12'h0C0, 0);
            expect_conv("gray 0x80 bin",      M_GRAY2BIN, 12'h080, 12'h0FF, 0);
            expect_conv("gray 0x0C bin",      M_GRAY2BIN, 12'h00C, 12'h008, 0);
            expect_conv("bin 0 bcd",          M_BIN2BCD,  12'h000, 12'h000, 0);
            expect_conv("bin 9 bcd",          M_BIN2BCD,  12'h009, 12'h009, 0);
            expect_conv("bin 10 bcd",         M_BIN2BCD,  12'h00A, 12'h010, 0);
            expect_conv("bin 99 bcd",         M_BIN2BCD,  12'h063, 12'h099, 0);
            expect_conv("bin 100 bcd",        M_BIN2BCD,  12'h064, 12'h100, 0);
            expect_conv("bin 255 bcd",        M_BIN2BCD,  12'h0FF, 12'h255, 0);
            expect_conv("bcd 255 bin",        M_BCD2BIN,  12'h255, 12'h0FF, 0);
            expect_conv("bcd 128 bin",        M_BCD2BIN,  12'h128, 12'h080, 0);
            expect_conv("bcd 000 bin",        M_BCD2BIN,  12'h000, 12'h000, 0);
            expect_conv("bin 0 ex3",          M_BIN2EX3,  12'h000, 12'h333, 0);
            expect_conv("bin 255 ex3",        M_BIN2EX3,  12'h0FF, 12'h588, 0);
            expect_conv("bin 100 ex3",        M_BIN2EX3,  12'h064, 12'h433, 0);
            expect_conv("ex3 588 bin",        M_EX32BIN,  12'h588, 12'h0FF, 0);
            expect_conv("ex3 333 bin",        M_EX32BIN,  12'h333, 12'h000, 0);
            expect_conv("ex3 456 bin",        M_EX32BIN,  12'h456, 12'h07B, 0);   // digits 1,2,3 -> 123 = 0x7B
        endtask

        //----------------------------------------------------------------------
        // TEST 3 : error handling (illegal inputs, overflow, reserved modes)
        //----------------------------------------------------------------------
        task test_errors();
            $display("\n=== TEST 3: error cases ===");
            expect_conv("bcd digit A",        M_BCD2BIN,  12'h0A0, 12'h000, 1);
            expect_conv("bcd digit F low",    M_BCD2BIN,  12'h00F, 12'h000, 1);
            expect_conv("bcd 256 overflow",   M_BCD2BIN,  12'h256, 12'h000, 1);
            expect_conv("bcd 999 overflow",   M_BCD2BIN,  12'h999, 12'h000, 1);
            expect_conv("ex3 digit 2",        M_EX32BIN,  12'h332, 12'h000, 1);
            expect_conv("ex3 digit D",        M_EX32BIN,  12'hD33, 12'h000, 1);
            expect_conv("ex3 256 overflow",   M_EX32BIN,  12'h589, 12'h000, 1);   // digits 2,5,6 -> 256 > 255
            expect_conv("ex3 999 overflow",   M_EX32BIN,  12'hCCC, 12'h000, 1);
            expect_conv("bin upper bits",     M_BIN2GRAY, 12'h100, 12'h000, 1);
            expect_conv("gray upper bits",    M_GRAY2BIN, 12'h800, 12'h000, 1);
            expect_conv("bin2bcd upper bits", M_BIN2BCD,  12'h123, 12'h000, 1);
            expect_conv("bin2ex3 upper bits", M_BIN2EX3,  12'hF00, 12'h000, 1);
            expect_conv("reserved mode 6",    3'd6,       12'h012, 12'h000, 1);
            expect_conv("reserved mode 7",    3'd7,       12'h0FF, 12'h000, 1);
            // after an error the converter must still work
            expect_conv("recover after err",  M_BIN2BCD,  12'h0FF, 12'h255, 0);
        endtask

        //----------------------------------------------------------------------
        // TEST 4 : EXHAUSTIVE - every mode (0..7) x every 12-bit input (4096)
        //          Results are checked by the monitor/scoreboard vs ref_model.
        //----------------------------------------------------------------------
        task test_exhaustive();
            logic [11:0] q;  bit e;
            $display("\n=== TEST 4: exhaustive, 8 modes x 4096 inputs = 32768 conversions ===");
            for (int m = 0; m < 8; m++)
                for (int d = 0; d < 4096; d++)
                    drv.convert(m[2:0], d[11:0], q, e);
        endtask

        //----------------------------------------------------------------------
        // TEST 5 : round trip  X -> Y -> X  must return the original value
        //----------------------------------------------------------------------
        task test_roundtrip();
            logic [11:0] a, b;  bit e1, e2;
            $display("\n=== TEST 5: round trips for all 256 binary values ===");
            for (int v = 0; v < 256; v++) begin
                drv.convert(M_BIN2GRAY, v[11:0], a, e1);  drv.convert(M_GRAY2BIN, a, b, e2);
                if (e1 || e2 || b !== v[11:0]) test_fail($sformatf("gray round trip failed for %0d", v));
                drv.convert(M_BIN2BCD,  v[11:0], a, e1);  drv.convert(M_BCD2BIN,  a, b, e2);
                if (e1 || e2 || b !== v[11:0]) test_fail($sformatf("bcd round trip failed for %0d", v));
                drv.convert(M_BIN2EX3,  v[11:0], a, e1);  drv.convert(M_EX32BIN,  a, b, e2);
                if (e1 || e2 || b !== v[11:0]) test_fail($sformatf("ex3 round trip failed for %0d", v));
            end
        endtask

        //----------------------------------------------------------------------
        // TEST 6 : constrained-random mode/data with random idle gaps
        //----------------------------------------------------------------------
        task test_random(int unsigned n);
            logic [11:0] q;  bit e;  logic [2:0] m;  logic [11:0] d;
            $display("\n=== TEST 6: %0d random transactions with random gaps ===", n);
            repeat (n) begin
                m = ($urandom_range(0, 9) < 8) ? $urandom_range(0, 5) : $urandom_range(6, 7);
                case ($urandom_range(0, 3))
                    0:       d = $urandom_range(0, 255);                            // legal binary
                    1:       d = {4'($urandom_range(0,2)), 4'($urandom_range(0,9)), 4'($urandom_range(0,9))};
                    2:       d = {4'($urandom_range(3,5)), 4'($urandom_range(3,12)), 4'($urandom_range(3,12))};
                    default: d = $urandom;                                          // anything
                endcase
                drv.convert(m, d, q, e, $urandom_range(0, 4));
            end
        endtask

        //----------------------------------------------------------------------
        // TEST 7 : start while busy must be ignored
        //----------------------------------------------------------------------
        task test_start_while_busy();
            logic [11:0] q;  bit e;
            $display("\n=== TEST 7: start pulse while busy is ignored ===");
            drv.convert_glitch(M_BIN2BCD, 12'h0C8, M_BIN2GRAY, 12'h0FF, q, e);      // 200 dec
            if (q !== 12'h200 || e) test_fail($sformatf("busy-start corrupted result: 0x%03h err=%0b", q, e));
            drv.convert_glitch(M_BCD2BIN, 12'h199, M_BIN2EX3, 12'h001, q, e);
            if (q !== 12'h0C7 || e) test_fail($sformatf("busy-start corrupted result: 0x%03h err=%0b", q, e));
            repeat (3) @(negedge vif.clk);
        endtask

        //----------------------------------------------------------------------
        // TEST 7b: start held high / start in the DONE cycle
        //----------------------------------------------------------------------
        task test_start_edge_cases();
            logic [11:0] q;  bit e;
            $display("\n=== TEST 7b: start held for several cycles / start during DONE ===");
            for (int hold = 1; hold <= 4; hold++) begin
                drv.convert_held(M_BIN2BCD, 12'h07B, hold, q, e);               // 123 dec
                if (q !== 12'h123 || e) test_fail($sformatf("held start (%0d cycles) corrupted result 0x%03h err=%0b", hold, q, e));
                repeat (2) @(negedge vif.clk);
            end
            for (int i = 0; i < 6; i++) begin
                drv.convert_start_in_done(i[2:0], 12'h0A5, q, e);
                repeat (3) @(negedge vif.clk);
                if (vif.busy !== 0 || vif.done !== 0)
                    test_fail("start in DONE cycle caused a spurious second conversion");
            end
        endtask

        //----------------------------------------------------------------------
        // TEST 8 : asynchronous reset in the middle of a conversion
        //----------------------------------------------------------------------
        task test_reset_midway();
            logic [11:0] q;  bit e;
            $display("\n=== TEST 8: reset in the middle of a conversion ===");
            @(negedge vif.clk);
            vif.start = 1;  vif.mode = M_BIN2BCD;  vif.data_in = 12'h0F0;
            @(negedge vif.clk);
            vif.start = 0;
            repeat (4) @(negedge vif.clk);              // now inside EXEC
            if (!vif.busy) test_fail("expected busy before mid-conversion reset");
            vif.rst_n = 0;
            @(negedge vif.clk);
            if (vif.busy !== 0 || vif.done !== 0) test_fail("busy/done not cleared by reset");
            @(negedge vif.clk);
            vif.rst_n = 1;
            repeat (2) @(negedge vif.clk);
            if (vif.done !== 0) test_fail("spurious done after reset");
            expect_conv("works after reset",  M_BIN2BCD, 12'h0F0, 12'h240, 0);       // 240 dec
        endtask

        //----------------------------------------------------------------------
        // run everything
        //----------------------------------------------------------------------
        task run_all();
            real cov_pct;
            fork mon.run(); join_none

            drv.idle_pins();
            test_reset();
            test_directed();
            test_errors();
            test_exhaustive();
            test_roundtrip();
            test_random(3000);
            test_start_while_busy();
            test_start_edge_cases();
            test_reset_midway();

            repeat (5) @(negedge vif.clk);

            cov_pct = cov.report();

            $display("\n================= SUMMARY =================");
            $display(" transactions accepted by DUT : %0d", mon.n_start);
            $display(" results checked by scoreboard : %0d", sb.n_checked);
            $display(" requests aborted by reset    : %0d", mon.n_aborted);
            $display(" scoreboard mismatches        : %0d", sb.n_errors);
            $display(" test self-check failures     : %0d", n_self_errors);
            $display(" pending (unchecked) requests : %0d", sb.exp_q.size());
            $display(" functional coverage          : %0.1f %%", cov_pct);
            if (sb.n_errors == 0 && n_self_errors == 0 && sb.exp_q.size() == 0 &&
                mon.n_start == mon.n_done + mon.n_aborted && cov_pct > 99.9)
                $display(" *** TEST PASSED ***");
            else
                $display(" *** TEST FAILED ***");
            $display("===========================================\n");
        endtask
    endclass

endpackage
