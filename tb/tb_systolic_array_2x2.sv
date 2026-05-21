`timescale 1ns/1ps

module tb_systolic_array_2x2;

    localparam int N = 2;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;

    logic clk;
    logic rst;
    logic clear;

    logic signed [DATA_WIDTH-1:0] a_in [N];
    logic signed [DATA_WIDTH-1:0] b_in [N];
    logic                         a_valid_in [N];
    logic                         b_valid_in [N];
    logic signed [ACC_WIDTH-1:0]  acc_out [N][N];

    logic signed [DATA_WIDTH-1:0] a_matrix [N][N];
    logic signed [DATA_WIDTH-1:0] b_matrix [N][N];
    logic signed [ACC_WIDTH-1:0]  c_expected [N][N];

    systolic_array #(
        .N(N),
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
        .acc_out(acc_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic drive_idle;
        begin
            for (int idx = 0; idx < N; idx++) begin
                a_in[idx]       = '0;
                b_in[idx]       = '0;
                a_valid_in[idx] = 1'b0;
                b_valid_in[idx] = 1'b0;
            end
        end
    endtask

    task automatic drive_cycle(input int t);
        int k_a;
        int k_b;
        begin
            @(negedge clk);
            drive_idle();
            clear = 1'b0;

            for (int row = 0; row < N; row++) begin
                k_a = t - row;
                if (k_a >= 0 && k_a < N) begin
                    a_in[row]       = a_matrix[row][k_a];
                    a_valid_in[row] = 1'b1;
                end
            end

            for (int col = 0; col < N; col++) begin
                k_b = t - col;
                if (k_b >= 0 && k_b < N) begin
                    b_in[col]       = b_matrix[k_b][col];
                    b_valid_in[col] = 1'b1;
                end
            end
        end
    endtask

    task automatic check_results;
        begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    if (acc_out[row][col] !== c_expected[row][col]) begin
                        $fatal(1, "C[%0d][%0d] expected %0d, got %0d",
                               row, col, c_expected[row][col], acc_out[row][col]);
                    end
                end
            end
        end
    endtask

    task automatic check_zero(input string label);
        begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    if (acc_out[row][col] !== '0) begin
                        $fatal(1, "%s: C[%0d][%0d] expected 0, got %0d",
                               label, row, col, acc_out[row][col]);
                    end
                end
            end
        end
    endtask

    initial begin
        a_matrix[0][0] = 8'sd1;
        a_matrix[0][1] = 8'sd2;
        a_matrix[1][0] = 8'sd3;
        a_matrix[1][1] = 8'sd4;

        b_matrix[0][0] = 8'sd5;
        b_matrix[0][1] = 8'sd6;
        b_matrix[1][0] = 8'sd7;
        b_matrix[1][1] = 8'sd8;

        c_expected[0][0] = 32'sd19;
        c_expected[0][1] = 32'sd22;
        c_expected[1][0] = 32'sd43;
        c_expected[1][1] = 32'sd50;

        rst   = 1'b1;
        clear = 1'b0;
        drive_idle();

        repeat (2) @(posedge clk);
        #1;
        check_zero("reset");

        @(negedge clk);
        rst   = 1'b0;
        clear = 1'b1;
        drive_idle();

        @(posedge clk);
        #1;
        check_zero("clear");

        for (int t = 0; t <= (3*N - 3); t++) begin
            drive_cycle(t);
            @(posedge clk);
            #1;
            $display("t=%0d C=[[ %0d, %0d ], [ %0d, %0d ]]",
                     t, acc_out[0][0], acc_out[0][1],
                     acc_out[1][0], acc_out[1][1]);
        end

        @(negedge clk);
        drive_idle();

        check_results();

        $display("PASS: tb_systolic_array_2x2");
        $finish;
    end

endmodule
