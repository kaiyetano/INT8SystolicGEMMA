`timescale 1ns/1ps

module tb_pe;

    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;

    logic clk;
    logic rst;
    logic clear;

    logic signed [DATA_WIDTH-1:0] a_in;
    logic signed [DATA_WIDTH-1:0] b_in;
    logic                         a_valid_in;
    logic                         b_valid_in;

    logic signed [DATA_WIDTH-1:0] a_out;
    logic signed [DATA_WIDTH-1:0] b_out;
    logic                         a_valid_out;
    logic                         b_valid_out;
    logic signed [ACC_WIDTH-1:0]  acc_out;

    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .a_in(a_in),
        .b_in(b_in),
        .a_valid_in(a_valid_in),
        .b_valid_in(b_valid_in),
        .a_out(a_out),
        .b_out(b_out),
        .a_valid_out(a_valid_out),
        .b_valid_out(b_valid_out),
        .acc_out(acc_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic drive_inputs(
        input logic signed [DATA_WIDTH-1:0] next_a,
        input logic signed [DATA_WIDTH-1:0] next_b,
        input logic                         next_a_valid,
        input logic                         next_b_valid,
        input logic                         next_clear
    );
        begin
            @(negedge clk);
            a_in       = next_a;
            b_in       = next_b;
            a_valid_in = next_a_valid;
            b_valid_in = next_b_valid;
            clear      = next_clear;
        end
    endtask

    task automatic check_outputs(
        input string                        label,
        input logic signed [DATA_WIDTH-1:0] exp_a_out,
        input logic signed [DATA_WIDTH-1:0] exp_b_out,
        input logic                         exp_a_valid_out,
        input logic                         exp_b_valid_out,
        input logic signed [ACC_WIDTH-1:0]  exp_acc_out
    );
        begin
            @(posedge clk);
            #1;

            if (a_out !== exp_a_out) begin
                $fatal(1, "%s: a_out expected %0d, got %0d", label, exp_a_out, a_out);
            end

            if (b_out !== exp_b_out) begin
                $fatal(1, "%s: b_out expected %0d, got %0d", label, exp_b_out, b_out);
            end

            if (a_valid_out !== exp_a_valid_out) begin
                $fatal(1, "%s: a_valid_out expected %0b, got %0b", label, exp_a_valid_out, a_valid_out);
            end

            if (b_valid_out !== exp_b_valid_out) begin
                $fatal(1, "%s: b_valid_out expected %0b, got %0b", label, exp_b_valid_out, b_valid_out);
            end

            if (acc_out !== exp_acc_out) begin
                $fatal(1, "%s: acc_out expected %0d, got %0d", label, exp_acc_out, acc_out);
            end
        end
    endtask

    initial begin
        rst        = 1'b1;
        clear      = 1'b0;
        a_in       = '0;
        b_in       = '0;
        a_valid_in = 1'b0;
        b_valid_in = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        if (a_out !== '0 || b_out !== '0 || a_valid_out !== 1'b0 ||
            b_valid_out !== 1'b0 || acc_out !== '0) begin
            $fatal(1, "reset: PE outputs were not cleared");
        end

        @(negedge clk);
        rst = 1'b0;

        drive_inputs(-8'sd3, 8'sd4, 1'b1, 1'b1, 1'b0);
        check_outputs("first signed MAC", -8'sd3, 8'sd4, 1'b1, 1'b1, -32'sd12);

        drive_inputs(8'sd2, -8'sd5, 1'b1, 1'b1, 1'b0);
        check_outputs("second signed MAC", 8'sd2, -8'sd5, 1'b1, 1'b1, -32'sd22);

        drive_inputs(8'sd7, 8'sd9, 1'b1, 1'b0, 1'b0);
        check_outputs("b invalid holds accumulator", 8'sd7, 8'sd9, 1'b1, 1'b0, -32'sd22);

        drive_inputs(-8'sd8, -8'sd2, 1'b0, 1'b1, 1'b0);
        check_outputs("a invalid holds accumulator", -8'sd8, -8'sd2, 1'b0, 1'b1, -32'sd22);

        drive_inputs(8'sd6, 8'sd6, 1'b1, 1'b1, 1'b1);
        check_outputs("clear wins over MAC", 8'sd6, 8'sd6, 1'b1, 1'b1, 32'sd0);

        drive_inputs(-8'sd4, -8'sd4, 1'b1, 1'b1, 1'b0);
        check_outputs("accumulate after clear", -8'sd4, -8'sd4, 1'b1, 1'b1, 32'sd16);

        drive_inputs(8'sd0, 8'sd0, 1'b0, 1'b0, 1'b0);
        check_outputs("idle cycle holds accumulator", 8'sd0, 8'sd0, 1'b0, 1'b0, 32'sd16);

        $display("PASS: tb_pe");
        $finish;
    end

endmodule
