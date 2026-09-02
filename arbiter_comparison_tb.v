`timescale 1ns/1ps

// Quantitative Experiment-B testbench.
//
// Purpose:
//   Compare PRE-ARBITRATION detector candidate events against
//   POST-ARBITRATION command emissions using exactly the same conflict stimuli.
//
// Important interpretation:
//   - This is an ablation/regression experiment, not a second human-subject test.
//   - "Pre-arbitration" means every rising detector event is treated as a
//     candidate command event before arbitration.
//   - "Post-arbitration" means the command actually accepted by
//     gesture_uart_bridge (dut.uart_send / dut.uart_data).
//
// Five conflict scenarios are repeated 10 times each (50 gesture episodes
// in simulation):
//   1) directional gesture with detector-tail chatter
//   2) shake with tap/direction tail chatter
//   3) tap-like transient developing into shake
//   4) backward-tilt transient developing into flip
//   5) tap + backward transients developing into flip
//
// Expected raw candidates per 5-scenario round = 4+3+2+2+3 = 14.
// Expected intended commands per round = 5.
// Over 10 rounds: 140 raw candidates for 50 intended episodes.

module arbiter_comparison_tb;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg tilt_left_level = 1'b0;
    reg tilt_right_level = 1'b0;
    reg tilt_forward_level = 1'b0;
    reg tilt_backward_level = 1'b0;
    reg tap_signal = 1'b0;
    reg shake_level = 1'b0;
    reg flip_signal = 1'b0;
    reg flip_candidate = 1'b0;

    wire uart_tx_out;

    // 4 MHz clock => 250 ns period.
    always #125 clk = ~clk;

    // Fast simulation parameters only. Production defaults are unchanged.
    localparam integer SIM_CLKS_PER_BIT      = 4;
    localparam integer SIM_REARM_CLKS        = 5;
    localparam integer SIM_TAP_GUARD         = 12;
    localparam integer SIM_DIR_GUARD         = 10;
    localparam integer SIM_FLIP_WAIT_TIMEOUT = 40;
    localparam integer SIM_TILT_LOCKOUT      = 8;
    localparam integer SIM_TAP_LOCKOUT       = 14;
    localparam integer SIM_SHAKE_LOCKOUT     = 24;
    localparam integer SIM_FLIP_LOCKOUT      = 24;

    gesture_uart_bridge #(
        .UART_CLKS_PER_BIT(SIM_CLKS_PER_BIT),
        .REARM_CLKS(SIM_REARM_CLKS),
        .TAP_GUARD_CLKS(SIM_TAP_GUARD),
        .DIR_GUARD_CLKS(SIM_DIR_GUARD),
        .FLIP_WAIT_TIMEOUT_CLKS(SIM_FLIP_WAIT_TIMEOUT),
        .TILT_LOCKOUT_CLKS(SIM_TILT_LOCKOUT),
        .TAP_LOCKOUT_CLKS(SIM_TAP_LOCKOUT),
        .SHAKE_LOCKOUT_CLKS(SIM_SHAKE_LOCKOUT),
        .FLIP_LOCKOUT_CLKS(SIM_FLIP_LOCKOUT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .tilt_left_level(tilt_left_level),
        .tilt_right_level(tilt_right_level),
        .tilt_forward_level(tilt_forward_level),
        .tilt_backward_level(tilt_backward_level),
        .tap_signal(tap_signal),
        .shake_level(shake_level),
        .flip_signal(flip_signal),
        .flip_candidate(flip_candidate),
        .uart_tx_out(uart_tx_out)
    );

    // Independent PRE-arbitration rising-edge counter.
    reg raw_prev_left = 1'b0;
    reg raw_prev_right = 1'b0;
    reg raw_prev_forward = 1'b0;
    reg raw_prev_backward = 1'b0;
    reg raw_prev_tap = 1'b0;
    reg raw_prev_shake = 1'b0;
    reg raw_prev_flip = 1'b0;

    integer raw_candidate_count = 0;
    integer arbiter_command_count = 0;
    integer arbiter_correct_episodes = 0;
    integer total_episodes = 0;
    integer failed_episodes = 0;

    integer raw_dir_chatter = 0;
    integer raw_shake_chatter = 0;
    integer raw_tap_shake = 0;
    integer raw_backward_flip = 0;
    integer raw_tap_backward_flip = 0;

    integer post_dir_chatter = 0;
    integer post_shake_chatter = 0;
    integer post_tap_shake = 0;
    integer post_backward_flip = 0;
    integer post_tap_backward_flip = 0;

    reg [7:0] last_command = 8'h00;

    always @(posedge clk) begin
        if (rst) begin
            raw_candidate_count <= 0;
            raw_prev_left     <= 1'b0;
            raw_prev_right    <= 1'b0;
            raw_prev_forward  <= 1'b0;
            raw_prev_backward <= 1'b0;
            raw_prev_tap      <= 1'b0;
            raw_prev_shake    <= 1'b0;
            raw_prev_flip     <= 1'b0;
        end else begin
            // One accumulated assignment is required because more than one
            // detector can rise on the same cycle (e.g. shake + right tail).
            raw_candidate_count <= raw_candidate_count
                + ((tilt_left_level     && !raw_prev_left)     ? 1 : 0)
                + ((tilt_right_level    && !raw_prev_right)    ? 1 : 0)
                + ((tilt_forward_level  && !raw_prev_forward)  ? 1 : 0)
                + ((tilt_backward_level && !raw_prev_backward) ? 1 : 0)
                + ((tap_signal          && !raw_prev_tap)      ? 1 : 0)
                + ((shake_level         && !raw_prev_shake)    ? 1 : 0)
                + ((flip_signal         && !raw_prev_flip)     ? 1 : 0);

            raw_prev_left     <= tilt_left_level;
            raw_prev_right    <= tilt_right_level;
            raw_prev_forward  <= tilt_forward_level;
            raw_prev_backward <= tilt_backward_level;
            raw_prev_tap      <= tap_signal;
            raw_prev_shake    <= shake_level;
            raw_prev_flip     <= flip_signal;
        end

        if (!rst && dut.uart_send) begin
            arbiter_command_count <= arbiter_command_count + 1;
            last_command <= dut.uart_data;
        end
    end

    task wait_for_full_rearm;
        begin
            repeat (120) @(posedge clk);
        end
    endtask

    // Scenario 1: intended LEFT, with tap/shake/right detector tails.
    // Raw candidate events: L, T, S, R => 4.
    task left_with_tail_chatter;
        begin
            @(negedge clk); tilt_left_level = 1'b1;
            repeat (2) @(posedge clk);

            @(negedge clk); tap_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk); tap_signal = 1'b0;

            @(negedge clk);
            shake_level = 1'b1;
            tilt_right_level = 1'b1;
            repeat (14) @(posedge clk);
            @(negedge clk);
            shake_level = 1'b0;
            tilt_right_level = 1'b0;
            tilt_left_level = 1'b0;
        end
    endtask

    // Scenario 2: intended SHAKE, with tap/backward detector tails.
    // Raw candidate events: S, T, D => 3.
    task shake_with_tail_chatter;
        begin
            @(negedge clk); shake_level = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            tap_signal = 1'b1;
            tilt_backward_level = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            tap_signal = 1'b0;
            tilt_backward_level = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk); shake_level = 1'b0;
        end
    endtask

    // Scenario 3: intended SHAKE, but an early tap-like transient appears.
    // Raw candidate events: T, S => 2.
    task tap_then_shake;
        begin
            @(negedge clk); tap_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk); tap_signal = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk); shake_level = 1'b1;
            repeat (10) @(posedge clk);
            @(negedge clk); shake_level = 1'b0;
        end
    endtask

    // Scenario 4: intended FLIP, but backward tilt appears first.
    // Raw candidate events: D, F => 2. flip_candidate is an arbitration hint,
    // not a command candidate, so it is intentionally not counted as raw.
    task backward_then_flip_candidate;
        begin
            @(negedge clk); tilt_backward_level = 1'b1;
            repeat (3) @(posedge clk);

            @(negedge clk); flip_candidate = 1'b1;
            repeat (5) @(posedge clk);

            @(negedge clk); flip_signal = 1'b1;
            repeat (2) @(posedge clk);

            @(negedge clk);
            flip_signal = 1'b0;
            flip_candidate = 1'b0;
            tilt_backward_level = 1'b0;
        end
    endtask

    // Scenario 5: intended FLIP, but tap then backward tilt appear first.
    // Raw candidate events: T, D, F => 3.
    task tap_backward_then_flip_candidate;
        begin
            @(negedge clk); tap_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk); tap_signal = 1'b0;

            repeat (3) @(posedge clk);
            @(negedge clk); tilt_backward_level = 1'b1;
            repeat (3) @(posedge clk);

            @(negedge clk); flip_candidate = 1'b1;
            repeat (5) @(posedge clk);

            @(negedge clk); flip_signal = 1'b1;
            repeat (2) @(posedge clk);

            @(negedge clk);
            flip_signal = 1'b0;
            flip_candidate = 1'b0;
            tilt_backward_level = 1'b0;
        end
    endtask

    task verify_episode;
        input [7:0] expected_command;
        input integer raw_before;
        input integer out_before;
        input integer expected_raw_delta;
        begin
            wait_for_full_rearm();
            total_episodes = total_episodes + 1;

            if ((raw_candidate_count - raw_before) !== expected_raw_delta) begin
                $display("FAIL: raw-event delta expected %0d, got %0d",
                         expected_raw_delta, raw_candidate_count - raw_before);
                failed_episodes = failed_episodes + 1;
            end

            if ((arbiter_command_count - out_before) !== 1) begin
                $display("FAIL: arbiter emitted %0d commands for one intended episode",
                         arbiter_command_count - out_before);
                failed_episodes = failed_episodes + 1;
            end else if (last_command !== expected_command) begin
                $display("FAIL: expected post-arbiter %c, got %c",
                         expected_command, last_command);
                failed_episodes = failed_episodes + 1;
            end else begin
                arbiter_correct_episodes = arbiter_correct_episodes + 1;
            end
        end
    endtask

    integer round_idx;
    integer rb;
    integer ob;
    integer raw_extra;
    integer post_unwanted;
    real suppression_pct;

    initial begin
        #12000000;
        $display("FAIL: simulation timeout");
        $fatal;
    end

    initial begin
        repeat (8) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        repeat (6) @(posedge clk);

        $display("============================================================");
        $display("EXPERIMENT B: PRE-ARBITRATION vs POST-ARBITRATION");
        $display("50 controlled conflict episodes (5 scenarios x 10 rounds)");
        $display("============================================================");

        for (round_idx = 1; round_idx <= 10; round_idx = round_idx + 1) begin

            rb = raw_candidate_count; ob = arbiter_command_count;
            left_with_tail_chatter();
            verify_episode("L", rb, ob, 4);
            raw_dir_chatter = raw_dir_chatter + (raw_candidate_count - rb);
            post_dir_chatter = post_dir_chatter + (arbiter_command_count - ob);

            rb = raw_candidate_count; ob = arbiter_command_count;
            shake_with_tail_chatter();
            verify_episode("S", rb, ob, 3);
            raw_shake_chatter = raw_shake_chatter + (raw_candidate_count - rb);
            post_shake_chatter = post_shake_chatter + (arbiter_command_count - ob);

            rb = raw_candidate_count; ob = arbiter_command_count;
            tap_then_shake();
            verify_episode("S", rb, ob, 2);
            raw_tap_shake = raw_tap_shake + (raw_candidate_count - rb);
            post_tap_shake = post_tap_shake + (arbiter_command_count - ob);

            rb = raw_candidate_count; ob = arbiter_command_count;
            backward_then_flip_candidate();
            verify_episode("F", rb, ob, 2);
            raw_backward_flip = raw_backward_flip + (raw_candidate_count - rb);
            post_backward_flip = post_backward_flip + (arbiter_command_count - ob);

            rb = raw_candidate_count; ob = arbiter_command_count;
            tap_backward_then_flip_candidate();
            verify_episode("F", rb, ob, 3);
            raw_tap_backward_flip = raw_tap_backward_flip + (raw_candidate_count - rb);
            post_tap_backward_flip = post_tap_backward_flip + (arbiter_command_count - ob);
        end

        raw_extra = raw_candidate_count - total_episodes;
        post_unwanted = arbiter_command_count - arbiter_correct_episodes;

        if (raw_extra > 0)
            suppression_pct = 100.0 * (raw_extra - post_unwanted) / raw_extra;
        else
            suppression_pct = 0.0;

        $display("");
        $display("---------------- SCENARIO TOTALS ----------------");
        $display("Scenario                         PRE raw   POST commands");
        $display("Directional tail chatter         %0d        %0d", raw_dir_chatter, post_dir_chatter);
        $display("Shake tail chatter               %0d        %0d", raw_shake_chatter, post_shake_chatter);
        $display("Tap transient -> shake           %0d        %0d", raw_tap_shake, post_tap_shake);
        $display("Backward transient -> flip       %0d        %0d", raw_backward_flip, post_backward_flip);
        $display("Tap+backward transients -> flip  %0d        %0d", raw_tap_backward_flip, post_tap_backward_flip);

        $display("");
        $display("---------------- OVERALL SUMMARY ----------------");
        $display("Intended gesture episodes        : %0d", total_episodes);
        $display("PRE-arbitration candidate events : %0d", raw_candidate_count);
        $display("PRE extra/unwanted candidates    : %0d", raw_extra);
        $display("POST-arbitration commands        : %0d", arbiter_command_count);
        $display("POST correct episodes            : %0d", arbiter_correct_episodes);
        $display("POST unwanted commands           : %0d", post_unwanted);
        $display("Unwanted-event suppression       : %0.2f%%", suppression_pct);
        $display("Failed episode checks            : %0d", failed_episodes);

        if ((failed_episodes == 0) &&
            (total_episodes == 50) &&
            (raw_candidate_count == 140) &&
            (arbiter_command_count == 50) &&
            (arbiter_correct_episodes == 50)) begin
            $display("EXPERIMENT-B PASS: quantitative arbiter suppression verified");
        end else begin
            $display("EXPERIMENT-B FAIL: inspect counts above");
            $fatal;
        end

        $finish;
    end

endmodule
