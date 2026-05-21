module matrix_accelerator #(
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
) (
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic                         a_write_en,
    input  logic [INDEX_WIDTH-1:0]       a_write_row,
    input  logic [INDEX_WIDTH-1:0]       a_write_col,
    input  logic signed [DATA_WIDTH-1:0] a_write_data,

    input  logic                         b_write_en,
    input  logic [INDEX_WIDTH-1:0]       b_write_row,
    input  logic [INDEX_WIDTH-1:0]       b_write_col,
    input  logic signed [DATA_WIDTH-1:0] b_write_data,

    input  logic                         bias_write_en,
    input  logic [INDEX_WIDTH-1:0]       bias_write_col,
    input  logic signed [ACC_WIDTH-1:0]  bias_write_data,

    input  logic                         c_read_en,
    input  logic [C_ADDR_WIDTH-1:0]      c_read_addr,
    output logic signed [ACC_WIDTH-1:0]  c_read_data,
    output logic                         c_read_valid,

    output logic busy,
    output logic done,
    output logic signed [ACC_WIDTH-1:0] acc_out [N][N]
);

    logic ctrl_busy;
    logic ctrl_done;
    logic clear_array;

    logic [INDEX_WIDTH-1:0] a_read_col [N];
    logic                   a_read_en  [N];
    logic [INDEX_WIDTH-1:0] b_read_row [N];
    logic                   b_read_en  [N];

    logic                   c_write_en;
    logic [C_ADDR_WIDTH-1:0] c_write_addr;
    logic [INDEX_WIDTH-1:0] c_write_row;
    logic [INDEX_WIDTH-1:0] c_write_col;
    logic signed [ACC_WIDTH-1:0] c_write_data;
    logic signed [ACC_WIDTH-1:0] c_bias_value;
    logic signed [ACC_WIDTH-1:0] c_processed_data;
    logic                        c_write_en_stage1;
    logic [C_ADDR_WIDTH-1:0]     c_write_addr_stage1;
    logic signed [ACC_WIDTH-1:0] c_acc_stage1;
    logic signed [ACC_WIDTH-1:0] c_bias_stage1;
    logic                        c_write_en_stage2;
    logic [C_ADDR_WIDTH-1:0]     c_write_addr_stage2;
    logic signed [ACC_WIDTH-1:0] c_processed_data_stage2;

    logic signed [DATA_WIDTH-1:0] a_array_in [N];
    logic signed [DATA_WIDTH-1:0] b_array_in [N];
    logic                         a_array_valid [N];
    logic                         b_array_valid [N];
    logic signed [ACC_WIDTH-1:0]  bias_mem [N];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int col_idx = 0; col_idx < N; col_idx++) begin
                bias_mem[col_idx] <= '0;
            end
        end else if (bias_write_en) begin
            bias_mem[int'(bias_write_col)] <= bias_write_data;
        end
    end

    controller_fsm #(
        .N(N),
        .PIPELINE_PRODUCT(PIPELINE_PRODUCT),
        .PIPELINE_DSP(PIPELINE_DSP),
        .INDEX_WIDTH(INDEX_WIDTH),
        .C_DEPTH(C_DEPTH),
        .C_ADDR_WIDTH(C_ADDR_WIDTH)
    ) ctrl (
        .clk(clk),
        .rst(rst),
        .start(start),
        .busy(ctrl_busy),
        .done(ctrl_done),
        .clear_array(clear_array),
        .a_read_col(a_read_col),
        .a_read_en(a_read_en),
        .b_read_row(b_read_row),
        .b_read_en(b_read_en),
        .c_write_en(c_write_en),
        .c_write_addr(c_write_addr),
        .c_write_row(c_write_row),
        .c_write_col(c_write_col)
    );

    genvar row;
    genvar col;

    generate
        for (row = 0; row < N; row++) begin : gen_a_banks
            logic row_write_en;

            assign row_write_en = a_write_en && (int'(a_write_row) == row);

            bram_model #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(N),
                .ADDR_WIDTH(INDEX_WIDTH)
            ) a_mem (
                .clk(clk),
                .rst(rst),
                .write_en(row_write_en),
                .write_addr(a_write_col),
                .write_data(a_write_data),
                .read_en(a_read_en[row]),
                .read_addr(a_read_col[row]),
                .read_data(a_array_in[row]),
                .read_valid(a_array_valid[row])
            );
        end

        for (col = 0; col < N; col++) begin : gen_b_banks
            logic col_write_en;

            assign col_write_en = b_write_en && (int'(b_write_col) == col);

            bram_model #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(N),
                .ADDR_WIDTH(INDEX_WIDTH)
            ) b_mem (
                .clk(clk),
                .rst(rst),
                .write_en(col_write_en),
                .write_addr(b_write_row),
                .write_data(b_write_data),
                .read_en(b_read_en[col]),
                .read_addr(b_read_row[col]),
                .read_data(b_array_in[col]),
                .read_valid(b_array_valid[col])
            );
        end
    endgenerate

    systolic_array #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .PIPELINE_PRODUCT(PIPELINE_PRODUCT),
        .PIPELINE_DSP(PIPELINE_DSP)
    ) systolic (
        .clk(clk),
        .rst(rst),
        .clear(clear_array),
        .a_in(a_array_in),
        .b_in(b_array_in),
        .a_valid_in(a_array_valid),
        .b_valid_in(b_array_valid),
        .acc_out(acc_out)
    );

    assign c_bias_value = ENABLE_BIAS ? bias_mem[int'(c_write_col)] : '0;

    post_process #(
        .ACC_WIDTH(ACC_WIDTH),
        .ENABLE_RELU(ENABLE_RELU)
    ) output_post_process (
        .acc_in(c_acc_stage1),
        .bias_in(c_bias_stage1),
        .y_out(c_processed_data)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            c_write_en_stage1       <= 1'b0;
            c_write_addr_stage1     <= '0;
            c_acc_stage1            <= '0;
            c_bias_stage1           <= '0;
            c_write_en_stage2       <= 1'b0;
            c_write_addr_stage2     <= '0;
            c_processed_data_stage2 <= '0;
        end else begin
            c_write_en_stage1       <= c_write_en;
            c_write_addr_stage1     <= c_write_addr;
            c_acc_stage1            <= acc_out[c_write_row][c_write_col];
            c_bias_stage1           <= c_bias_value;

            c_write_en_stage2       <= c_write_en_stage1;
            c_write_addr_stage2     <= c_write_addr_stage1;
            c_processed_data_stage2 <= c_processed_data;
        end
    end

    // BRAM_C stores raw C when post-processing is disabled, or final Y when
    // bias/ReLU post-processing is enabled.
    assign c_write_data = c_processed_data_stage2;

    bram_model #(
        .DATA_WIDTH(ACC_WIDTH),
        .DEPTH(C_DEPTH),
        .ADDR_WIDTH(C_ADDR_WIDTH)
    ) c_mem (
        .clk(clk),
        .rst(rst),
        .write_en(c_write_en_stage2),
        .write_addr(c_write_addr_stage2),
        .write_data(c_write_data),
        .read_en(c_read_en),
        .read_addr(c_read_addr),
        .read_data(c_read_data),
        .read_valid(c_read_valid)
    );

    assign done = ctrl_done;
    assign busy = ctrl_busy;

endmodule
