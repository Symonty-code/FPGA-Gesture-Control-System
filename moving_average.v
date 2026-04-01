`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////////
// moving_average.v - N-point Simple Moving Average (SMA) Filter
//
// Features:
// - Running sum algorithm (efficient hardware)
// - Updates only when sample_en = 1
// - Window includes current sample (0-frame latency)
// - Outputs out_valid strobe when new average ready
//
// Pipeline interface:
//   sample_en (input)  → Filter processes → out_valid (output)
//////////////////////////////////////////////////////////////////////////////////
module moving_average #(
    parameter N     = 8,    // Window length (power of 2 recommended)
    parameter IN_W  = 16,   // Input width (16-bit for accelerometer)
    parameter OUT_W = 16    // Output width
)(
    input  wire                    clk,
    input  wire                    rst,        // Synchronous reset
    input  wire                    sample_en,  // 1-cycle pulse (from sh_valid)
    input  wire signed [IN_W-1:0]  sample_in,  // Input sample (from sh_x/y/z)
    output reg  signed [OUT_W-1:0] avg_out,    // Filtered output
    output reg                     out_valid   // 1-cycle pulse when new avg ready
);
    // Enough bits for sum (safe for N up to ~256)
    localparam SUM_W = IN_W + 8;
    
    // Shift register window (newest at [0], oldest at [N-1])
    reg signed [IN_W-1:0] shift_reg [0:N-1];
    
    // Running sum
    reg signed [SUM_W-1:0] sum;
    
    // Helpers
    reg signed [IN_W-1:0] oldest;
    reg signed [SUM_W-1:0] sum_next;
    integer i;
    
    // Sign-extend IN_W -> SUM_W
    function [SUM_W-1:0] sx_in;
        input signed [IN_W-1:0] v;
        begin
            sx_in = {{(SUM_W-IN_W){v[IN_W-1]}}, v};
        end
    endfunction
    
    // Combinational logic: compute next sum
    always @(*) begin
        oldest   = shift_reg[N-1];
        sum_next = sum + sx_in(sample_in) - sx_in(oldest);
    end
    
    // Sequential logic: update on sample_en
    always @(posedge clk) begin
        if (rst) begin
            sum       <= 0;
            avg_out   <= 0;
            out_valid <= 1'b0;
            for (i = 0; i < N; i = i + 1) begin
                shift_reg[i] <= 0;
            end
        end else if (sample_en) begin
            // Shift register: newest at [0]
            for (i = N-1; i > 0; i = i - 1) begin
                shift_reg[i] <= shift_reg[i-1];
            end
            shift_reg[0] <= sample_in;
            
            // Update sum and average
            sum     <= sum_next;
            avg_out <= sum_next / N;  // Division (Vivado optimizes for N=power of 2)
            
            // Generate output strobe
            out_valid <= 1'b1;
        end else begin
            // Clear strobe when not updating
            out_valid <= 1'b0;
        end
    end
    
endmodule
