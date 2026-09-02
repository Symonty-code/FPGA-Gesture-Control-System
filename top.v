`timescale 1ns/1ps

module top(
    input  CLK100MHZ,
    input  ACL_MISO,
    output ACL_MOSI,
    output ACL_SCLK,
    output ACL_CSN,
    output UART_RXD_OUT,       // FPGA -> PC through Nexys A7 USB-UART bridge
    output [15:0] LED,
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
    // SPI accelerometer acquisition
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
            rst_cnt <= rst_cnt + 1'b1;
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
    // Tilt Detector
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
    wire flip_candidate;

    flip_detector flip (
        .clk(clk_4MHz),
        .rst(rst),
        .in_valid(sh_valid),
        .in_z(filt_z),
        .flip_pulse(flip_pulse),
        .flip_candidate(flip_candidate)
    );

    //--------------------------------------------------
    // Debouncers
    //--------------------------------------------------
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

    //--------------------------------------------------
    // FPGA -> PC gesture command bridge
    // Sends one ASCII byte per newly accepted gesture:
    // L, R, U, D, T, S, F
    //--------------------------------------------------
    gesture_uart_bridge game_uart (
        .clk                 (clk_4MHz),
        .rst                 (rst),
        .tilt_left_level     (tilt_left_level),
        .tilt_right_level    (tilt_right_level),
        .tilt_forward_level  (tilt_forward_level),
        .tilt_backward_level (tilt_backward_level),
        .tap_signal          (tap_pulse),
        .shake_level         (shake_level),
        .flip_signal         (flip_pulse),
        .flip_candidate      (flip_candidate),
        .uart_tx_out         (UART_RXD_OUT)
    );

    //--------------------------------------------------
    // Existing UI FSM
    //--------------------------------------------------
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

    //--------------------------------------------------
    // Existing Mode Controller
    //--------------------------------------------------
    wire [15:0] LED_mode;

    mode_controller modes (
        .clk(clk_4MHz),
        .rst(rst),
        .sample_valid(sh_valid),
        .in_execute(in_execute),
        .menu_index(menu_index),
        .tilt_left_level(tilt_left_level),
        .tilt_right_level(tilt_right_level),
        .tilt_forward_level(tilt_forward_level),
        .tilt_backward_level(tilt_backward_level),
        .tap_pulse(tap_pulse),
        .shake_level(shake_level),
        .flip_pulse(flip_pulse),
        .LED_mode(LED_mode)
    );

    //--------------------------------------------------
    // 7-Segment Display
    //--------------------------------------------------
    simple_seg7 display (
        .menu_index(menu_index),
        .AN(AN),
        .SEG(SEG),
        .DP(DP)
    );

    //--------------------------------------------------
    // Existing LED Output MUX
    //--------------------------------------------------
    reg [15:0] LED_out;

    always @(*) begin
        if (in_execute) begin
            LED_out = LED_mode;
            LED_out[7] = 1'b1;
        end else begin
            LED_out = 16'b0;
            LED_out[1:0] = menu_index;
            LED_out[7] = 1'b0;
        end
    end

    assign LED = LED_out;

endmodule
