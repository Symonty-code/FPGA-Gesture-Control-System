`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////
//
// top.v - FINAL: Mode 3 with 16 LEDs
//
// Changes:
//   - LED expanded to [15:0] (16 LEDs)
//   - LED_mode expanded to [15:0]
//   - Mode 3 uses LED[8] for shake, LED[9] for flip
//
///////////////////////////////////////////////////////////////////////////////

module top(
    input  CLK100MHZ,
    input  ACL_MISO,
    output ACL_MOSI,
    output ACL_SCLK,
    output ACL_CSN,
    output [15:0] LED,  // ✅ CHANGED: Now 16 LEDs!
    
    // 7-Segment Display Outputs
    output [7:0] AN,
    output [6:0] SEG,
    output DP
);

    //--------------------------------------------------
    // Clock
    //--------------------------------------------------
    wire clk_4MHz;

    iclk_gen clkgen (
        .CLK100MHZ (CLK100MHZ),
        .clk_4MHz  (clk_4MHz)
    );

    //--------------------------------------------------
    // SPI
    //--------------------------------------------------
    wire signed [15:0] accel_x, accel_y, accel_z;
    wire data_valid;

    spi_master spi (
        .iclk       (clk_4MHz),
        .miso       (ACL_MISO),
        .sclk       (ACL_SCLK),
        .mosi       (ACL_MOSI),
        .cs         (ACL_CSN),
        .accel_x    (accel_x),
        .accel_y    (accel_y),
        .accel_z    (accel_z),
        .data_valid (data_valid)
    );

    //--------------------------------------------------
    // Reset
    //--------------------------------------------------
    reg [3:0] rst_cnt = 0;
    reg rst = 1'b1;

    always @(posedge clk_4MHz) begin
        if (rst_cnt < 10) begin
            rst_cnt <= rst_cnt + 1;
            rst <= 1'b1;
        end else begin
            rst <= 1'b0;
        end
    end

    //--------------------------------------------------
    // Sample & Hold
    //--------------------------------------------------
    wire signed [15:0] sh_x, sh_y, sh_z;
    wire sh_valid;

    sample_hold sh (
        .clk        (clk_4MHz),
        .rst        (rst),
        .data_valid (data_valid),
        .accel_x    (accel_x),
        .accel_y    (accel_y),
        .accel_z    (accel_z),
        .sh_x       (sh_x),
        .sh_y       (sh_y),
        .sh_z       (sh_z),
        .sh_valid   (sh_valid)
    );

    //--------------------------------------------------
    // Moving Average
    //--------------------------------------------------
    wire signed [15:0] filt_x, filt_y, filt_z;

    moving_average #(.N(8)) ma_x (
        .clk(clk_4MHz), .rst(rst),
        .sample_en(sh_valid),
        .sample_in(sh_x),
        .avg_out(filt_x),
        .out_valid()
    );

    moving_average #(.N(8)) ma_y (
        .clk(clk_4MHz), .rst(rst),
        .sample_en(sh_valid),
        .sample_in(sh_y),
        .avg_out(filt_y),
        .out_valid()
    );

    moving_average #(.N(8)) ma_z (
        .clk(clk_4MHz), .rst(rst),
        .sample_en(sh_valid),
        .sample_in(sh_z),
        .avg_out(filt_z),
        .out_valid()
    );

    //--------------------------------------------------
    // Tilt Detector (4-directional)
    //--------------------------------------------------
    wire tilt_left_cand, tilt_right_cand;
    wire tilt_forward_cand, tilt_backward_cand;

    tilt_detector tilt (
        .clk(clk_4MHz),
        .rst(rst),
        .in_valid(sh_valid),
        .in_x(filt_x),
        .in_y(filt_y),
        .tilt_left_cand(tilt_left_cand),
        .tilt_right_cand(tilt_right_cand),
        .tilt_forward_cand(tilt_forward_cand),
        .tilt_backward_cand(tilt_backward_cand)
    );

    //--------------------------------------------------
    // Shake Detector
    //--------------------------------------------------
    wire shake_cand;

    shake_detector shake (
        .clk(clk_4MHz),
        .rst(rst),
        .in_valid(sh_valid),
        .in_x(filt_x),
        .in_y(filt_y),
        .in_z(filt_z),
        .shake_cand(shake_cand)
    );

    //--------------------------------------------------
    // Tap Detector
    //--------------------------------------------------
    wire tap_pulse;

    single_tap_detector tap (
        .clk(clk_4MHz),
        .rst(rst),
        .in_valid(sh_valid),
        .in_x(sh_x),
        .in_y(sh_y),
        .in_z(sh_z),
        .tap_detected(tap_pulse)
    );

    //--------------------------------------------------
    // Flip Detector
    //--------------------------------------------------
    wire flip_pulse;

    flip_detector flip (
        .clk(clk_4MHz),
        .rst(rst),
        .in_valid(sh_valid),
        .in_z(filt_z),
        .flip_pulse(flip_pulse)
    );

    //==================================================
    // DEBOUNCERS (All 4 tilt directions + shake)
    //==================================================
    wire tilt_left_level, tilt_right_level;
    wire tilt_forward_level, tilt_backward_level;
    wire shake_level;

    gesture_debouncer #(.STABLE_SAMPLES(20)) db_left (
        .clk(clk_4MHz), .rst(rst),
        .sample_valid(sh_valid),
        .gesture_cand(tilt_left_cand),
        .gesture_level(tilt_left_level),
        .gesture_pulse()
    );

    gesture_debouncer #(.STABLE_SAMPLES(20)) db_right (
        .clk(clk_4MHz), .rst(rst),
        .sample_valid(sh_valid),
        .gesture_cand(tilt_right_cand),
        .gesture_level(tilt_right_level),
        .gesture_pulse()
    );

    gesture_debouncer #(.STABLE_SAMPLES(20)) db_forward (
        .clk(clk_4MHz), .rst(rst),
        .sample_valid(sh_valid),
        .gesture_cand(tilt_forward_cand),
        .gesture_level(tilt_forward_level),
        .gesture_pulse()
    );

    gesture_debouncer #(.STABLE_SAMPLES(20)) db_backward (
        .clk(clk_4MHz), .rst(rst),
        .sample_valid(sh_valid),
        .gesture_cand(tilt_backward_cand),
        .gesture_level(tilt_backward_level),
        .gesture_pulse()
    );

    gesture_debouncer #(.STABLE_SAMPLES(6)) db_shake (
        .clk(clk_4MHz), .rst(rst),
        .sample_valid(sh_valid),
        .gesture_cand(shake_cand),
        .gesture_level(shake_level),
        .gesture_pulse()
    );

    //==================================================
    // UI FSM (Navigation Logic)
    //==================================================
    wire [1:0] menu_index;
    wire in_execute;

    ui_fsm fsm (
        .clk(clk_4MHz),
        .rst(rst),
        .sample_valid(sh_valid),

        .tilt_left_level(tilt_left_level),
        .tilt_right_level(tilt_right_level),
        .shake_level(shake_level),

        .tap_pulse(tap_pulse),
        .flip_pulse(flip_pulse),

        .menu_index(menu_index),
        .in_execute(in_execute)
    );

    //==================================================
    // MODE CONTROLLER
    //==================================================
    wire [15:0] LED_mode;  // ✅ CHANGED: Now 16 bits!

    mode_controller modes (
        .clk(clk_4MHz),
        .rst(rst),
        .sample_valid(sh_valid),
        
        .in_execute(in_execute),
        .menu_index(menu_index),
        
        // Mode control gestures
        .tilt_left_level(tilt_left_level),
        .tilt_right_level(tilt_right_level),
        .tilt_forward_level(tilt_forward_level),
        .tilt_backward_level(tilt_backward_level),
        .tap_pulse(tap_pulse),
        .shake_level(shake_level),
        .flip_pulse(flip_pulse),
        
        .LED_mode(LED_mode)
    );

    //==================================================
    // 7-Segment Display
    //==================================================
    simple_seg7 display (
        .menu_index(menu_index),
        .AN(AN),
        .SEG(SEG),
        .DP(DP)
    );

    //==================================================
    // LED OUTPUT MUX (MENU vs EXECUTE)
    //==================================================
    reg [15:0] LED_out;  // ✅ CHANGED: Now 16 bits!
    
    always @(*) begin
        if (in_execute) begin
            // EXECUTE: Show mode output
            LED_out = LED_mode;
            // Always show execute state on LED[7]
            LED_out[7] = 1'b1;
        end else begin
            // MENU: Show menu_index for debug
            LED_out = 16'b0000000000000000;  // ✅ CHANGED: 16 bits
            LED_out[1:0] = menu_index;
            LED_out[7] = 1'b0;  // Not executing
        end
    end
    
    assign LED = LED_out;

endmodule