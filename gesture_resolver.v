`timescale 1ns/ 1ps

/////////////////////////////////////////////////////////////
// gesture_resolver.v  (4-TILT VERSION + 2s Hold)
//
// Priority:
// 1) flip_pulse
// 2) shake_level
// 3) tap_detected
// 4) tilt (directional)
//
// LED Mapping:
// LED[2] = tilt left
// LED[3] = tilt right
// LED[4] = tilt forward
// LED[3] = tilt backward
// LED[6] = tap (2s hold)
// LED[7] = shake (2s hold)
// LED[8] = flip

/////////////////////////////////////////////////////////////

module gesture_resolver (
    input wire clk,
    input wire rst,
    input wire sample_valid,

    input wire tilt_left_level,
    input wire tilt_right_level,
    input wire tilt_forward_level,
    input wire tilt_backward_level,

    input wire shake_level,
    input wire tap_detected,
    input wire flip_pulse,

    output reg [7:0] LED
);

    //--------------------------------------------------
    // FSM States
    //--------------------------------------------------
    localparam S_IDLE           = 3'd0;
    localparam S_TILT_LEFT      = 3'd1;
    localparam S_TILT_RIGHT     = 3'd2;
    localparam S_TILT_FORWARD   = 3'd3;
    localparam S_TILT_BACKWARD  = 3'd4;
    localparam S_SHAKE          = 3'd5;
    localparam S_TAP            = 3'd6;
    localparam S_FLIP           = 3'd7;

    localparam HOLD_TIME = 8'd200;   // ~2 seconds @ 100 Hz

    reg [2:0] state;
    reg [7:0] hold_cnt;

    //--------------------------------------------------
    // LED decode
    //--------------------------------------------------
    always @(*) begin
        LED = 8'b00000000;

        case (state)
            S_TILT_LEFT:     LED[0] = 1'b1;
            S_TILT_RIGHT:    LED[1] = 1'b1;
            S_TILT_FORWARD:  LED[2] = 1'b1;
            S_TILT_BACKWARD: LED[3] = 1'b1;
            S_TAP:           LED[4] = 1'b1;
            S_SHAKE:         LED[5] = 1'b1;
            S_FLIP:          LED[6] = 1'b1;
            default:         LED = 8'b00000000;
        endcase
    end

    //--------------------------------------------------
    // Main FSM
    //--------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            hold_cnt <= 8'd0;

        end else if (sample_valid) begin

            case (state)

                //--------------------------------------------------
                // IDLE: choose by priority
                //--------------------------------------------------
                S_IDLE: begin
                    hold_cnt <= 8'd0;

                    if (flip_pulse)
                        state <= S_FLIP;

                    else if (shake_level) begin
                        state    <= S_SHAKE;
                        hold_cnt <= HOLD_TIME;
                    end

                    else if (tap_detected) begin
                        state    <= S_TAP;
                        hold_cnt <= HOLD_TIME;
                    end

                    else if (tilt_left_level)
                        state <= S_TILT_LEFT;

                    else if (tilt_right_level)
                        state <= S_TILT_RIGHT;

                    else if (tilt_forward_level)
                        state <= S_TILT_FORWARD;

                    else if (tilt_backward_level)
                        state <= S_TILT_BACKWARD;
                end

                //--------------------------------------------------
                // Tilt states (live while active)
                //--------------------------------------------------
                S_TILT_LEFT:
                    if (!tilt_left_level)
                        state <= S_IDLE;

                S_TILT_RIGHT:
                    if (!tilt_right_level)
                        state <= S_IDLE;

                S_TILT_FORWARD:
                    if (!tilt_forward_level)
                        state <= S_IDLE;

                S_TILT_BACKWARD:
                    if (!tilt_backward_level)
                        state <= S_IDLE;

                //--------------------------------------------------
                // Shake (2s hold)
                //--------------------------------------------------
                S_SHAKE: begin
                    if (hold_cnt > 0)
                        hold_cnt <= hold_cnt - 1;
                    else
                        state <= S_IDLE;
                end

                //--------------------------------------------------
                // Tap (2s hold)
                //--------------------------------------------------
                S_TAP: begin
                    if (hold_cnt > 0)
                        hold_cnt <= hold_cnt - 1;
                    else
                        state <= S_IDLE;
                end

                //--------------------------------------------------
                // Flip (1-cycle)
                //--------------------------------------------------
                S_FLIP:
                    state <= S_IDLE;

                default:
                    state <= S_IDLE;

            endcase
        end
    end

endmodule