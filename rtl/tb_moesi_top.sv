// tb_moesi_top.sv
// Minimal testbench for moesi_top: clock/reset and short run for traffic.

module tb_moesi_top;
    logic clk;
    logic rst_n;

    // Clock generation: 10ns period
    always #5 clk = ~clk;

    // DUT
    moesi_top dut (
        .clk(clk),
        .rst_n(rst_n)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;

        // Apply reset for a few cycles
        #20;
        rst_n = 1'b1;

        // Run for a short duration to observe activity
        #200;
        $display("TB complete.");
        $finish;
    end
endmodule
