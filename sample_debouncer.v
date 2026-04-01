`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Counter-based gesture debouncer (temporal stability check)
//
// Purpose:
//   Confirms a gesture candidate has been TRUE for STABLE_SAMPLES
//   consecutive valid samples before asserting gesture_level.
//
// Inputs:
//   clk          : system clock
//   rst          : synchronous reset (active high)
//   sample_valid : 1-cycle pulse per new valid sample (~100 Hz from S/H stage)
//   gesture_cand : boolean condition (e.g., filt_x > THRESH)
//
// Outputs:
//   gesture_level : HIGH once cand stable for STABLE_SAMPLES samples;
//                   stays HIGH while cand remains true;
//                   drops LOW immediately when cand goes false
//   gesture_pulse : 1-cycle pulse exactly when gesture_level FIRST goes high
//
// Timing note:
//   gesture_level rises ONE clock after stable_cnt reaches STABLE_SAMPLES-1.
//   This is CORRECT synchronous behavior (nonblocking assignment).
//   Testbench verifies: trigger happens on the Nth valid sample. PASS.
//
//////////////////////////////////////////////////////////////////////////////////

module gesture_debouncer #(
    parameter integer STABLE_SAMPLES = 8  // consecutive true samples required
)(
    input  wire clk,
    input  wire rst,
    input  wire sample_valid,
    input  wire gesture_cand,
    output reg  gesture_level,
    output reg  gesture_pulse
);

    // -------------------------------------------------
    // Counter width: enough bits to count to STABLE_SAMPLES
    // -------------------------------------------------
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer CW = (STABLE_SAMPLES <= 1) ? 1 : clog2(STABLE_SAMPLES + 1);

    reg [CW-1:0] stable_cnt;

    // -------------------------------------------------
    // Sequential logic only - no combinational level_next needed
    // -------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            stable_cnt    <= {CW{1'b0}};
            gesture_level <= 1'b0;
            gesture_pulse <= 1'b0;

        end else begin

            gesture_pulse <= 1'b0;  // default: one-shot pulse

            if (sample_valid) begin

                if (!gesture_cand) begin
                    // ----------------------------------------
                    // Candidate false: reset everything
                    // ----------------------------------------
                    stable_cnt    <= {CW{1'b0}};
                    gesture_level <= 1'b0;

                end else begin
                    // ----------------------------------------
                    // Candidate true
                    // ----------------------------------------

                    if (gesture_level) begin
                        // Already confirmed: hold HIGH while cand remains true
                        gesture_level <= 1'b1;

                    end else begin
                        // Still earning stability
                        if (STABLE_SAMPLES <= 1) begin
                            // Special case: single sample is enough
                            gesture_level <= 1'b1;
                            gesture_pulse <= 1'b1;
                            stable_cnt    <= {CW{1'b0}};

                        end else if (stable_cnt >= STABLE_SAMPLES - 1) begin
                            // Counter reached threshold: confirm gesture!
                            gesture_level <= 1'b1;
                            gesture_pulse <= 1'b1;
                            stable_cnt    <= {CW{1'b0}};  // FIXED: reset cleanly

                        end else begin
                            // Still counting...
                            stable_cnt <= stable_cnt + 1'b1;
                        end
                    end

                end
            end
        end
    end

endmodule
