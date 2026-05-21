module pe #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int PIPELINE_PRODUCT = 0,
    parameter int PIPELINE_DSP = 0
) (
    input  logic clk,
    input  logic rst,
    input  logic clear,

    input  logic signed [DATA_WIDTH-1:0] a_in,
    input  logic signed [DATA_WIDTH-1:0] b_in,
    input  logic                         a_valid_in,
    input  logic                         b_valid_in,

    output logic signed [DATA_WIDTH-1:0] a_out,
    output logic signed [DATA_WIDTH-1:0] b_out,
    output logic                         a_valid_out,
    output logic                         b_valid_out,
    output logic signed [ACC_WIDTH-1:0]  acc_out
);

    localparam int PRODUCT_WIDTH = 2*DATA_WIDTH;

    logic signed [PRODUCT_WIDTH-1:0] product;
    logic signed [ACC_WIDTH-1:0]     product_ext;

    logic signed [PRODUCT_WIDTH-1:0] product_reg;
    logic                            product_valid_reg;
    logic signed [ACC_WIDTH-1:0]     product_reg_ext;

    logic signed [DATA_WIDTH-1:0]    mult_a_reg;
    logic signed [DATA_WIDTH-1:0]    mult_b_reg;
    logic                            mult_valid_reg;

    assign product = a_in * b_in;
    assign product_ext = {{(ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
    assign product_reg_ext = {{(ACC_WIDTH-PRODUCT_WIDTH){product_reg[PRODUCT_WIDTH-1]}}, product_reg};

    always_ff @(posedge clk) begin
        if (rst) begin
            a_out             <= '0;
            b_out             <= '0;
            a_valid_out       <= 1'b0;
            b_valid_out       <= 1'b0;
            acc_out           <= '0;
            product_reg       <= '0;
            product_valid_reg <= 1'b0;
            mult_a_reg        <= '0;
            mult_b_reg        <= '0;
            mult_valid_reg    <= 1'b0;
        end else begin
            a_out       <= a_in;
            b_out       <= b_in;
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;

            if (clear) begin
                acc_out           <= '0;
                product_reg       <= '0;
                product_valid_reg <= 1'b0;
                mult_a_reg        <= '0;
                mult_b_reg        <= '0;
                mult_valid_reg    <= 1'b0;
            end else if (PIPELINE_DSP) begin
                mult_a_reg        <= a_in;
                mult_b_reg        <= b_in;
                mult_valid_reg    <= a_valid_in && b_valid_in;
                product_reg       <= mult_a_reg * mult_b_reg;
                product_valid_reg <= mult_valid_reg;

                if (product_valid_reg) begin
                    acc_out <= acc_out + product_reg_ext;
                end
            end else if (PIPELINE_PRODUCT) begin
                product_reg       <= product;
                product_valid_reg <= a_valid_in && b_valid_in;
                mult_a_reg        <= '0;
                mult_b_reg        <= '0;
                mult_valid_reg    <= 1'b0;

                if (product_valid_reg) begin
                    acc_out <= acc_out + product_reg_ext;
                end
            end else begin
                product_reg       <= '0;
                product_valid_reg <= 1'b0;
                mult_a_reg        <= '0;
                mult_b_reg        <= '0;
                mult_valid_reg    <= 1'b0;

                if (a_valid_in && b_valid_in) begin
                    acc_out <= acc_out + product_ext;
                end
            end
        end
    end

endmodule
