`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
//
// - Detects directional tilt
// - Enforces single active direction (no diagonals)
// - Uses dominance logic (larger magnitude axis wins)
// - Clears outputs first, then asserts only one
//////////////////////////////////////////////////////////////////////////////////

module tilt_detector #(
    parameter THRESHOLD = 16'd500
)(
    input  wire clk,
    input  wire rst,
    input  wire in_valid,
    input  wire signed [15:0] in_x,
    input  wire signed [15:0] in_y,

    output reg  tilt_left_cand,
    output reg  tilt_right_cand,
    output reg  tilt_forward_cand,
    output reg  tilt_backward_cand
);

    //--------------------------------------------------
    // Absolute values
    //--------------------------------------------------
    wire [15:0] abs_x = (in_x[15]) ? -in_x : in_x;
    wire [15:0] abs_y = (in_y[15]) ? -in_y : in_y;

    //--------------------------------------------------
    // Sequential logic
    //--------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            tilt_left_cand     <= 1'b0;
            tilt_right_cand    <= 1'b0;
            tilt_forward_cand  <= 1'b0;
            tilt_backward_cand <= 1'b0;

        end else if (in_valid) begin

            // Default OFF (clean style)
            tilt_left_cand     <= 1'b0;
            tilt_right_cand    <= 1'b0;
            tilt_forward_cand  <= 1'b0;
            tilt_backward_cand <= 1'b0;

            //--------------------------------------------------
            // Dominance logic
            //--------------------------------------------------

            // X dominates if |X| > THRESHOLD and |X| > |Y|
            if ((abs_x > THRESHOLD) && (abs_x > abs_y)) begin
                if (in_x > 0)
                    tilt_left_cand  <= 1'b1;
                else
                    tilt_right_cand <= 1'b1;
            end

            // Otherwise Y dominates if |Y| > THRESHOLD
            else if (abs_y > THRESHOLD) begin
                if (in_y > 0)
                    tilt_forward_cand  <= 1'b1;
                else
                    tilt_backward_cand <= 1'b1;
            end
        end
    end

endmodule
