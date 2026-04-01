`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// Flip Detector - Event-Based Version
//
// Detects sequence:
//   1) Z stably positive
//   2) Then Z stably negative
//
// Outputs 1-cycle flip_pulse
//////////////////////////////////////////////////////////////////////////////////

module flip_detector #(
    parameter signed THRESH = 16'sd800,
    parameter STABLE_SAMPLES = 50
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              in_valid,
    input  wire signed [15:0] in_z,

    output reg               flip_pulse
);

    localparam WAIT_POS = 2'd0;
    localparam WAIT_NEG = 2'd1;

    reg [1:0] state;
    reg [7:0] stable_cnt;

    wire z_positive = (in_z >  THRESH);
    wire z_negative = (in_z < -THRESH);

    always @(posedge clk) begin
        if (rst) begin
            state       <= WAIT_POS;
            stable_cnt  <= 0;
            flip_pulse  <= 0;

        end else if (in_valid) begin

            flip_pulse <= 0;

            case (state)

                WAIT_POS: begin
                    if (z_positive) begin
                        if (stable_cnt + 1 >= STABLE_SAMPLES) begin
                            state      <= WAIT_NEG;
                            stable_cnt <= 0;
                        end else begin
                            stable_cnt <= stable_cnt + 1;
                        end
                    end else begin
                        stable_cnt <= 0;
                    end
                end

                WAIT_NEG: begin
                    if (z_negative) begin
                        if (stable_cnt + 1 >= STABLE_SAMPLES) begin
                            flip_pulse <= 1;
                            state      <= WAIT_POS;
                            stable_cnt <= 0;
                        end else begin
                            stable_cnt <= stable_cnt + 1;
                        end
                    end else begin
                        stable_cnt <= 0;
                    end
                end

                default: begin
                    state      <= WAIT_POS;
                    stable_cnt <= 0;
                end

            endcase
        end
    end

endmodule
