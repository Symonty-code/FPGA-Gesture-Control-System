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
    localparam integer SIM_CLKS_PER_BIT = 4;
    localparam integer SIM_REARM_CLKS   = 4;
    localparam integer SIM_TAP_GUARD    = 8;
    localparam integer BIT_TIME_NS      = SIM_CLKS_PER_BIT * 250;

    gesture_uart_bridge #(
        .UART_CLKS_PER_BIT(SIM_CLKS_PER_BIT),
        .REARM_CLKS(SIM_REARM_CLKS),
        .TAP_GUARD_CLKS(SIM_TAP_GUARD)
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

    task hold_then_release_left;
        begin
            @(negedge clk);
            tilt_left_level = 1'b1;
            repeat (10) @(posedge clk); // held long enough to prove one-shot behavior
            @(negedge clk);
            tilt_left_level = 1'b0;
        end
    endtask

    task hold_then_release_right;
        begin
            @(negedge clk);
            tilt_right_level = 1'b1;
            repeat (6) @(posedge clk);
            @(negedge clk);
            tilt_right_level = 1'b0;
        end
    endtask

    task hold_then_release_forward;
        begin
            @(negedge clk);
            tilt_forward_level = 1'b1;
            repeat (6) @(posedge clk);
            @(negedge clk);
            tilt_forward_level = 1'b0;
        end
    endtask

    task hold_then_release_backward;
        begin
            @(negedge clk);
            tilt_backward_level = 1'b1;
            repeat (6) @(posedge clk);
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
            repeat (6) @(posedge clk);
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

    // Simulates a tap-like transient at the beginning of a shake.
    // Expected result: S only; pending T must be cancelled.
    task tap_then_shake;
        begin
            @(negedge clk);
            tap_signal = 1'b1;
            repeat (2) @(posedge clk);
            @(negedge clk);
            tap_signal = 1'b0;

            repeat (2) @(posedge clk);

            @(negedge clk);
            shake_level = 1'b1;
            repeat (8) @(posedge clk);
            @(negedge clk);
            shake_level = 1'b0;
        end
    endtask

    initial begin
        #800000;
        $display("FAIL: simulation timeout");
        $fatal;
    end

    initial begin
        repeat (8) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (6) @(posedge clk);

        fork
            hold_then_release_left();
            expect_uart_byte("L");
        join
        repeat (10) @(posedge clk);

        fork
            hold_then_release_right();
            expect_uart_byte("R");
        join
        repeat (10) @(posedge clk);

        fork
            hold_then_release_forward();
            expect_uart_byte("U");
        join
        repeat (10) @(posedge clk);

        fork
            hold_then_release_backward();
            expect_uart_byte("D");
        join
        repeat (10) @(posedge clk);

        // Tap is intentionally delayed by the guard interval.
        fork
            pulse_tap();
            expect_uart_byte("T");
        join
        repeat (10) @(posedge clk);

        fork
            hold_then_release_shake();
            expect_uart_byte("S");
        join
        repeat (10) @(posedge clk);

        fork
            pulse_flip();
            expect_uart_byte("F");
        join
        repeat (10) @(posedge clk);

        // Arbitration regression: an early tap-like pulse followed by shake
        // must resolve to S rather than T.
        fork
            tap_then_shake();
            expect_uart_byte("S");
        join

        $display("PASS: tap-to-shake arbitration suppressed false T");
        $display("ALL FPGA->UART GUARDED COMMAND TESTS PASSED");
        $finish;
    end

endmodule
