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

    gesture_uart_bridge dut (
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

    localparam integer BIT_TIME_NS = 8750; // 35 clocks * 250 ns

    task receive_uart_byte;
        output [7:0] value;
        integer i;
        begin
            @(negedge uart_tx_out);              // start bit begins
            #(BIT_TIME_NS + BIT_TIME_NS/2);      // center of data bit 0
            for (i = 0; i < 8; i = i + 1) begin
                value[i] = uart_tx_out;
                #BIT_TIME_NS;
            end
            #BIT_TIME_NS;                        // allow stop bit to finish
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
            tilt_left_level = 1'b1;
            repeat (4) @(posedge clk);
            tilt_left_level = 1'b0;
        end
    endtask

    task hold_then_release_right;
        begin
            tilt_right_level = 1'b1;
            repeat (4) @(posedge clk);
            tilt_right_level = 1'b0;
        end
    endtask

    task hold_then_release_forward;
        begin
            tilt_forward_level = 1'b1;
            repeat (4) @(posedge clk);
            tilt_forward_level = 1'b0;
        end
    endtask

    task hold_then_release_backward;
        begin
            tilt_backward_level = 1'b1;
            repeat (4) @(posedge clk);
            tilt_backward_level = 1'b0;
        end
    endtask

    task pulse_tap;
        begin
            tap_signal = 1'b1;
            @(posedge clk);
            tap_signal = 1'b0;
        end
    endtask

    task hold_then_release_shake;
        begin
            shake_level = 1'b1;
            repeat (4) @(posedge clk);
            shake_level = 1'b0;
        end
    endtask

    task pulse_flip;
        begin
            flip_signal = 1'b1;
            @(posedge clk);
            flip_signal = 1'b0;
        end
    endtask

    initial begin
        repeat (8) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

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

        $display("ALL FPGA->UART GESTURE COMMAND TESTS PASSED");
        $finish;
    end

endmodule
