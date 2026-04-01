`timescale 1ns/1ps

module tb_gesture_debouncer;

    // -------------------------------------------------
    // Clock
    // -------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // =================================================
    // DUT7 : STABLE_SAMPLES = 7
    // =================================================
    localparam STABLE7 = 7;

    reg  rst7, sv7, gc7;
    wire gl7, gp7;

    gesture_debouncer #(.STABLE_SAMPLES(STABLE7)) dut7 (
        .clk          (clk),
        .rst          (rst7),
        .sample_valid (sv7),
        .gesture_cand (gc7),
        .gesture_level(gl7),
        .gesture_pulse(gp7)
    );

    // =================================================
    // TASKS
    // =================================================

    // Clean synchronous sample pulse
    task send7(input cand);
    begin
        @(negedge clk);
        gc7 <= cand;
        sv7 <= 1'b1;

        @(posedge clk);      // sampled here

        @(negedge clk);
        sv7 <= 1'b0;
    end
    endtask

    task idle7;
    begin
        @(negedge clk);
        sv7 <= 1'b0;
        @(posedge clk);
    end
    endtask

    // =================================================
    // PASS / FAIL TRACKING
    // =================================================
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check(input condition,
               input integer test_num,
               input [255:0] msg);
    begin
        if (condition) begin
            $display("PASS [Test %0d]: %s", test_num, msg);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL [Test %0d]: %s (time=%0t)", test_num, msg, $time);
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    // =================================================
    // MAIN TEST SEQUENCE
    // =================================================
    initial begin

        $display("===========================================");
        $display(" Testing gesture_debouncer  STABLE=%0d", STABLE7);
        $display("===========================================");

        rst7 = 1; sv7 = 0; gc7 = 0;

        repeat(3) @(posedge clk);
        rst7 = 0;

        // ---------------------------------------------
        // 1) Reset behavior
        // ---------------------------------------------
        idle7;
        check(!gl7, 1, "Level low after reset");

        // ---------------------------------------------
        // 2) No early trigger (first 6 samples)
        // ---------------------------------------------
        repeat(STABLE7-1) send7(1);   // send 6 samples
        check(!gl7, 2, "No early trigger before 7th sample");
        check(!gp7, 2, "No early pulse");

        // ---------------------------------------------
        // 3) Trigger on 7th sample
        // ---------------------------------------------
        send7(1);   // 7th sample
        check(gl7, 3, "Trigger on 7th valid sample");
        check(gp7, 3, "Pulse fired at threshold");

        // ---------------------------------------------
        // 4) Pulse must be one clock wide
        // ---------------------------------------------
        idle7;
        check(!gp7, 4, "Pulse is one clock wide");

        // ---------------------------------------------
        // 5) Hold high while cand=1
        // ---------------------------------------------
        send7(1);
        send7(1);
        check(gl7, 5, "Level holds high while cand remains 1");
        check(!gp7, 5, "No re-trigger while already high");

        // ---------------------------------------------
        // 6) Drop on cand=0
        // ---------------------------------------------
        send7(0);
        check(!gl7, 6, "Level drops on first valid cand=0 sample");

        // ---------------------------------------------
        // 7) Re-trigger after drop
        // ---------------------------------------------
        repeat(STABLE7) send7(1);
        check(gl7, 7, "Re-trigger works after drop");
        check(gp7, 7, "Pulse fires again after drop");

        // ---------------------------------------------
        // SUMMARY
        // ---------------------------------------------
        $display("===========================================");
        $display("RESULTS: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        $display("===========================================");

        $finish;
    end

endmodule
