`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////
//
// simple_seg7.v - Simple 7-Segment Display for Menu Index
//
// Purpose: Display menu_index (0-3) on rightmost digit of 7-segment display
//
// Nexys A7 7-Segment Display:
//   - 8 digits (AN[7:0] - anodes, active LOW)
//   - 7 segments + DP (CA-CG + DP, active LOW)
//   - For Step 2: Show only rightmost digit (AN[0])
//
// Input:
//   menu_index[1:0] - current menu selection (0-3)
//
// Outputs:
//   AN[7:0] - anode control (active LOW)
//   CA-CG   - segment control (active LOW)
//   DP      - decimal point (active LOW)
//
///////////////////////////////////////////////////////////////////////////////

module simple_seg7 (
    input  wire [1:0] menu_index,  // 0-3
    output reg  [7:0] AN,           // Anode control (active LOW)
    output reg  [6:0] SEG,          // Segments CA-CG (active LOW)
    output reg        DP            // Decimal point (active LOW)
);

    // 7-segment encoding (active LOW, so inverted)
    // Segments: CA CB CC CD CE CF CG
    //            a  b  c  d  e  f  g
    //
    //      a
    //     ---
    //  f |   | b
    //     -g-
    //  e |   | c
    //     ---
    //      d
    
    localparam SEG_0 = 7'b1000000;  // 0
    localparam SEG_1 = 7'b1111001;  // 1
    localparam SEG_2 = 7'b0100100;  // 2
    localparam SEG_3 = 7'b0110000;  // 3
    localparam SEG_OFF = 7'b1111111; // All segments OFF

    always @(*) begin
        // Turn off all anodes except rightmost (AN[0])
        AN = 8'b11111110;  // Only AN[0] active (LOW)
        
        // Decimal point OFF
        DP = 1'b1;
        
        // Decode menu_index to 7-segment pattern
        case (menu_index)
            2'b00:   SEG = SEG_0;
            2'b01:   SEG = SEG_1;
            2'b10:   SEG = SEG_2;
            2'b11:   SEG = SEG_3;
            default: SEG = SEG_OFF;
        endcase
    end

endmodule