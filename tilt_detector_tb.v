`timescale 1ns / 1ps

module tb_tilt_detector;

    // -------------------------------------------------
    // Clock
    // -------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // -------------------------------------------------
    // Parameters
    // -------------------------------------------------
    localparam THRESHOLD = 16'd500;

    // -------------------------------------------------
    // DUT signals
    // -------------------------------------------------
    reg rst = 1;
    reg in_valid = 0;
    reg signed [15:0] in_x = 0;
    reg signed [15:0] in_y = 0;

    wire tilt_left_cand;
    wire tilt_right_cand;
    wire tilt_forward_cand;
    wire tilt_backward_cand;

    // -------------------------------------------------
    // DUT
    // -------------------------------------------------
    tilt_detector #(
        .THRESHOLD(THRESHOLD)
    ) dut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_x(in_x),
        .in_y(in_y),
        .tilt_left_cand(tilt_left_cand),
        .tilt_right_cand(tilt_right_cand),
        .tilt_forward_cand(tilt_forward_cand),
        .tilt_backward_cand(tilt_backward_cand)
    );

    // -------------------------------------------------
    // PASS / FAIL tracking
    // -------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check(input condition, input [255:0] msg);
    begin
        if (condition) begin
            $display("PASS: %s", msg);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: %s (time=%0t)", msg, $time);
            fail_cnt = fail_cnt + 1;
        end
    end
    endtask

    // -------------------------------------------------
    // Apply one valid input sample
    // -------------------------------------------------
    task apply_sample(input signed [15:0] x, input signed [15:0] y);
    begin
        @(negedge clk);
        in_x <= x;
        in_y <= y;
        in_valid <= 1'b1;

        @(posedge clk);   // sampled here

        @(negedge clk);
        in_valid <= 1'b0;
    end
    endtask

    // -------------------------------------------------
    // Idle cycle
    // -------------------------------------------------
    task idle_cycle;
    begin
        @(negedge clk);
        in_valid <= 1'b0;
        @(posedge clk);
    end
    endtask

    // -------------------------------------------------
    // Main test
    // -------------------------------------------------
    initial begin
        $display("======================================");
        $display(" Testing tilt_detector");
        $display("======================================");

        // Reset
        repeat(3) @(posedge clk);
        rst <= 1'b0;

        // 1) Reset / initial state
        idle_cycle;
        check(!tilt_left_cand && !tilt_right_cand &&
              !tilt_forward_cand && !tilt_backward_cand,
              "All outputs low after reset");

        // 2) Below threshold -> no tilt
        apply_sample(16'sd200, 16'sd100);
        check(!tilt_left_cand && !tilt_right_cand &&
              !tilt_forward_cand && !tilt_backward_cand,
              "No output below threshold");

        // 3) Left tilt: X positive and dominates
        apply_sample(16'sd700, 16'sd200);
        check(tilt_left_cand && !tilt_right_cand &&
              !tilt_forward_cand && !tilt_backward_cand,
              "Left tilt detected for +X dominant");

        // 4) Right tilt: X negative and dominates
        apply_sample(-16'sd800, 16'sd100);
        check(!tilt_left_cand && tilt_right_cand &&
              !tilt_forward_cand && !tilt_backward_cand,
              "Right tilt detected for -X dominant");

        // 5) Forward tilt: Y positive and dominates
        apply_sample(16'sd150, 16'sd900);
        check(!tilt_left_cand && !tilt_right_cand &&
              tilt_forward_cand && !tilt_backward_cand,
              "Forward tilt detected for +Y dominant");

        // 6) Backward tilt: Y negative and dominates
        apply_sample(16'sd100, -16'sd950);
        check(!tilt_left_cand && !tilt_right_cand &&
              !tilt_forward_cand && tilt_backward_cand,
              "Backward tilt detected for -Y dominant");

        // 7) Dominance logic: X and Y both above threshold, X larger
        apply_sample(16'sd850, 16'sd600);
        check(tilt_left_cand && !tilt_right_cand &&
              !tilt_forward_cand && !tilt_backward_cand,
              "X dominance selects left tilt");

        // 8) Dominance logic: X and Y both above threshold, Y larger
        apply_sample(16'sd650, 16'sd900);
        check(!tilt_left_cand && !tilt_right_cand &&
              tilt_forward_cand && !tilt_backward_cand,
              "Y dominance selects forward tilt");

        // 9) Hold behavior check with in_valid=0 -> outputs should not update
        @(negedge clk);
        in_x <= -16'sd900;
        in_y <= 16'sd100;
        in_valid <= 1'b0;
        @(posedge clk);
        check(!tilt_left_cand && !tilt_right_cand &&
              tilt_forward_cand && !tilt_backward_cand,
              "Outputs do not change when in_valid=0");

        // Summary
        $display("======================================");
        $display("RESULTS: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        $display("======================================");

        $finish;
    end

endmodule
