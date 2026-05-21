module post_process #(
    parameter int ACC_WIDTH = 32,
    parameter bit ENABLE_RELU = 1
) (
    input  logic signed [ACC_WIDTH-1:0] acc_in,
    input  logic signed [ACC_WIDTH-1:0] bias_in,
    output logic signed [ACC_WIDTH-1:0] y_out
);

    logic signed [ACC_WIDTH-1:0] biased;

    always_comb begin
        biased = acc_in + bias_in;

        if (ENABLE_RELU && (biased < 0)) begin
            y_out = '0;
        end else begin
            y_out = biased;
        end
    end

endmodule
