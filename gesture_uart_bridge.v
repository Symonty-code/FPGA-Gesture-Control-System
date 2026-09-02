`timescale 1ns/1ps

// Converts validated gesture outputs into single-byte ASCII commands for the PC.
// Commands: L/R/U/D/T/S/F.
//
// Arbiter rules:
//   * one command per physical gesture episode
//   * flip > shake > directional tilt > tap
//   * tap guard suppresses early tap-like transients
//   * direction guard lets an early flip candidate suppress U/D/L/R during inversion
//   * class-specific lockout + neutral re-arm suppress detector tails
module gesture_uart_bridge #(
    parameter integer UART_CLKS_PER_BIT = 35,
    parameter integer REARM_CLKS = 400000,             // 100 ms @ 4 MHz
    parameter integer TAP_GUARD_CLKS = 800000,          // 200 ms
    parameter integer DIR_GUARD_CLKS = 800000,          // 200 ms
    parameter integer FLIP_WAIT_TIMEOUT_CLKS = 8000000, // 2 s
    parameter integer TILT_LOCKOUT_CLKS  = 400000,      // 100 ms
    parameter integer TAP_LOCKOUT_CLKS   = 1000000,     // 250 ms
    parameter integer SHAKE_LOCKOUT_CLKS = 2400000,     // 600 ms
    parameter integer FLIP_LOCKOUT_CLKS  = 2400000      // 600 ms
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
    input  wire flip_candidate,
    output wire uart_tx_out
);

    // Edge detection
    reg prev_left, prev_right, prev_forward, prev_backward;
    reg prev_tap, prev_shake, prev_flip;

    wire evt_left     = tilt_left_level     & ~prev_left;
    wire evt_right    = tilt_right_level    & ~prev_right;
    wire evt_forward  = tilt_forward_level  & ~prev_forward;
    wire evt_backward = tilt_backward_level & ~prev_backward;
    wire evt_tap      = tap_signal          & ~prev_tap;
    wire evt_shake    = shake_level         & ~prev_shake;
    wire evt_flip     = flip_signal         & ~prev_flip;

    // UART
    reg       uart_send;
    reg [7:0] uart_data;
    wire      uart_busy;

    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) tx_inst (
        .clk(clk), .rst(rst), .send(uart_send), .data(uart_data),
        .tx(uart_tx_out), .busy(uart_busy)
    );

    // Arbiter state
    localparam [2:0] ST_ARMED     = 3'd0;
    localparam [2:0] ST_TAP_WAIT  = 3'd1;
    localparam [2:0] ST_DIR_WAIT  = 3'd2;
    localparam [2:0] ST_FLIP_WAIT = 3'd3;
    localparam [2:0] ST_LOCKOUT   = 3'd4;
    localparam [2:0] ST_REARM     = 3'd5;

    reg [2:0] state;
    reg [7:0] pending_dir_data;
    reg [31:0] tap_count, dir_count, flip_wait_count;
    reg [31:0] lockout_count, lockout_target, rearm_count;

    wire any_level_active = tilt_left_level | tilt_right_level |
                            tilt_forward_level | tilt_backward_level |
                            shake_level;
    wire quiet_now = ~any_level_active & ~tap_signal & ~flip_signal & ~flip_candidate;

    always @(posedge clk) begin
        if (rst) begin
            prev_left <= 0; prev_right <= 0; prev_forward <= 0; prev_backward <= 0;
            prev_tap <= 0; prev_shake <= 0; prev_flip <= 0;
            uart_send <= 0; uart_data <= 0;
            state <= ST_ARMED;
            pending_dir_data <= 0;
            tap_count <= 0; dir_count <= 0; flip_wait_count <= 0;
            lockout_count <= 0; lockout_target <= 0; rearm_count <= 0;
        end else begin
            prev_left <= tilt_left_level;
            prev_right <= tilt_right_level;
            prev_forward <= tilt_forward_level;
            prev_backward <= tilt_backward_level;
            prev_tap <= tap_signal;
            prev_shake <= shake_level;
            prev_flip <= flip_signal;
            uart_send <= 1'b0;

            case (state)
                ST_ARMED: begin
                    if (!uart_busy) begin
                        if (evt_flip || flip_signal) begin
                            uart_data <= "F"; uart_send <= 1'b1;
                            state <= ST_LOCKOUT; lockout_count <= 0;
                            lockout_target <= FLIP_LOCKOUT_CLKS; rearm_count <= 0;
                        end else if (flip_candidate) begin
                            state <= ST_FLIP_WAIT; flip_wait_count <= 0;
                        end else if (evt_shake) begin
                            uart_data <= "S"; uart_send <= 1'b1;
                            state <= ST_LOCKOUT; lockout_count <= 0;
                            lockout_target <= SHAKE_LOCKOUT_CLKS; rearm_count <= 0;
                        end else if (evt_forward) begin
                            pending_dir_data <= "U"; dir_count <= 0; state <= ST_DIR_WAIT;
                        end else if (evt_backward) begin
                            pending_dir_data <= "D"; dir_count <= 0; state <= ST_DIR_WAIT;
                        end else if (evt_left) begin
                            pending_dir_data <= "L"; dir_count <= 0; state <= ST_DIR_WAIT;
                        end else if (evt_right) begin
                            pending_dir_data <= "R"; dir_count <= 0; state <= ST_DIR_WAIT;
                        end else if (evt_tap) begin
                            tap_count <= 0; state <= ST_TAP_WAIT;
                        end
                    end
                end

                ST_TAP_WAIT: begin
                    if (!uart_busy) begin
                        if (evt_flip || flip_signal) begin
                            uart_data <= "F"; uart_send <= 1'b1;
                            state <= ST_LOCKOUT; lockout_count <= 0;
                            lockout_target <= FLIP_LOCKOUT_CLKS; tap_count <= 0; rearm_count <= 0;
                        end else if (flip_candidate) begin
                            state <= ST_FLIP_WAIT; flip_wait_count <= 0; tap_count <= 0;
                        end else if (evt_shake || shake_level) begin
                            uart_data <= "S"; uart_send <= 1'b1;
                            state <= ST_LOCKOUT; lockout_count <= 0;
                            lockout_target <= SHAKE_LOCKOUT_CLKS; tap_count <= 0; rearm_count <= 0;
                        end else if (evt_forward || tilt_forward_level) begin
                            pending_dir_data <= "U"; dir_count <= 0; tap_count <= 0; state <= ST_DIR_WAIT;
                        end else if (evt_backward || tilt_backward_level) begin
                            pending_dir_data <= "D"; dir_count <= 0; tap_count <= 0; state <= ST_DIR_WAIT;
                        end else if (evt_left || tilt_left_level) begin
                            pending_dir_data <= "L"; dir_count <= 0; tap_count <= 0; state <= ST_DIR_WAIT;
                        end else if (evt_right || tilt_right_level) begin
                            pending_dir_data <= "R"; dir_count <= 0; tap_count <= 0; state <= ST_DIR_WAIT;
                        end else if ((TAP_GUARD_CLKS <= 1) || (tap_count >= TAP_GUARD_CLKS - 1)) begin
                            uart_data <= "T"; uart_send <= 1'b1;
                            state <= ST_LOCKOUT; lockout_count <= 0;
                            lockout_target <= TAP_LOCKOUT_CLKS; tap_count <= 0; rearm_count <= 0;
                        end else begin
                            tap_count <= tap_count + 1'b1;
                        end
                    end
                end

                ST_DIR_WAIT: begin
                    if (!uart_busy) begin
                        if (evt_flip || flip_signal) begin
                            uart_data <= "F"; uart_send <= 1'b1;
                            state <= ST_LOCKOUT; lockout_count <= 0;
                            lockout_target <= FLIP_LOCKOUT_CLKS; dir_count <= 0; rearm_count <= 0;
                        end else if (flip_candidate) begin
                            // Key fix: discard pending direction while flip develops.
                            state <= ST_FLIP_WAIT; flip_wait_count <= 0; dir_count <= 0;
                        end else if ((DIR_GUARD_CLKS <= 1) || (dir_count >= DIR_GUARD_CLKS - 1)) begin
                            uart_data <= pending_dir_data; uart_send <= 1'b1;
                            state <= ST_LOCKOUT; lockout_count <= 0;
                            lockout_target <= TILT_LOCKOUT_CLKS; dir_count <= 0; rearm_count <= 0;
                        end else begin
                            dir_count <= dir_count + 1'b1;
                        end
                    end
                end

                ST_FLIP_WAIT: begin
                    if (!uart_busy && (evt_flip || flip_signal)) begin
                        uart_data <= "F"; uart_send <= 1'b1;
                        state <= ST_LOCKOUT; lockout_count <= 0;
                        lockout_target <= FLIP_LOCKOUT_CLKS; flip_wait_count <= 0; rearm_count <= 0;
                    end else if ((FLIP_WAIT_TIMEOUT_CLKS <= 1) ||
                                 (flip_wait_count >= FLIP_WAIT_TIMEOUT_CLKS - 1)) begin
                        // Aborted/incomplete flip: emit nothing and require neutral.
                        state <= ST_REARM; flip_wait_count <= 0; rearm_count <= 0;
                    end else begin
                        flip_wait_count <= flip_wait_count + 1'b1;
                    end
                end

                ST_LOCKOUT: begin
                    if ((lockout_target <= 1) || (lockout_count >= lockout_target - 1)) begin
                        state <= ST_REARM; lockout_count <= 0; rearm_count <= 0;
                    end else begin
                        lockout_count <= lockout_count + 1'b1;
                    end
                end

                ST_REARM: begin
                    if (quiet_now) begin
                        if ((REARM_CLKS <= 1) || (rearm_count >= REARM_CLKS - 1)) begin
                            state <= ST_ARMED; rearm_count <= 0;
                        end else begin
                            rearm_count <= rearm_count + 1'b1;
                        end
                    end else begin
                        rearm_count <= 0;
                    end
                end

                default: begin
                    state <= ST_ARMED;
                    tap_count <= 0; dir_count <= 0; flip_wait_count <= 0;
                    lockout_count <= 0; rearm_count <= 0;
                end
            endcase
        end
    end

endmodule
