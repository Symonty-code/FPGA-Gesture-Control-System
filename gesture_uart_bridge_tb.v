`timescale 1ns/1ps

module gesture_uart_bridge_tb;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg tilt_left_level = 1'b0;
    reg tilt_right_level = 1'b0;
    reg tilt_forward_level = 1'b0;
    reg tilt_backward_level = 1'b0;
    reg tap_signal = 1'b0;
    reg shake_level = 1'b0;
    reg flip_signal = 1'b0;

    wire uart_tx_out;

    // 4 MHz clock => 250 ns period.
    always #125 clk = ~clk;

    // Fast simulation parameters. Hardware defaults remain much longer.
    localparam integer SIM_CLKS_PER_BIT   = 4;
    localparam integer SIM_REARM_CLKS     = 5;
    localparam integer SIM_TAP_GUARD      = 12;
    localparam integer SIM_TILT_LOCKOUT   = 8;
    localparam integer SIM_TAP_LOCKOUT    = 14;
    localparam integer SIM_SHAKE_LOCKOUT  = 24;
    localparam integer SIM_FLIP_LOCKOUT   = 24;
    localparam integer BIT_TIME_NS        = SIM_CLKS_PER_BIT * 250;

    gesture_uart_bridge #(
        .UART_CLKS_PER_BIT(SIM_CLKS_PER_BIT),
        .REARM_CLKS(SIM_REARM_CLKS),
        .TAP_GUARD_CLKS(SIM_TAP_GUARD),
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
        .uart_tx_out(uart_tx_out)
    );

    integer command_count = 0;
    integer before_count;
    reg [7:0] last_command = 8'h00;

    always @(posedge clk) begin
        if (dut.uart_send) begin
            command_count <= command_count + 1;
            last_command <= dut.uart_data;
        end
    end

    task receive_uart_byte;
        output [7:0] value;
        integer i;
        begin
            @(negedge uart_tx_out);
            #(BIT_TIME_NS + BIT_TIME_NS/2);
            for (i = 0; i < 8; i = i + 1) begin
                value[i] = uart_tx_out;
                #BIT_TIME_NS;
            end
            #BIT_TIME_NS;
        end
    endtask

    task expect_uart_byte;
        input [7:0] expected;
        reg [7:0] received;
        begin
            receive_uart_byte(received);
            if (received !== expected) begin
                $display("FAIL: expected %c (0x%02h), got %c (0x%02h)",
                         expected, expected, received, received);
                $fatal;
            end else begin
                $display("PASS: received %c", received);
            end
        end
    endtask

    task wait_for_full_rearm;
        begin
            // Longer than the largest simulated lockout + rearm + UART frame.
            repeat (100) @(posedge clk);
        end
    endtask

    task hold_then_release_left;
        begin
            @(negedge clk);
            tilt_left_level = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            tilt_left_level = 1'b0;
        end
    endtask

    task hold_then_release_right;
        begin
            @(negedge clk);
            tilt_right_level = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            tilt_right_level = 1'b0;
        end
    endtask

    task hold_then_release_forward;
        begin
            @(negedge clk);
            tilt_forward_level = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            tilt_forward_level = 1'b0;
        end
    endtask

    task hold_then_release_backward;
        begin
            @(negedge clk);
            tilt_backward_level = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            tilt_backward_level = 1'b0;
        end
    endtask

    task pulse_tap;
        begin
            @(negedge clk);
            tap_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            tap_signal = 1'b0;
        end
    endtask

    task hold_then_release_shake;
        begin
            @(negedge clk);
            shake_level = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            shake_level = 1'b0;
        end
    endtask

    task pulse_flip;
        begin
            @(negedge clk);
            flip_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            flip_signal = 1'b0;
        end
    endtask

    // One intended left gesture followed by detector-tail chatter.
    // Only L is allowed; T/S/R tails must be absorbed by the refractory interval.
    task left_with_tail_chatter;
        begin
            @(negedge clk);
            tilt_left_level = 1'b1;
            repeat (2) @(posedge clk);

            @(negedge clk);
            tap_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            tap_signal = 1'b0;

            @(negedge clk);
            shake_level = 1'b1;
            tilt_right_level = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            shake_level = 1'b0;
            tilt_right_level = 1'b0;
            tilt_left_level = 1'b0;
        end
    endtask

    // Simulates a tap-like transient at the beginning of a shake.
    // Expected result: S only; pending T must be cancelled.
    task tap_then_shake;
        begin
            @(negedge clk);
            tap_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            tap_signal = 1'b0;

            repeat (3) @(posedge clk);

            @(negedge clk);
            shake_level = 1'b1;
            repeat (10) @(posedge clk);
            @(negedge clk);
            shake_level = 1'b0;
        end
    endtask

    // Shake followed by tap/directional tails. Only S is allowed.
    task shake_with_tail_chatter;
        begin
            @(negedge clk);
            shake_level = 1'b1;
            repeat (3) @(posedge clk);

            @(negedge clk);
            tap_signal = 1'b1;
            tilt_backward_level = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            tap_signal = 1'b0;
            tilt_backward_level = 1'b0;

            repeat (4) @(posedge clk);
            @(negedge clk);
            shake_level = 1'b0;
        end
    endtask

    // Flip followed by orientation-induced directional/tap tails. Only F is allowed.
    task flip_with_tail_chatter;
        begin
            @(negedge clk);
            flip_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            flip_signal = 1'b0;

            repeat (2) @(posedge clk);
            @(negedge clk);
            tilt_forward_level = 1'b1;
            tap_signal = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            tilt_forward_level = 1'b0;
            tap_signal = 1'b0;
        end
    endtask

    // Safety watchdog: simulation must never hang forever.
    initial begin
        #1000000;
        $display("FAIL: simulation timeout");
        $fatal;
    end

    initial begin
        repeat (8) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (6) @(posedge clk);

        // Refractory-tail test around a directional command.
        before_count = command_count;
        fork
            left_with_tail_chatter();
            expect_uart_byte("L");
        join
        wait_for_full_rearm();
        if (command_count !== before_count + 1) begin
            $display("FAIL: directional tail chatter generated extra commands");
            $fatal;
        end
        $display("PASS: directional tail chatter suppressed");

        fork
            hold_then_release_right();
            expect_uart_byte("R");
        join
        wait_for_full_rearm();

        fork
            hold_then_release_forward();
            expect_uart_byte("U");
        join
        wait_for_full_rearm();

        fork
            hold_then_release_backward();
            expect_uart_byte("D");
        join
        wait_for_full_rearm();

        // Pure tap must still work after the guard delay.
        fork
            pulse_tap();
            expect_uart_byte("T");
        join
        wait_for_full_rearm();

        // Shake refractory-tail suppression.
        before_count = command_count;
        fork
            shake_with_tail_chatter();
            expect_uart_byte("S");
        join
        wait_for_full_rearm();
        if (command_count !== before_count + 1) begin
            $display("FAIL: shake tail chatter generated extra commands");
            $fatal;
        end
        $display("PASS: shake tail chatter suppressed");

        // Flip refractory-tail suppression.
        before_count = command_count;
        fork
            flip_with_tail_chatter();
            expect_uart_byte("F");
        join
        wait_for_full_rearm();
        if (command_count !== before_count + 1) begin
            $display("FAIL: flip tail chatter generated extra commands");
            $fatal;
        end
        $display("PASS: flip tail chatter suppressed");

        // Arbitration regression: early tap-like pulse that develops into shake
        // must resolve to S rather than T.
        before_count = command_count;
        fork
            tap_then_shake();
            expect_uart_byte("S");
        join
        wait_for_full_rearm();
        if (command_count !== before_count + 1) begin
            $display("FAIL: tap-to-shake arbitration generated extra commands");
            $fatal;
        end
        $display("PASS: tap-to-shake arbitration suppressed false T");

        $display("ALL FPGA->UART FINAL ARBITER TESTS PASSED");
        $finish;
    end

endmodule
