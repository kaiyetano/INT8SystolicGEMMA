`timescale 1ns/1ps

module tb_controller_systolic_2x2;

    localparam int N = 2;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;
    localparam int INDEX_WIDTH = (N <= 1) ? 1 : $clog2(N);
    localparam int T_MAX = 3*N - 3;

    logic clk;
    logic rst;
    logic start;
    logic busy;
    logic done;
    logic clear;

    logic [INDEX_WIDTH-1:0] a_read_col [N];
    logic                   a_read_en  [N];
    logic [INDEX_WIDTH-1:0] b_read_row [N];
    logic                   b_read_en  [N];

    logic signed [DATA_WIDTH-1:0] a_in [N];
    logic signed [DATA_WIDTH-1:0] b_in [N];
    logic                         a_valid_in [N];
    logic                         b_valid_in [N];
    logic signed [ACC_WIDTH-1:0]  acc_out [N][N];

    logic signed [DATA_WIDTH-1:0] a_matrix [N][N];
    logic signed [DATA_WIDTH-1:0] b_matrix [N][N];
    logic signed [ACC_WIDTH-1:0]  c_expected [N][N];

    controller_fsm #(
        .N(N),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) ctrl (
        .clk(clk),
        .rst(rst),
        .start(start),
        .busy(busy),
        .done(done),
        .clear_array(clear),
        .a_read_col(a_read_col),
        .a_read_en(a_read_en),
        .b_read_row(b_read_row),
        .b_read_en(b_read_en)
    );

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

    always_comb begin
        for (int row = 0; row < N; row++) begin
            a_in[row]       = '0;
            a_valid_in[row] = 1'b0;

            if (a_read_en[row]) begin
                a_in[row]       = a_matrix[row][a_read_col[row]];
                a_valid_in[row] = 1'b1;
            end
        end

        for (int col = 0; col < N; col++) begin
            b_in[col]       = '0;
            b_valid_in[col] = 1'b0;

            if (b_read_en[col]) begin
                b_in[col]       = b_matrix[b_read_row[col]][col];
                b_valid_in[col] = 1'b1;
            end
        end
    end

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

    task automatic check_schedule(input int t);
        int k_a;
        int k_b;
        logic exp_a_en;
        logic exp_b_en;
        begin
            for (int row = 0; row < N; row++) begin
                k_a = t - row;
                exp_a_en = (k_a >= 0) && (k_a < N);

                if (a_read_en[row] !== exp_a_en) begin
                    $fatal(1, "t=%0d row=%0d: a_read_en expected %0b, got %0b",
                           t, row, exp_a_en, a_read_en[row]);
                end

                if (exp_a_en && (int'(a_read_col[row]) != k_a)) begin
                    $fatal(1, "t=%0d row=%0d: a_read_col expected %0d, got %0d",
                           t, row, k_a, a_read_col[row]);
                end
            end

            for (int col = 0; col < N; col++) begin
                k_b = t - col;
                exp_b_en = (k_b >= 0) && (k_b < N);

                if (b_read_en[col] !== exp_b_en) begin
                    $fatal(1, "t=%0d col=%0d: b_read_en expected %0b, got %0b",
                           t, col, exp_b_en, b_read_en[col]);
                end

                if (exp_b_en && (int'(b_read_row[col]) != k_b)) begin
                    $fatal(1, "t=%0d col=%0d: b_read_row expected %0d, got %0d",
                           t, col, k_b, b_read_row[col]);
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
        start = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        check_zero("reset");

        @(negedge clk);
        rst   = 1'b0;
        start = 1'b1;

        @(posedge clk);
        #1;
        start = 1'b0;

        if (!busy || !clear || done) begin
            $fatal(1, "clear state expected busy=1 clear=1 done=0");
        end

        @(posedge clk);
        #1;
        check_zero("clear");

        for (int t = 0; t <= T_MAX; t++) begin
            check_schedule(t);

            @(posedge clk);
            #1;

            $display("t=%0d C=[[ %0d, %0d ], [ %0d, %0d ]]",
                     t, acc_out[0][0], acc_out[0][1],
                     acc_out[1][0], acc_out[1][1]);
        end

        if (!done || busy || clear) begin
            $fatal(1, "done state expected done=1 busy=0 clear=0");
        end

        check_results();

        @(posedge clk);
        #1;

        if (done || busy || clear) begin
            $fatal(1, "idle after done expected done=0 busy=0 clear=0");
        end

        $display("PASS: tb_controller_systolic_2x2");
        $finish;
    end

endmodule
