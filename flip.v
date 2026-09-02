`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Flip Detector - Event-Based Version with Early Flip Candidate
//
// Detects sequence:
//   1) Z stably positive (upright reference acquired)
//   2) Board rotates far enough toward inversion -> flip_candidate asserted
//   3) Z stably negative -> one-cycle flip_pulse
//
// flip_candidate is intentionally earlier than flip_pulse.  It lets the
// command arbiter suppress orientation-induced tilt commands while a physical
// flip is still developing.
//////////////////////////////////////////////////////////////////////////////////

module flip_detector #(
    parameter signed THRESH = 16'sd800,
    parameter signed CANDIDATE_THRESH = 16'sd300,
    parameter STABLE_SAMPLES = 50
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire signed [15:0] in_z,

    output reg                flip_pulse,
    output reg                flip_candidate
);

    localparam WAIT_POS = 2'd0;
    localparam WAIT_NEG = 2'd1;

    reg [1:0] state;
    reg [7:0] stable_cnt;

    wire z_positive = (in_z >  THRESH);
    wire z_negative = (in_z < -THRESH);

    always @(posedge clk) begin
        if (rst) begin
            state          <= WAIT_POS;
            stable_cnt     <= 0;
            flip_pulse     <= 0;
            flip_candidate <= 0;

        end else if (in_valid) begin

            flip_pulse <= 0;

            case (state)

                WAIT_POS: begin
                    flip_candidate <= 0;

                    if (z_positive) begin
                        if (stable_cnt + 1 >= STABLE_SAMPLES) begin
                            state      <= WAIT_NEG;
                            stable_cnt <= 0;
                        end else begin
                            stable_cnt <= stable_cnt + 1'b1;
                        end
                    end else begin
                        stable_cnt <= 0;
                    end
                end

                WAIT_NEG: begin
                    // Normal upright operation keeps Z strongly positive, so
                    // the candidate remains low.  Once Z falls well below the
                    // upright region, a flip is considered to be developing.
                    if (in_z < CANDIDATE_THRESH)
                        flip_candidate <= 1'b1;
                    else if (z_positive)
                        flip_candidate <= 1'b0;

                    if (z_negative) begin
                        if (stable_cnt + 1 >= STABLE_SAMPLES) begin
                            flip_pulse     <= 1'b1;
                            flip_candidate <= 1'b0;
                            state          <= WAIT_POS;
                            stable_cnt     <= 0;
                        end else begin
                            stable_cnt <= stable_cnt + 1'b1;
                        end
                    end else begin
                        stable_cnt <= 0;
                    end
                end

                default: begin
                    state          <= WAIT_POS;
                    stable_cnt     <= 0;
                    flip_candidate <= 0;
                end

            endcase
        end
    end

endmodule
