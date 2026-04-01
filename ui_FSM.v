`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////
//
//
//   - Flip ignored when in Mode 3 EXECUTE
//   - Shake ignored when in Mode 3 EXECUTE
//   - Flip and shake still work normally in Modes 0, 1, 2
//
///////////////////////////////////////////////////////////////////////////////

module ui_fsm (
    input  wire       clk,
    input  wire       rst,
    input  wire       sample_valid,
    
    // LEVEL inputs (debounced)
    input  wire       tilt_left_level,
    input  wire       tilt_right_level,
    input  wire       shake_level,
    
    // Pulse inputs (event-based)
    input  wire       tap_pulse,
    input  wire       flip_pulse,
    
    output reg  [1:0] menu_index,
    output reg        in_execute
);

    localparam S_MENU    = 1'b0;
    localparam S_EXECUTE = 1'b1;
    
    reg state;
    
    // Previous levels for edge detect (sample_valid domain)
    reg tilt_left_prev, tilt_right_prev, shake_prev;
    
    // Internal event pulses (1 sample_valid tick wide)
    wire tilt_left_evt  =  tilt_left_level  & ~tilt_left_prev;
    wire tilt_right_evt =  tilt_right_level & ~tilt_right_prev;
    wire shake_evt      =  shake_level      & ~shake_prev;
    
    // Moore output
    always @(*) begin
        case (state)
            S_MENU:    in_execute = 1'b0;
            S_EXECUTE: in_execute = 1'b1;
            default:   in_execute = 1'b0;
        endcase
    end
    
    // State + menu logic
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_MENU;
            menu_index     <= 2'b00;
            tilt_left_prev <= 1'b0;
            tilt_right_prev<= 1'b0;
            shake_prev     <= 1'b0;
            
        end else if (sample_valid) begin
            
            // Update prev registers each sample tick
            tilt_left_prev  <= tilt_left_level;
            tilt_right_prev <= tilt_right_level;
            shake_prev      <= shake_level;
            
            // ✅ CHANGED: GLOBAL flip resets EXCEPT in Mode 3!
            if (flip_pulse && !(state == S_EXECUTE && menu_index == 2'b11)) begin
                state      <= S_MENU;
                menu_index <= 2'b00;
            
            // ✅ CHANGED: EXECUTE shake exits EXCEPT in Mode 3!
            end else if ((state == S_EXECUTE) && shake_evt && (menu_index != 2'b11)) begin
                state <= S_MENU;
                
            end else begin
                
                case (state)
                    
                    // MENU: navigate with tilt events, enter EXECUTE with tap
                    S_MENU: begin
                        if (tilt_right_evt) begin
                            if (menu_index == 2'b11) menu_index <= 2'b00;
                            else                      menu_index <= menu_index + 1'b1;
                        end
                        else if (tilt_left_evt) begin
                            if (menu_index == 2'b00) menu_index <= 2'b11;
                            else                      menu_index <= menu_index - 1'b1;
                        end
                        else if (tap_pulse) begin
                            state <= S_EXECUTE;
                        end
                    end
                    
                    // EXECUTE: hold menu_index, wait for shake/flip (handled above)
                    S_EXECUTE: begin
                        // no-op
                    end
                    
                    default: begin
                        state      <= S_MENU;
                        menu_index <= 2'b00;
                    end
                    
                endcase
            end
        end
    end
    
endmodule
