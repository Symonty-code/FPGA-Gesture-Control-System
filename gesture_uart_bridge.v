`timescale 1ns/1ps

// Converts validated gesture outputs into single-byte ASCII commands for the PC.
// Commands:
//   L = tilt left
//   R = tilt right
//   U = tilt forward (2048 move up)
//   D = tilt backward (2048 move down)
//   T = tap
//   S = shake
//   F = flip
//
// Every gesture is edge-detected so a held gesture produces only one command.
module gesture_uart_bridge (
    input  wire clk,
    input  wire rst,

    input  wire tilt_left_level,
    input  wire tilt_right_level,
    input  wire tilt_forward_level,
    input  wire tilt_backward_level,
    input  wire tap_signal,
    input  wire shake_level,
    input  wire flip_signal,

    output wire uart_tx_out
);

    reg prev_left;
    reg prev_right;
    reg prev_forward;
    reg prev_backward;
    reg prev_tap;
    reg prev_shake;
    reg prev_flip;

    wire evt_left     = tilt_left_level     & ~prev_left;
    wire evt_right    = tilt_right_level    & ~prev_right;
    wire evt_forward  = tilt_forward_level  & ~prev_forward;
    wire evt_backward = tilt_backward_level & ~prev_backward;
    wire evt_tap      = tap_signal          & ~prev_tap;
    wire evt_shake    = shake_level         & ~prev_shake;
    wire evt_flip     = flip_signal         & ~prev_flip;

    reg       uart_send;
    reg [7:0] uart_data;
    wire      uart_busy;

    uart_tx #(
        .CLKS_PER_BIT(35)
    ) tx_inst (
        .clk  (clk),
        .rst  (rst),
        .send (uart_send),
        .data (uart_data),
        .tx   (uart_tx_out),
        .busy (uart_busy)
    );

    always @(posedge clk) begin
        if (rst) begin
            prev_left     <= 1'b0;
            prev_right    <= 1'b0;
            prev_forward  <= 1'b0;
            prev_backward <= 1'b0;
            prev_tap      <= 1'b0;
            prev_shake    <= 1'b0;
            prev_flip     <= 1'b0;
            uart_send     <= 1'b0;
            uart_data     <= 8'h00;
        end else begin
            // Track levels continuously. Tap/flip are also edge-detected because
            // their current implementations may remain asserted until the next sample.
            prev_left     <= tilt_left_level;
            prev_right    <= tilt_right_level;
            prev_forward  <= tilt_forward_level;
            prev_backward <= tilt_backward_level;
            prev_tap      <= tap_signal;
            prev_shake    <= shake_level;
            prev_flip     <= flip_signal;

            uart_send <= 1'b0;

            // Gesture events are much slower than one UART byte, so a simple
            // one-event priority encoder is sufficient for this interface.
            if (!uart_busy) begin
                if (evt_flip) begin
                    uart_data <= "F";
                    uart_send <= 1'b1;
                end else if (evt_shake) begin
                    uart_data <= "S";
                    uart_send <= 1'b1;
                end else if (evt_tap) begin
                    uart_data <= "T";
                    uart_send <= 1'b1;
                end else if (evt_forward) begin
                    uart_data <= "U";
                    uart_send <= 1'b1;
                end else if (evt_backward) begin
                    uart_data <= "D";
                    uart_send <= 1'b1;
                end else if (evt_left) begin
                    uart_data <= "L";
                    uart_send <= 1'b1;
                end else if (evt_right) begin
                    uart_data <= "R";
                    uart_send <= 1'b1;
                end
            end
        end
    end

endmodule
