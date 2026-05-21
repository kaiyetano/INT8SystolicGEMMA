module systolic_array #(
    parameter int N = 2,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int PIPELINE_PRODUCT = 0,
    parameter int PIPELINE_DSP = 0
) (
    input  logic clk,
    input  logic rst,
    input  logic clear,

    input  wire logic signed [DATA_WIDTH-1:0] a_in [N],
    input  wire logic signed [DATA_WIDTH-1:0] b_in [N],
    input  wire logic                         a_valid_in [N],
    input  wire logic                         b_valid_in [N],

    output logic signed [ACC_WIDTH-1:0]  acc_out [N][N]
);

    logic signed [DATA_WIDTH-1:0] a_bus [N][N+1];
    logic signed [DATA_WIDTH-1:0] b_bus [N+1][N];
    logic                         a_valid_bus [N][N+1];
    logic                         b_valid_bus [N+1][N];

    genvar row;
    genvar col;

    generate
        for (row = 0; row < N; row++) begin : gen_a_edges
            assign a_bus[row][0]       = a_in[row];
            assign a_valid_bus[row][0] = a_valid_in[row];
        end

        for (col = 0; col < N; col++) begin : gen_b_edges
            assign b_bus[0][col]       = b_in[col];
            assign b_valid_bus[0][col] = b_valid_in[col];
        end

        for (row = 0; row < N; row++) begin : gen_rows
            for (col = 0; col < N; col++) begin : gen_cols
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH),
                    .PIPELINE_PRODUCT(PIPELINE_PRODUCT),
                    .PIPELINE_DSP(PIPELINE_DSP)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .clear(clear),
                    .a_in(a_bus[row][col]),
                    .b_in(b_bus[row][col]),
                    .a_valid_in(a_valid_bus[row][col]),
                    .b_valid_in(b_valid_bus[row][col]),
                    .a_out(a_bus[row][col+1]),
                    .b_out(b_bus[row+1][col]),
                    .a_valid_out(a_valid_bus[row][col+1]),
                    .b_valid_out(b_valid_bus[row+1][col]),
                    .acc_out(acc_out[row][col])
                );
            end
        end
    endgenerate

endmodule
