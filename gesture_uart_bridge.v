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
// Robustness rules:
//   1) One physical gesture should produce one command.
//   2) After a command, the bridge must observe a quiet/neutral interval before re-arming.
//   3) Tap is delayed briefly so a developing shake/tilt/flip can override a false tap.
//   4) Priority is: flip > shake > directional tilt > tap.
module gesture_uart_bridge #(
    // Hardware default: 4 MHz / 35 ~= 114.3 kbaud, close to 115200.
    parameter integer UART_CLKS_PER_BIT = 35,

    // 4 MHz clock: 600000 clocks ~= 150 ms of quiet before accepting a new gesture.
    parameter integer REARM_CLKS = 600000,

    // 4 MHz clock: 720000 clocks ~= 180 ms tap guard.
    // This gives the shake detector time to assert and suppress a shake-induced false tap.
    parameter integer TAP_GUARD_CLKS = 720000
)(
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

    //--------------------------------------------------
    // Edge detection
    //--------------------------------------------------
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

    //--------------------------------------------------
    // UART
    //--------------------------------------------------
    reg       uart_send;
    reg [7:0] uart_data;
    wire      uart_busy;

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) tx_inst (
        .clk  (clk),
        .rst  (rst),
        .send (uart_send),
        .data (uart_data),
        .tx   (uart_tx_out),
        .busy (uart_busy)
    );

    //--------------------------------------------------
    // Command guard / arbitration
    //--------------------------------------------------
    localparam integer REARM_W = (REARM_CLKS <= 1) ? 1 : $clog2(REARM_CLKS);
    localparam integer TAP_W   = (TAP_GUARD_CLKS <= 1) ? 1 : $clog2(TAP_GUARD_CLKS);

    reg [REARM_W-1:0] rearm_count;
    reg [TAP_W-1:0]   tap_guard_count;
    reg                armed;
    reg                pending_tap;

    wire any_level_active = tilt_left_level |
                            tilt_right_level |
                            tilt_forward_level |
                            tilt_backward_level |
                            shake_level;

    // A quiet interval means no held gesture and no event pulse at this clock.
    wire quiet_now = ~any_level_active & ~tap_signal & ~flip_signal;

    //--------------------------------------------------
    // Main control
    //--------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            prev_left       <= 1'b0;
            prev_right      <= 1'b0;
            prev_forward    <= 1'b0;
            prev_backward   <= 1'b0;
            prev_tap        <= 1'b0;
            prev_shake      <= 1'b0;
            prev_flip       <= 1'b0;

            uart_send       <= 1'b0;
            uart_data       <= 8'h00;

            armed           <= 1'b1;
            rearm_count     <= {REARM_W{1'b0}};
            pending_tap     <= 1'b0;
            tap_guard_count <= {TAP_W{1'b0}};
        end else begin
            //--------------------------------------------------
            // Always update previous samples for edge detection.
            //--------------------------------------------------
            prev_left     <= tilt_left_level;
            prev_right    <= tilt_right_level;
            prev_forward  <= tilt_forward_level;
            prev_backward <= tilt_backward_level;
            prev_tap      <= tap_signal;
            prev_shake    <= shake_level;
            prev_flip     <= flip_signal;

            uart_send <= 1'b0;

            //--------------------------------------------------
            // Re-arm only after the board has returned to a quiet state.
            //--------------------------------------------------
            if (!armed && !pending_tap) begin
                if (quiet_now) begin
                    if (REARM_CLKS <= 1) begin
                        armed       <= 1'b1;
                        rearm_count <= {REARM_W{1'b0}};
                    end else if (rearm_count >= REARM_CLKS - 1) begin
                        armed       <= 1'b1;
                        rearm_count <= {REARM_W{1'b0}};
                    end else begin
                        rearm_count <= rearm_count + 1'b1;
                    end
                end else begin
                    rearm_count <= {REARM_W{1'b0}};
                end
            end

            //--------------------------------------------------
            // Pending tap arbitration.
            // A real tap is emitted only if no stronger gesture develops
            // during the short guard interval.
            //--------------------------------------------------
            if (pending_tap && !uart_busy) begin
                if (evt_flip || flip_signal) begin
                    uart_data       <= "F";
                    uart_send       <= 1'b1;
                    pending_tap     <= 1'b0;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end else if (evt_shake || shake_level) begin
                    uart_data       <= "S";
                    uart_send       <= 1'b1;
                    pending_tap     <= 1'b0;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end else if (evt_forward || tilt_forward_level) begin
                    uart_data       <= "U";
                    uart_send       <= 1'b1;
                    pending_tap     <= 1'b0;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end else if (evt_backward || tilt_backward_level) begin
                    uart_data       <= "D";
                    uart_send       <= 1'b1;
                    pending_tap     <= 1'b0;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end else if (evt_left || tilt_left_level) begin
                    uart_data       <= "L";
                    uart_send       <= 1'b1;
                    pending_tap     <= 1'b0;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end else if (evt_right || tilt_right_level) begin
                    uart_data       <= "R";
                    uart_send       <= 1'b1;
                    pending_tap     <= 1'b0;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end else if (TAP_GUARD_CLKS <= 1 || tap_guard_count >= TAP_GUARD_CLKS - 1) begin
                    uart_data       <= "T";
                    uart_send       <= 1'b1;
                    pending_tap     <= 1'b0;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end else begin
                    tap_guard_count <= tap_guard_count + 1'b1;
                end
            end

            //--------------------------------------------------
            // Accept a new command only while armed.
            //--------------------------------------------------
            else if (armed && !uart_busy) begin
                // Highest priority first.
                if (evt_flip) begin
                    uart_data   <= "F";
                    uart_send   <= 1'b1;
                    armed       <= 1'b0;
                    rearm_count <= {REARM_W{1'b0}};
                end else if (evt_shake) begin
                    uart_data   <= "S";
                    uart_send   <= 1'b1;
                    armed       <= 1'b0;
                    rearm_count <= {REARM_W{1'b0}};
                end else if (evt_forward) begin
                    uart_data   <= "U";
                    uart_send   <= 1'b1;
                    armed       <= 1'b0;
                    rearm_count <= {REARM_W{1'b0}};
                end else if (evt_backward) begin
                    uart_data   <= "D";
                    uart_send   <= 1'b1;
                    armed       <= 1'b0;
                    rearm_count <= {REARM_W{1'b0}};
                end else if (evt_left) begin
                    uart_data   <= "L";
                    uart_send   <= 1'b1;
                    armed       <= 1'b0;
                    rearm_count <= {REARM_W{1'b0}};
                end else if (evt_right) begin
                    uart_data   <= "R";
                    uart_send   <= 1'b1;
                    armed       <= 1'b0;
                    rearm_count <= {REARM_W{1'b0}};
                end else if (evt_tap) begin
                    // Do not send T immediately. Wait briefly to make sure
                    // the motion does not develop into shake/tilt/flip.
                    pending_tap     <= 1'b1;
                    tap_guard_count <= {TAP_W{1'b0}};
                    armed           <= 1'b0;
                    rearm_count     <= {REARM_W{1'b0}};
                end
            end
        end
    end

endmodule
