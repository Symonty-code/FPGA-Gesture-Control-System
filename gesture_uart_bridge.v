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
// Final gesture-decision arbiter rules:
//   1) Exactly one accepted command is emitted for one physical gesture episode.
//   2) Priority is: flip > shake > directional tilt > tap.
//   3) Tap is delayed briefly so a developing shake/tilt/flip can override a false tap.
//   4) After each accepted command, a class-specific refractory interval suppresses
//      detector tails/cross-triggers.
//   5) After the refractory interval, the board must remain quiet/neutral for a
//      short interval before the arbiter re-arms.
module gesture_uart_bridge #(
    // Hardware default: 4 MHz / 35 ~= 114.3 kbaud, close to 115200.
    parameter integer UART_CLKS_PER_BIT = 35,

    // 4 MHz clock: 400000 clocks = 100 ms neutral interval before re-arming.
    parameter integer REARM_CLKS = 400000,

    // 4 MHz clock: 800000 clocks = 200 ms tap guard.
    parameter integer TAP_GUARD_CLKS = 800000,

    // Class-specific refractory intervals at 4 MHz.
    // Tilt is already strongly debounced in top.v, so it needs only a short lockout.
    parameter integer TILT_LOCKOUT_CLKS  = 400000,   // 100 ms
    parameter integer TAP_LOCKOUT_CLKS   = 1000000,  // 250 ms
    parameter integer SHAKE_LOCKOUT_CLKS = 2400000,  // 600 ms
    parameter integer FLIP_LOCKOUT_CLKS  = 2400000   // 600 ms
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
    // Gesture decision arbiter state
    //--------------------------------------------------
    reg        armed;
    reg        pending_tap;
    reg        lockout_active;
    reg [31:0] rearm_count;
    reg [31:0] tap_guard_count;
    reg [31:0] lockout_count;
    reg [31:0] lockout_target;

    wire any_level_active = tilt_left_level |
                            tilt_right_level |
                            tilt_forward_level |
                            tilt_backward_level |
                            shake_level;

    // Quiet means no held gesture and no one-cycle event input currently asserted.
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
            pending_tap     <= 1'b0;
            lockout_active  <= 1'b0;
            rearm_count     <= 32'd0;
            tap_guard_count <= 32'd0;
            lockout_count   <= 32'd0;
            lockout_target  <= 32'd0;
        end else begin
            //--------------------------------------------------
            // Always track detector inputs, even while commands are suppressed.
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
            // 1) Refractory interval: ignore ALL detector activity.
            // This absorbs shake/tap/flip tails after one accepted gesture.
            //--------------------------------------------------
            if (lockout_active) begin
                pending_tap     <= 1'b0;
                tap_guard_count <= 32'd0;
                armed           <= 1'b0;
                rearm_count     <= 32'd0;

                if ((lockout_target <= 1) || (lockout_count >= lockout_target - 1)) begin
                    lockout_active <= 1'b0;
                    lockout_count  <= 32'd0;
                end else begin
                    lockout_count <= lockout_count + 1'b1;
                end
            end

            //--------------------------------------------------
            // 2) Pending tap arbitration.
            // A tap is not emitted immediately. Stronger gestures can replace it.
            //--------------------------------------------------
            else if (pending_tap) begin
                if (!uart_busy) begin
                    if (evt_flip || flip_signal) begin
                        uart_data        <= "F";
                        uart_send        <= 1'b1;
                        pending_tap      <= 1'b0;
                        tap_guard_count  <= 32'd0;
                        armed            <= 1'b0;
                        lockout_active   <= 1'b1;
                        lockout_count    <= 32'd0;
                        lockout_target   <= FLIP_LOCKOUT_CLKS;
                        rearm_count      <= 32'd0;
                    end else if (evt_shake || shake_level) begin
                        uart_data        <= "S";
                        uart_send        <= 1'b1;
                        pending_tap      <= 1'b0;
                        tap_guard_count  <= 32'd0;
                        armed            <= 1'b0;
                        lockout_active   <= 1'b1;
                        lockout_count    <= 32'd0;
                        lockout_target   <= SHAKE_LOCKOUT_CLKS;
                        rearm_count      <= 32'd0;
                    end else if (evt_forward || tilt_forward_level) begin
                        uart_data        <= "U";
                        uart_send        <= 1'b1;
                        pending_tap      <= 1'b0;
                        tap_guard_count  <= 32'd0;
                        armed            <= 1'b0;
                        lockout_active   <= 1'b1;
                        lockout_count    <= 32'd0;
                        lockout_target   <= TILT_LOCKOUT_CLKS;
                        rearm_count      <= 32'd0;
                    end else if (evt_backward || tilt_backward_level) begin
                        uart_data        <= "D";
                        uart_send        <= 1'b1;
                        pending_tap      <= 1'b0;
                        tap_guard_count  <= 32'd0;
                        armed            <= 1'b0;
                        lockout_active   <= 1'b1;
                        lockout_count    <= 32'd0;
                        lockout_target   <= TILT_LOCKOUT_CLKS;
                        rearm_count      <= 32'd0;
                    end else if (evt_left || tilt_left_level) begin
                        uart_data        <= "L";
                        uart_send        <= 1'b1;
                        pending_tap      <= 1'b0;
                        tap_guard_count  <= 32'd0;
                        armed            <= 1'b0;
                        lockout_active   <= 1'b1;
                        lockout_count    <= 32'd0;
                        lockout_target   <= TILT_LOCKOUT_CLKS;
                        rearm_count      <= 32'd0;
                    end else if (evt_right || tilt_right_level) begin
                        uart_data        <= "R";
                        uart_send        <= 1'b1;
                        pending_tap      <= 1'b0;
                        tap_guard_count  <= 32'd0;
                        armed            <= 1'b0;
                        lockout_active   <= 1'b1;
                        lockout_count    <= 32'd0;
                        lockout_target   <= TILT_LOCKOUT_CLKS;
                        rearm_count      <= 32'd0;
                    end else if ((TAP_GUARD_CLKS <= 1) || (tap_guard_count >= TAP_GUARD_CLKS - 1)) begin
                        uart_data        <= "T";
                        uart_send        <= 1'b1;
                        pending_tap      <= 1'b0;
                        tap_guard_count  <= 32'd0;
                        armed            <= 1'b0;
                        lockout_active   <= 1'b1;
                        lockout_count    <= 32'd0;
                        lockout_target   <= TAP_LOCKOUT_CLKS;
                        rearm_count      <= 32'd0;
                    end else begin
                        tap_guard_count <= tap_guard_count + 1'b1;
                    end
                end
            end

            //--------------------------------------------------
            // 3) After lockout, require a genuine neutral interval before re-arming.
            //--------------------------------------------------
            else if (!armed) begin
                if (quiet_now) begin
                    if ((REARM_CLKS <= 1) || (rearm_count >= REARM_CLKS - 1)) begin
                        armed       <= 1'b1;
                        rearm_count <= 32'd0;
                    end else begin
                        rearm_count <= rearm_count + 1'b1;
                    end
                end else begin
                    rearm_count <= 32'd0;
                end
            end

            //--------------------------------------------------
            // 4) Armed: accept exactly one new gesture using fixed priority.
            //--------------------------------------------------
            else if (!uart_busy) begin
                if (evt_flip) begin
                    uart_data       <= "F";
                    uart_send       <= 1'b1;
                    armed           <= 1'b0;
                    lockout_active  <= 1'b1;
                    lockout_count   <= 32'd0;
                    lockout_target  <= FLIP_LOCKOUT_CLKS;
                    rearm_count     <= 32'd0;
                end else if (evt_shake) begin
                    uart_data       <= "S";
                    uart_send       <= 1'b1;
                    armed           <= 1'b0;
                    lockout_active  <= 1'b1;
                    lockout_count   <= 32'd0;
                    lockout_target  <= SHAKE_LOCKOUT_CLKS;
                    rearm_count     <= 32'd0;
                end else if (evt_forward) begin
                    uart_data       <= "U";
                    uart_send       <= 1'b1;
                    armed           <= 1'b0;
                    lockout_active  <= 1'b1;
                    lockout_count   <= 32'd0;
                    lockout_target  <= TILT_LOCKOUT_CLKS;
                    rearm_count     <= 32'd0;
                end else if (evt_backward) begin
                    uart_data       <= "D";
                    uart_send       <= 1'b1;
                    armed           <= 1'b0;
                    lockout_active  <= 1'b1;
                    lockout_count   <= 32'd0;
                    lockout_target  <= TILT_LOCKOUT_CLKS;
                    rearm_count     <= 32'd0;
                end else if (evt_left) begin
                    uart_data       <= "L";
                    uart_send       <= 1'b1;
                    armed           <= 1'b0;
                    lockout_active  <= 1'b1;
                    lockout_count   <= 32'd0;
                    lockout_target  <= TILT_LOCKOUT_CLKS;
                    rearm_count     <= 32'd0;
                end else if (evt_right) begin
                    uart_data       <= "R";
                    uart_send       <= 1'b1;
                    armed           <= 1'b0;
                    lockout_active  <= 1'b1;
                    lockout_count   <= 32'd0;
                    lockout_target  <= TILT_LOCKOUT_CLKS;
                    rearm_count     <= 32'd0;
                end else if (evt_tap) begin
                    // Delay T: if this motion becomes shake/tilt/flip, the stronger
                    // gesture will replace the pending tap before anything is sent.
                    pending_tap     <= 1'b1;
                    tap_guard_count <= 32'd0;
                    armed           <= 1'b0;
                    rearm_count     <= 32'd0;
                end
            end
        end
    end

endmodule
