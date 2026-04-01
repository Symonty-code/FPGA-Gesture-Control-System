`timescale 1ns/1ps

module tb_moving_average;

  // -------------------------------------------------
  // Parameters
  // -------------------------------------------------
  localparam N = 11;

  // -------------------------------------------------
  // Clock (simulation only)
  // -------------------------------------------------
  reg clk = 0;
  always #5 clk = ~clk;   // 100 MHz sim clock

  // -------------------------------------------------
  // DUT signals
  // -------------------------------------------------
  reg rst = 1;
  reg sample_en = 0;
  reg signed [15:0] sample_in = 0;

  wire signed [15:0] avg_out;
  wire out_valid;

  // -------------------------------------------------
  // DUT instantiation
  // -------------------------------------------------
  moving_average #(
    .N(N),
    .IN_W(16),
    .OUT_W(16)
  ) dut (
    .clk(clk),
    .rst(rst),
    .sample_en(sample_en),
    .sample_in(sample_in),
    .avg_out(avg_out),
    .out_valid(out_valid)
  );

  // -------------------------------------------------
  // Task: send one sample (1-cycle enable pulse)
  // -------------------------------------------------
  task send_sample(input signed [15:0] v);
    begin
      @(negedge clk);
      sample_in <= v;
      sample_en <= 1'b1;
      @(negedge clk);
      sample_en <= 1'b0;
    end
  endtask

  // -------------------------------------------------
  // Test sequence
  // -------------------------------------------------
  initial begin
    // Reset
    repeat (3) @(negedge clk);
    rst <= 1'b0;

    // -------- First 11 samples (fill the window) --------
    // Window:
    // 55, 5, 29, 41, 921, 67, 0, 42, 87, 18, 18
    // Sum = 1283
    // Avg = 1283 / 11 = 116
    send_sample(16'sd55);
    send_sample(16'sd5);
    send_sample(16'sd29);
    send_sample(16'sd41);
    send_sample(16'sd921);
    send_sample(16'sd67);
    send_sample(16'sd0);
    send_sample(16'sd42);
    send_sample(16'sd87);
    send_sample(16'sd18);
    send_sample(16'sd18);

    // -------- 12th sample (window slides) --------
    // Remove 55, add 18
    // New sum = 1246
    // Avg = 1246 / 11 = 113
    send_sample(16'sd18);

    // -------- Extra samples (stress sliding behavior) --------
    send_sample(16'sd860);
    send_sample(16'sd127);
    send_sample(16'sd84);
    send_sample(16'sd10);
    send_sample(16'sd181);
    send_sample(16'sd951);
    send_sample(16'sd21);

    repeat (10) @(negedge clk);
    $finish;
  end

endmodule
