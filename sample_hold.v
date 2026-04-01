`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Sample-and-Hold Module
// 
// Purpose: Create stable "frames" of accelerometer data
// - Latches X, Y, Z on data_valid pulse
// - Holds values constant between samples
// - Provides clean timing for downstream processing
//
// This module has:
// - NO math
// - NO filtering
// - NO thresholds
// - Pure temporal ownership of data
//////////////////////////////////////////////////////////////////////////////////
module sample_hold(
    input clk,                      // w_4MHz
    input rst,                      // Reset
    input data_valid,               // 100 Hz pulse from SPI master
    input signed [15:0] accel_x,    // Raw X from SPI (changes continuously)
    input signed [15:0] accel_y,    // Raw Y from SPI (changes continuously)
    input signed [15:0] accel_z,    // Raw Z from SPI (changes continuously)
    output reg signed [15:0] sh_x,  // Held X value (stable for 10ms)
    output reg signed [15:0] sh_y,  // Held Y value (stable for 10ms)
    output reg signed [15:0] sh_z,  // Held Z value (stable for 10ms)
    output reg sh_valid             // 1-cycle pulse when new sample captured
);
    // -------------------------------------------------
    // Sample-and-hold logic
    // -------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            sh_x <= 16'sd0;
            sh_y <= 16'sd0;
            sh_z <= 16'sd0;
            sh_valid <= 1'b0;
        end else if (data_valid) begin
            // Capture new frame
            sh_x <= accel_x;
            sh_y <= accel_y;
            sh_z <= accel_z;
            sh_valid <= 1'b1;  // Generate 1-cycle pulse
        end else begin
            // Hold values, clear pulse
            sh_valid <= 1'b0;
        end
    end

endmodule
