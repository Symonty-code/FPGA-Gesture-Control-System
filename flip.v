`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// One-way Flip Detector: FACE-UP -> FACE-DOWN
//
// A flip event is generated only for this sequence:
//   1) Board is stably face-up (positive Z) long enough to arm.
//   2) Board leaves the upright region -> flip_candidate asserts early.
//   3) Board reaches and holds face-down (negative Z) -> flip_pulse.
//
// Returning from face-down to face-up does NOT generate a flip. It only
// re-arms the detector for the next future face-up -> face-down transition.
//////////////////////////////////////////////////////////////////////////////////

module flip_detector #(
    parameter signed UPRIGHT_THRESH   = 16'sd800,
    parameter signed CANDIDATE_THRESH = 16'sd750,
    parameter signed FACEDOWN_THRESH  = -16'sd800,
    parameter integer ARM_SAMPLES     = 20,   // ~200 ms at ~100 Hz
    parameter integer FLIP_SAMPLES    = 25    // ~250 ms face-down confirmation
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                in_valid,
    input  wire signed [15:0]  in_z,

    output reg                 flip_pulse,
    output reg                 flip_candidate
);

    reg        armed_faceup;
    reg [7:0]  arm_count;
    reg [7:0]  facedown_count;

    wire faceup_now   = (in_z > UPRIGHT_THRESH);
    wire facedown_now = (in_z < FACEDOWN_THRESH);

    always @(posedge clk) begin
        if (rst) begin
            armed_faceup   <= 1'b0;
            arm_count      <= 8'd0;
            facedown_count <= 8'd0;
            flip_candidate <= 1'b0;
            flip_pulse     <= 1'b0;
        end else if (in_valid) begin
            flip_pulse <= 1'b0;

            // -------------------------------------------------------------
            // Phase 1: arm only after a short stable face-up interval.
            // -------------------------------------------------------------
            if (!armed_faceup) begin
                flip_candidate <= 1'b0;
                facedown_count <= 8'd0;

                if (faceup_now) begin
                    if ((ARM_SAMPLES <= 1) || (arm_count >= ARM_SAMPLES - 1)) begin
                        armed_faceup <= 1'b1;
                        arm_count    <= 8'd0;
                    end else begin
                        arm_count <= arm_count + 1'b1;
                    end
                end else begin
                    arm_count <= 8'd0;
                end
            end

            // -------------------------------------------------------------
            // Phase 2: detector is armed.  As the board starts rotating away
            // from face-up, assert flip_candidate early so UART arbitration
            // can suppress transient Tap/Backward interpretations.
            // -------------------------------------------------------------
            else begin
                if (in_z < CANDIDATE_THRESH)
                    flip_candidate <= 1'b1;
                else if (faceup_now)
                    flip_candidate <= 1'b0;

                // A valid flip is simply stable face-down after being armed
                // face-up.  No face-down -> face-up motion is required.
                if (facedown_now) begin
                    if ((FLIP_SAMPLES <= 1) ||
                        (facedown_count >= FLIP_SAMPLES - 1)) begin
                        flip_pulse     <= 1'b1;
                        flip_candidate <= 1'b0;
                        armed_faceup   <= 1'b0;
                        facedown_count <= 8'd0;
                        arm_count      <= 8'd0;
                    end else begin
                        facedown_count <= facedown_count + 1'b1;
                    end
                end else begin
                    facedown_count <= 8'd0;
                end
            end
        end
    end

endmodule
