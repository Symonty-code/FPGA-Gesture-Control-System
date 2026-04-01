`timescale 1ns/ 1ps


module single_tap_tb;

    // Clock
    reg clk = 0;
    always #5 clk = ~clk;

    // DUT signals
    reg rst = 1;
    reg in_valid = 0;
    reg signed [15:0] in_x = 0;
    reg signed [15:0] in_y = 0;
    reg signed [15:0] in_z = 0;

    wire tap_detected;

    // DUT
    single_tap_detector dut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_x(in_x),
        .in_y(in_y),
        .in_z(in_z),
        .tap_detected(tap_detected)
    );

    // PASS / FAIL
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check(input cond, input [255:0] msg);
    begin
        if (cond) begin
            $display("PASS: %s", msg);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: %s", msg);
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    // Apply one sample
    task send_sample(input signed [15:0] x, y, z);
    begin
        @(negedge clk);
        in_x <= x;
        in_y <= y;
        in_z <= z;
        in_valid <= 1;

        @(posedge clk);

        @(negedge clk);
        in_valid <= 0;
    end
    endtask

    // Idle sample
    task idle_sample;
    begin
        @(negedge clk);
        in_valid <= 0;
        @(posedge clk);
    end
    endtask

    // -------------------------------------------------
    // MAIN TEST
    // -------------------------------------------------
    initial begin

        $display("===== SINGLE TAP TEST =====");

        // Reset
        repeat(3) @(posedge clk);
        rst = 0;

        // -----------------------------------------
        // 1) Startup ignore (no trigger)
        // -----------------------------------------
        repeat(25) send_sample(0,0,0);
        check(!tap_detected, "No trigger during startup ignore");

        // -----------------------------------------
        // 2) Valid tap (single spike)
        // -----------------------------------------
        send_sample(0,0,0);
        send_sample(1000,0,0);   // spike
        send_sample(0,0,0);      // quiet
        send_sample(0,0,0);
        send_sample(0,0,0);

        check(tap_detected, "Valid single tap detected");

        // -----------------------------------------
        // 3) Too short spike (reject)
        // -----------------------------------------
        send_sample(1000,0,0);
        send_sample(0,0,0);

        check(!tap_detected, "Short spike rejected");

        // -----------------------------------------
        // 4) Shake (multiple spikes → reject)
        // -----------------------------------------
        send_sample(1000,0,0);
        send_sample(0,0,0);
        send_sample(1000,0,0);   // second spike → shake

        check(!tap_detected, "Multiple spikes rejected as shake");

        // -----------------------------------------
        // 5) Debounce (no re-trigger immediately)
        // -----------------------------------------
        send_sample(1000,0,0);
        send_sample(0,0,0);
        send_sample(0,0,0);
        send_sample(0,0,0);

        check(!tap_detected, "Debounce prevents immediate retrigger");

        // Summary
        $display("PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        $finish;
    end

endmodule