`timescale 1ns / 1ps
module riscv_tb;
    reg clk = 0, reset = 1;
    Riscv dut (.clk(clk), .reset(reset));

    always #5 clk = ~clk;

    initial begin
        #12 reset = 0;
        #150;
        $display("x1=%0d x2=%0d x3=%0d x4=%0d x5=%0d x6=%0d x7=%0d",
            dut.RF.register[1], dut.RF.register[2], dut.RF.register[3],
            dut.RF.register[4], dut.RF.register[5], dut.RF.register[6],
            dut.RF.register[7]);
    
        $finish;
    end
endmodule
