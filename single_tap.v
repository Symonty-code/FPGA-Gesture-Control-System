`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Single Tap Detector - BALANCED SENSITIVITY
//
// Version 2: Fixed over-sensitivity issues
//
// Changes from v1:
//   1. ENERGY_THRESH_LOW: 600 → 800 (less false positives)
//   2. Added STARTUP_IGNORE samples to prevent power-up false triggers
//
// Kept from v1:
//   - QUIET_SAMPLES = 3 (this was the key fix!)
//   - ENERGY_THRESH_HIGH = 5000 (allow hard taps)
//   - TAP_DUR_MAX = 5 (allow longer taps)
//
//////////////////////////////////////////////////////////////////////////////////

module single_tap_detector #(
    parameter ENERGY_THRESH_LOW  = 16'd800,    // ✅ BALANCED: Not too sensitive (was 600)
    parameter ENERGY_THRESH_HIGH = 18'd5000,   // Allow harder taps
    parameter TAP_DUR_MIN        = 8'd1,       // 10ms minimum
    parameter TAP_DUR_MAX        = 8'd5,       // 50ms maximum
    parameter QUIET_SAMPLES      = 8'd3,       // 30ms quiet check (KEY FIX!)
    parameter DEBOUNCE_SAMPLES   = 8'd10,      // 100ms debounce
    parameter STARTUP_IGNORE     = 8'd20       // ✅ NEW: Ignore first 200ms after reset
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              in_valid,
    input  wire signed [15:0] in_x,
    input  wire signed [15:0] in_y,
    input  wire signed [15:0] in_z,
    output reg               tap_detected
);

    //--------------------------------------------------
    // ✅ NEW: Startup ignore counter
    // Prevents false triggers during power-up/reset
    //--------------------------------------------------
    reg [7:0] startup_cnt;
    wire startup_done = (startup_cnt >= STARTUP_IGNORE);

    always @(posedge clk) begin
        if (rst) begin
            startup_cnt <= 0;
        end else if (in_valid && !startup_done) begin
            startup_cnt <= startup_cnt + 1;
        end
    end

    //--------------------------------------------------
    // Previous samples
    //--------------------------------------------------
    reg signed [15:0] x_prev, y_prev, z_prev;

    always @(posedge clk) begin
        if (rst) begin
            x_prev <= 0;
            y_prev <= 0;
            z_prev <= 0;
        end else if (in_valid) begin
            x_prev <= in_x;
            y_prev <= in_y;
            z_prev <= in_z;
        end
    end

    //--------------------------------------------------
    // Jerk computation
    //--------------------------------------------------
    reg signed [15:0] dx_r, dy_r, dz_r;

    always @(posedge clk) begin
        if (rst) begin
            dx_r <= 0;
            dy_r <= 0;
            dz_r <= 0;
        end else if (in_valid) begin
            dx_r <= in_x - x_prev;
            dy_r <= in_y - y_prev;
            dz_r <= in_z - z_prev;
        end
    end

    //--------------------------------------------------
    // Absolute value with -32768 protection
    //--------------------------------------------------
    wire signed [16:0] dx_ext = {dx_r[15], dx_r};
    wire signed [16:0] dy_ext = {dy_r[15], dy_r};
    wire signed [16:0] dz_ext = {dz_r[15], dz_r};

    wire [16:0] abs_dx = dx_ext[16] ? -dx_ext : dx_ext;
    wire [16:0] abs_dy = dy_ext[16] ? -dy_ext : dy_ext;
    wire [16:0] abs_dz = dz_ext[16] ? -dz_ext : dz_ext;

    wire [17:0] energy = abs_dx + abs_dy + abs_dz;

    // ✅ MODIFIED: Only detect spike if startup is done
    wire spike = startup_done &&
                 (energy > ENERGY_THRESH_LOW) &&
                 (energy < ENERGY_THRESH_HIGH);

    //--------------------------------------------------
    // FSM with CANCELLED state
    //--------------------------------------------------
    localparam IDLE       = 3'd0;
    localparam TAP_ACTIVE = 3'd1;
    localparam QUIET      = 3'd2;
    localparam CANCELLED  = 3'd3;
    localparam DEBOUNCE   = 3'd4;

    reg [2:0] state;
    reg [7:0] duration_cnt;
    reg [7:0] quiet_cnt;
    reg [7:0] debounce_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            duration_cnt <= 0;
            quiet_cnt    <= 0;
            debounce_cnt <= 0;
            tap_detected <= 0;

        end else if (in_valid) begin

            tap_detected <= 0;  // Default: no pulse

            case (state)

                //--------------------------------------------------
                IDLE:
                begin
                    duration_cnt <= 0;
                    quiet_cnt    <= 0;

                    if (spike) begin
                        state        <= TAP_ACTIVE;
                        duration_cnt <= 1;
                    end
                end

                //--------------------------------------------------
                TAP_ACTIVE:
                begin
                    if (spike) begin
                        // Spike continues

                        if (duration_cnt + 1 > TAP_DUR_MAX) begin
                            // Too long, reject
                            state        <= IDLE;
                            duration_cnt <= 0;
                        end else begin
                            duration_cnt <= duration_cnt + 1;
                        end

                    end else begin
                        // Spike ended

                        if (duration_cnt >= TAP_DUR_MIN) begin
                            // Valid duration, now validate quiet period
                            state     <= QUIET;
                            quiet_cnt <= 0;
                        end else begin
                            // Too short, glitch
                            state <= IDLE;
                        end

                        duration_cnt <= 0;
                    end
                end

                //--------------------------------------------------
                // QUIET VALIDATION (30ms - KEY FIX!)
                //--------------------------------------------------
                QUIET:
                begin
                    if (spike) begin
                        // Spike during quiet validation!
                        // This is shake (second spike cluster) - REJECT!
                        state        <= CANCELLED;
                        debounce_cnt <= 0;
                        quiet_cnt    <= 0;

                    end else begin
                        // Still quiet, keep counting

                        if (quiet_cnt + 1 >= QUIET_SAMPLES) begin
                            // ✅ Quiet period complete!
                            // Confirmed: ONE spike cluster + brief silence = real tap!
                            tap_detected <= 1;
                            state        <= DEBOUNCE;
                            debounce_cnt <= 0;
                            quiet_cnt    <= 0;
                        end else begin
                            quiet_cnt <= quiet_cnt + 1;
                        end
                    end
                end

                //--------------------------------------------------
                // CANCELLED (100ms cooldown)
                //--------------------------------------------------
                CANCELLED:
                begin
                    if (debounce_cnt + 1 >= DEBOUNCE_SAMPLES) begin
                        state        <= IDLE;
                        debounce_cnt <= 0;
                    end else begin
                        debounce_cnt <= debounce_cnt + 1;
                    end
                end

                //--------------------------------------------------
                // DEBOUNCE (after successful tap confirmation)
                //--------------------------------------------------
                DEBOUNCE:
                begin
                    if (debounce_cnt + 1 >= DEBOUNCE_SAMPLES) begin
                        state        <= IDLE;
                        debounce_cnt <= 0;
                    end else begin
                        debounce_cnt <= debounce_cnt + 1;
                    end
                end

                default:
                begin
                    state        <= IDLE;
                    duration_cnt <= 0;
                    quiet_cnt    <= 0;
                    debounce_cnt <= 0;
                end

            endcase
        end
    end

endmodule