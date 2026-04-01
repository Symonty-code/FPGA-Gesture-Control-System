`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////
//
// mode_controller.v - FINAL: Mode 3 with LED[8] and LED[9]
//
// Changes:
//   - LED_mode output expanded to [15:0]
//   - Mode 3: Flip gets 2-second timer (not 1-cycle)
//   - Mode 3: LED[8] = Shake, LED[9] = Flip
//
///////////////////////////////////////////////////////////////////////////////

module mode_controller (
    input  wire       clk,
    input  wire       rst,
    input  wire       sample_valid,
    
    // FSM control
    input  wire       in_execute,
    input  wire [1:0] menu_index,
    
    // Gesture inputs
    input  wire       tilt_left_level,
    input  wire       tilt_right_level,
    input  wire       tilt_forward_level,
    input  wire       tilt_backward_level,
    input  wire       tap_pulse,
    input  wire       shake_level,
    input  wire       flip_pulse,
    
    // Output
    output reg  [15:0] LED_mode  // ✅ CHANGED: Now 16 bits!
);

    //==================================================
    // MODE ACTIVE SIGNALS
    //==================================================
    wire mode0_active = in_execute && (menu_index == 2'b00);
    wire mode1_active = in_execute && (menu_index == 2'b01);
    wire mode2_active = in_execute && (menu_index == 2'b10);
    wire mode3_active = in_execute && (menu_index == 2'b11);
    
    //==================================================
    // SHARED: SPEED CONTROL (Modes 0 & 1)
    //==================================================
    reg [2:0] speed = 3'd3;
    
    reg [7:0] speed_divider;
    always @(*) begin
        case (speed)
            3'd0: speed_divider = 8'd200;
            3'd1: speed_divider = 8'd150;
            3'd2: speed_divider = 8'd100;
            3'd3: speed_divider = 8'd50;
            3'd4: speed_divider = 8'd25;
            3'd5: speed_divider = 8'd10;
            3'd6: speed_divider = 8'd5;
            3'd7: speed_divider = 8'd2;
            default: speed_divider = 8'd50;
        endcase
    end
    
    reg [7:0] clk_div_cnt = 8'd0;
    wire counter_tick = (clk_div_cnt == speed_divider - 1);
    reg paused = 1'b0;
    
    // Edge detection
    reg tilt_left_prev = 1'b0;
    reg tilt_right_prev = 1'b0;
    reg tilt_forward_prev = 1'b0;
    reg tilt_backward_prev = 1'b0;
    
    wire tilt_left_evt = tilt_left_level & ~tilt_left_prev;
    wire tilt_right_evt = tilt_right_level & ~tilt_right_prev;
    wire tilt_forward_evt = tilt_forward_level & ~tilt_forward_prev;
    wire tilt_backward_evt = tilt_backward_level & ~tilt_backward_prev;
    
    //==================================================
    // MODE 0: LED COUNTER
    //==================================================
    reg [7:0] led_counter = 8'd0;
    
    //==================================================
    // MODE 1: LED SHIFT PATTERN
    //==================================================
    reg [6:0] shift_reg = 7'b0000001;
    reg direction = 1'b0;
    
    //==================================================
    // MODE 2: PWM BRIGHTNESS
    //==================================================
    reg [7:0] pwm_counter = 8'd0;
    reg [7:0] duty_cycle = 8'd128;
    reg breathing_enabled = 1'b0;
    reg breath_direction = 1'b0;
    reg [7:0] breath_div_cnt = 8'd0;
    localparam BREATH_SPEED = 8'd2;
    wire breath_tick = (breath_div_cnt == BREATH_SPEED - 1);
    
    //==================================================
    // MODE 3: GESTURE DEMO
    //==================================================
    
    // FSM States
    localparam M3_IDLE           = 3'd0;
    localparam M3_TILT_LEFT      = 3'd1;
    localparam M3_TILT_RIGHT     = 3'd2;
    localparam M3_TILT_FORWARD   = 3'd3;
    localparam M3_TILT_BACKWARD  = 3'd4;
    localparam M3_SHAKE          = 3'd5;
    localparam M3_TAP            = 3'd6;
    localparam M3_FLIP           = 3'd7;
    
    localparam M3_HOLD_TIME = 8'd200;  // 2 seconds @ 100Hz
    
    reg [2:0] m3_state = M3_IDLE;
    reg [7:0] m3_hold_cnt = 8'd0;
    
    //==================================================
    // MAIN LOGIC
    //==================================================
    always @(posedge clk) begin
        if (rst) begin
            // Shared
            speed <= 3'd3;
            clk_div_cnt <= 8'd0;
            paused <= 1'b0;
            tilt_left_prev <= 1'b0;
            tilt_right_prev <= 1'b0;
            tilt_forward_prev <= 1'b0;
            tilt_backward_prev <= 1'b0;
            
            // Mode 0
            led_counter <= 8'd0;
            
            // Mode 1
            shift_reg <= 7'b0000001;
            direction <= 1'b0;
            
            // Mode 2
            pwm_counter <= 8'd0;
            duty_cycle <= 8'd128;
            breathing_enabled <= 1'b0;
            breath_direction <= 1'b0;
            breath_div_cnt <= 8'd0;
            
            // Mode 3
            m3_state <= M3_IDLE;
            m3_hold_cnt <= 8'd0;
            
        end else begin
            
            //------------------------------------------
            // PWM counter (Mode 2)
            //------------------------------------------
            if (mode2_active) pwm_counter <= pwm_counter + 1'b1;
            else              pwm_counter <= 8'd0;
            
            //------------------------------------------
            // SAMPLE VALID DOMAIN
            //------------------------------------------
            if (sample_valid) begin
                
                // Update edge detection
                tilt_left_prev <= tilt_left_level;
                tilt_right_prev <= tilt_right_level;
                tilt_forward_prev <= tilt_forward_level;
                tilt_backward_prev <= tilt_backward_level;
                
                //------------------------------------------
                // MODES 0 & 1: SHARED SPEED/PAUSE
                //------------------------------------------
                if (mode0_active || mode1_active) begin
                    if (tilt_right_evt && speed < 3'd7) begin
                        speed <= speed + 1'b1;
                        clk_div_cnt <= 8'd0;
                    end
                    else if (tilt_left_evt && speed > 3'd0) begin
                        speed <= speed - 1'b1;
                        clk_div_cnt <= 8'd0;
                    end
                    
                    if (tap_pulse) paused <= ~paused;
                    
                    if (!paused) begin
                        if (counter_tick) clk_div_cnt <= 8'd0;
                        else              clk_div_cnt <= clk_div_cnt + 1'b1;
                    end
                end
                
                //------------------------------------------
                // MODE 0
                //------------------------------------------
                if (mode0_active) begin
                    if (!paused && counter_tick)
                        led_counter <= led_counter + 1'b1;
                end else begin
                    led_counter <= 8'd0;
                end
                
                //------------------------------------------
                // MODE 1
                //------------------------------------------
                if (mode1_active) begin
                    if (tilt_forward_evt)  direction <= 1'b0;
                    if (tilt_backward_evt) direction <= 1'b1;
                    
                    if (!paused && counter_tick) begin
                        if (direction == 1'b0) begin
                            if (shift_reg == 7'b1000000) shift_reg <= 7'b0000001;
                            else                         shift_reg <= shift_reg << 1;
                        end else begin
                            if (shift_reg == 7'b0000001) shift_reg <= 7'b1000000;
                            else                         shift_reg <= shift_reg >> 1;
                        end
                    end
                end else begin
                    shift_reg <= 7'b0000001;
                    direction <= 1'b0;
                end
                
                //------------------------------------------
                // MODE 2
                //------------------------------------------
                if (mode2_active) begin
                    
                    if (!breathing_enabled) begin
                        if (tilt_right_evt) begin
                            if (duty_cycle <= 8'd239) duty_cycle <= duty_cycle + 8'd16;
                            else                      duty_cycle <= 8'd255;
                        end
                        else if (tilt_left_evt) begin
                            if (duty_cycle >= 8'd16)  duty_cycle <= duty_cycle - 8'd16;
                            else                      duty_cycle <= 8'd0;
                        end
                    end
                    
                    if (tilt_forward_evt) begin
                        duty_cycle <= 8'd255;
                        breathing_enabled <= 1'b0;
                    end
                    else if (tilt_backward_evt) begin
                        duty_cycle <= 8'd0;
                        breathing_enabled <= 1'b0;
                    end
                    
                    if (tap_pulse) begin
                        if (breathing_enabled) breathing_enabled <= 1'b0;
                        else begin
                            breathing_enabled <= 1'b1;
                            breath_direction <= (duty_cycle < 8'd128) ? 1'b0 : 1'b1;
                        end
                    end
                    
                    if (breathing_enabled) begin
                        if (breath_tick) begin
                            breath_div_cnt <= 8'd0;
                            if (breath_direction == 1'b0) begin
                                if (duty_cycle >= 8'd254) breath_direction <= 1'b1;
                                else                      duty_cycle <= duty_cycle + 1'b1;
                            end else begin
                                if (duty_cycle <= 8'd1)   breath_direction <= 1'b0;
                                else                      duty_cycle <= duty_cycle - 1'b1;
                            end
                        end else begin
                            breath_div_cnt <= breath_div_cnt + 1'b1;
                        end
                    end else begin
                        breath_div_cnt <= 8'd0;
                    end
                    
                end else begin
                    duty_cycle <= 8'd128;
                    breathing_enabled <= 1'b0;
                    breath_direction <= 1'b0;
                    breath_div_cnt <= 8'd0;
                end
                
                //------------------------------------------
                // MODE 3: GESTURE DEMO FSM
                //------------------------------------------
                if (mode3_active) begin
                    
                    case (m3_state)
                        
                        M3_IDLE: begin
                            m3_hold_cnt <= 8'd0;
                            
                            if (flip_pulse) begin
                                m3_state <= M3_FLIP;
                                m3_hold_cnt <= M3_HOLD_TIME;  // ✅ CHANGED: 2s timer!
                            end
                            
                            else if (shake_level) begin
                                m3_state <= M3_SHAKE;
                                m3_hold_cnt <= M3_HOLD_TIME;
                            end
                            
                            else if (tap_pulse) begin
                                m3_state <= M3_TAP;
                                m3_hold_cnt <= M3_HOLD_TIME;
                            end
                            
                            else if (tilt_left_level)
                                m3_state <= M3_TILT_LEFT;
                            
                            else if (tilt_right_level)
                                m3_state <= M3_TILT_RIGHT;
                            
                            else if (tilt_forward_level)
                                m3_state <= M3_TILT_FORWARD;
                            
                            else if (tilt_backward_level)
                                m3_state <= M3_TILT_BACKWARD;
                        end
                        
                        // Tilt states (live while active)
                        M3_TILT_LEFT:
                            if (!tilt_left_level)
                                m3_state <= M3_IDLE;
                        
                        M3_TILT_RIGHT:
                            if (!tilt_right_level)
                                m3_state <= M3_IDLE;
                        
                        M3_TILT_FORWARD:
                            if (!tilt_forward_level)
                                m3_state <= M3_IDLE;
                        
                        M3_TILT_BACKWARD:
                            if (!tilt_backward_level)
                                m3_state <= M3_IDLE;
                        
                        // Shake (2-second hold)
                        M3_SHAKE: begin
                            if (m3_hold_cnt > 0)
                                m3_hold_cnt <= m3_hold_cnt - 1;
                            else
                                m3_state <= M3_IDLE;
                        end
                        
                        // Tap (2-second hold)
                        M3_TAP: begin
                            if (m3_hold_cnt > 0)
                                m3_hold_cnt <= m3_hold_cnt - 1;
                            else
                                m3_state <= M3_IDLE;
                        end
                        
                        // ✅ CHANGED: Flip (2-second hold, not 1-cycle!)
                        M3_FLIP: begin
                            if (m3_hold_cnt > 0)
                                m3_hold_cnt <= m3_hold_cnt - 1;
                            else
                                m3_state <= M3_IDLE;
                        end
                        
                        default:
                            m3_state <= M3_IDLE;
                    
                    endcase
                    
                end else begin
                    m3_state <= M3_IDLE;
                    m3_hold_cnt <= 8'd0;
                end
                
                //------------------------------------------
                // GLOBAL RESET
                //------------------------------------------
                if (!in_execute) begin
                    speed <= 3'd3;
                    clk_div_cnt <= 8'd0;
                    paused <= 1'b0;
                end
            end
        end
    end
    
    //==================================================
    // LED OUTPUT MULTIPLEXER
    //==================================================
    always @(*) begin
        if (in_execute) begin
            case (menu_index)
                2'b00: begin
                    // Mode 0: Counter on lower 8 LEDs
                    LED_mode = {8'b0, led_counter};
                end
                
                2'b01: begin
                    // Mode 1: Shift on lower 7 LEDs
                    LED_mode = {9'b0, shift_reg};
                end
                
                2'b10: begin
                    // Mode 2: PWM on lower 7 LEDs
                    if (pwm_counter < duty_cycle)
                        LED_mode = 16'b0000000001111111;
                    else
                        LED_mode = 16'b0000000000000000;
                end
                
                2'b11: begin
                    // ✅ Mode 3: Gesture demo
                    // LED[2] = Tilt Left
                    // LED[3] = Tilt Right
                    // LED[4] = Tilt Forward
                    // LED[5] = Tilt Backward
                    // LED[6] = Tap (2s)
                    // LED[8] = Shake (2s) ← NEW!
                    // LED[9] = Flip (2s) ← NEW!
                    // (LED[7] = Execute indicator, set by top.v)
                    
                    LED_mode = 16'b0000000000000000;
                    
                    case (m3_state)
                        M3_TILT_LEFT:     LED_mode[2] = 1'b1;
                        M3_TILT_RIGHT:    LED_mode[3] = 1'b1;
                        M3_TILT_FORWARD:  LED_mode[4] = 1'b1;
                        M3_TILT_BACKWARD: LED_mode[5] = 1'b1;
                        M3_TAP:           LED_mode[6] = 1'b1;
                        M3_SHAKE:         LED_mode[8] = 1'b1;  // ✅ CHANGED: LED[8]!
                        M3_FLIP:          LED_mode[9] = 1'b1;  // ✅ CHANGED: LED[9]!
                        default:          LED_mode = 16'b0;
                    endcase
                end
                
                default: LED_mode = 16'b0;
            endcase
        end else begin
            LED_mode = 16'b0;
        end
    end

endmodule