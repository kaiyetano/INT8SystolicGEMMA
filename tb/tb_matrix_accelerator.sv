`timescale 1ns/1ps

module tb_matrix_accelerator #(
    parameter int N = 2,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int PIPELINE_PRODUCT = 0,
    parameter int PIPELINE_DSP = 0,
    parameter bit ENABLE_BIAS = 1,
    parameter bit ENABLE_RELU = 1,
    parameter int INDEX_WIDTH = (N <= 1) ? 1 : $clog2(N),
    parameter int C_DEPTH = N*N,
    parameter int C_ADDR_WIDTH = (C_DEPTH <= 1) ? 1 : $clog2(C_DEPTH)
);

    logic clk;
    logic rst;
    logic start;
    logic busy;
    logic done;

    logic                         a_write_en;
    logic [INDEX_WIDTH-1:0]       a_write_row;
    logic [INDEX_WIDTH-1:0]       a_write_col;
    logic signed [DATA_WIDTH-1:0] a_write_data;

    logic                         b_write_en;
    logic [INDEX_WIDTH-1:0]       b_write_row;
    logic [INDEX_WIDTH-1:0]       b_write_col;
    logic signed [DATA_WIDTH-1:0] b_write_data;

    logic                         bias_write_en;
    logic [INDEX_WIDTH-1:0]       bias_write_col;
    logic signed [ACC_WIDTH-1:0]  bias_write_data;

    logic                         c_read_en;
    logic [C_ADDR_WIDTH-1:0]      c_read_addr;
    logic signed [ACC_WIDTH-1:0]  c_read_data;
    logic                         c_read_valid;

    logic signed [ACC_WIDTH-1:0] acc_out [N][N];

    logic signed [DATA_WIDTH-1:0] a_vector [0:C_DEPTH-1];
    logic signed [DATA_WIDTH-1:0] b_vector [0:C_DEPTH-1];
    logic signed [ACC_WIDTH-1:0]  bias_vector [0:N-1];
    logic signed [ACC_WIDTH-1:0]  c_expected [0:C_DEPTH-1];

    string vec_dir;
    string test_name;

    matrix_accelerator #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .PIPELINE_PRODUCT(PIPELINE_PRODUCT),
        .PIPELINE_DSP(PIPELINE_DSP),
        .ENABLE_BIAS(ENABLE_BIAS),
        .ENABLE_RELU(ENABLE_RELU),
        .INDEX_WIDTH(INDEX_WIDTH),
        .C_DEPTH(C_DEPTH),
        .C_ADDR_WIDTH(C_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_write_en(a_write_en),
        .a_write_row(a_write_row),
        .a_write_col(a_write_col),
        .a_write_data(a_write_data),
        .b_write_en(b_write_en),
        .b_write_row(b_write_row),
        .b_write_col(b_write_col),
        .b_write_data(b_write_data),
        .bias_write_en(bias_write_en),
        .bias_write_col(bias_write_col),
        .bias_write_data(bias_write_data),
        .c_read_en(c_read_en),
        .c_read_addr(c_read_addr),
        .c_read_data(c_read_data),
        .c_read_valid(c_read_valid),
        .busy(busy),
        .done(done),
        .acc_out(acc_out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic drive_idle;
        begin
            a_write_en   = 1'b0;
            a_write_row  = '0;
            a_write_col  = '0;
            a_write_data = '0;

            b_write_en   = 1'b0;
            b_write_row  = '0;
            b_write_col  = '0;
            b_write_data = '0;

            bias_write_en   = 1'b0;
            bias_write_col  = '0;
            bias_write_data = '0;

            c_read_en    = 1'b0;
            c_read_addr  = '0;
        end
    endtask

    task automatic write_operands(
        input int row,
        input int col,
        input logic signed [DATA_WIDTH-1:0] a_value,
        input logic signed [DATA_WIDTH-1:0] b_value
    );
        begin
            @(negedge clk);
            a_write_en   = 1'b1;
            a_write_row  = row[INDEX_WIDTH-1:0];
            a_write_col  = col[INDEX_WIDTH-1:0];
            a_write_data = a_value;

            b_write_en   = 1'b1;
            b_write_row  = row[INDEX_WIDTH-1:0];
            b_write_col  = col[INDEX_WIDTH-1:0];
            b_write_data = b_value;

            bias_write_en   = 1'b0;
            bias_write_col  = '0;
            bias_write_data = '0;

            c_read_en    = 1'b0;
            c_read_addr  = '0;

            @(posedge clk);
            #1;
        end
    endtask

    task automatic write_bias(
        input int col,
        input logic signed [ACC_WIDTH-1:0] bias_value
    );
        begin
            @(negedge clk);
            a_write_en      = 1'b0;
            b_write_en      = 1'b0;
            bias_write_en   = 1'b1;
            bias_write_col  = col[INDEX_WIDTH-1:0];
            bias_write_data = bias_value;
            c_read_en       = 1'b0;
            c_read_addr     = '0;

            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_accumulators_zero(input string label);
        begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    if (acc_out[row][col] !== '0) begin
                        $fatal(1, "%s: acc_out[%0d][%0d] expected 0, got %0d",
                               label, row, col, acc_out[row][col]);
                    end
                end
            end
        end
    endtask

    task automatic check_c_memory;
        logic signed [ACC_WIDTH-1:0] expected;
        begin
            for (int addr = 0; addr < C_DEPTH; addr++) begin
                @(negedge clk);
                c_read_en   = 1'b1;
                c_read_addr = addr[C_ADDR_WIDTH-1:0];

                @(posedge clk);
                #1;

                expected = c_expected[addr];
                if (!c_read_valid) begin
                    $fatal(1, "BRAM_C addr %0d: c_read_valid expected 1", addr);
                end

                if (c_read_data !== expected) begin
                    $fatal(1, "BRAM_C addr %0d expected %0d, got %0d",
                           addr, expected, c_read_data);
                end
            end

            @(negedge clk);
            c_read_en   = 1'b0;
            c_read_addr = '0;
        end
    endtask

    initial begin
        int cycle_count;
        int addr;

        if (!$value$plusargs("VEC_DIR=%s", vec_dir)) begin
            vec_dir = $sformatf("vectors/N%0d/signed_basic", N);
        end

        if (!$value$plusargs("TEST=%s", test_name)) begin
            test_name = "signed_basic";
        end

        $display("Loading vectors: N=%0d TEST=%s PIPELINE_PRODUCT=%0d PIPELINE_DSP=%0d ENABLE_BIAS=%0d ENABLE_RELU=%0d VEC_DIR=%s",
                 N, test_name, PIPELINE_PRODUCT, PIPELINE_DSP,
                 ENABLE_BIAS, ENABLE_RELU, vec_dir);
        $readmemh($sformatf("%s/A.hex", vec_dir), a_vector);
        $readmemh($sformatf("%s/B.hex", vec_dir), b_vector);
        $readmemh($sformatf("%s/bias.hex", vec_dir), bias_vector);
        $readmemh($sformatf("%s/C_expected.hex", vec_dir), c_expected);

        rst   = 1'b1;
        start = 1'b0;
        drive_idle();

        repeat (2) @(posedge clk);
        #1;
        check_accumulators_zero("reset");

        @(negedge clk);
        rst = 1'b0;

        for (int row = 0; row < N; row++) begin
            for (int col = 0; col < N; col++) begin
                addr = row*N + col;
                write_operands(row, col, a_vector[addr], b_vector[addr]);
            end
        end

        for (int col = 0; col < N; col++) begin
            write_bias(col, bias_vector[col]);
        end

        @(negedge clk);
        drive_idle();
        start = 1'b1;

        @(posedge clk);
        #1;
        start = 1'b0;

        cycle_count = 0;
        while (!done) begin
            @(posedge clk);
            #1;
            cycle_count++;

            if (cycle_count > (8*N + C_DEPTH + 16)) begin
                $fatal(1, "Timed out waiting for done");
            end
        end

        check_c_memory();

        @(posedge clk);
        #1;
        if (done || busy) begin
            $fatal(1, "idle after done expected done=0 busy=0");
        end

        $display("PASS: tb_matrix_accelerator N=%0d TEST=%s PIPELINE_PRODUCT=%0d PIPELINE_DSP=%0d ENABLE_BIAS=%0d ENABLE_RELU=%0d",
                 N, test_name, PIPELINE_PRODUCT, PIPELINE_DSP,
                 ENABLE_BIAS, ENABLE_RELU);
        $finish;
    end

endmodule
