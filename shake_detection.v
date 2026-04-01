`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Shake Detector - Candidate Version
//
// Produces shake_cand level based on windowed energy + hysteresis.
// No arbitration, no system locking.
//
//////////////////////////////////////////////////////////////////////////////////

module shake_detector #(
    parameter WINDOW_SIZE      = 10,        // ~160ms @100Hz
    parameter SHAKE_THRESHOLD  = 32'd28000,
    parameter SHAKE_HYSTERESIS = 32'd3000
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               in_valid,
    input  wire signed [15:0] in_x,
    input  wire signed [15:0] in_y,
    input  wire signed [15:0] in_z,
    output reg                shake_cand
);

    // Absolute values
    wire [15:0] abs_x = in_x[15] ? -in_x : in_x;
    wire [15:0] abs_y = in_y[15] ? -in_y : in_y;
    wire [15:0] abs_z = in_z[15] ? -in_z : in_z;

    wire [17:0] energy = abs_x + abs_y + abs_z;

    // Circular buffer
    reg [17:0] energy_buffer [0:WINDOW_SIZE-1];
    reg [$clog2(WINDOW_SIZE)-1:0] buf_index;
    reg [31:0] running_sum;

    wire [31:0] upper_thresh = SHAKE_THRESHOLD;
    wire [31:0] lower_thresh = SHAKE_THRESHOLD - SHAKE_HYSTERESIS;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            running_sum <= 32'd0;
            buf_index   <= 0;
            shake_cand  <= 1'b0;

            for (i = 0; i < WINDOW_SIZE; i = i + 1)
                energy_buffer[i] <= 18'd0;

        end else if (in_valid) begin

            // Update running sum
            running_sum <= running_sum
                           - energy_buffer[buf_index]
                           + energy;

            // Store energy
            energy_buffer[buf_index] <= energy;

            // Update index
            if (buf_index == WINDOW_SIZE - 1)
                buf_index <= 0;
            else
                buf_index <= buf_index + 1'b1;

            // Hysteresis thresholding
            if (running_sum > upper_thresh)
                shake_cand <= 1'b1;
            else if (running_sum < lower_thresh)
                shake_cand <= 1'b0;
        end
    end

endmodule