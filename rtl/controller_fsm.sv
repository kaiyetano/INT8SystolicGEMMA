module controller_fsm #(
    parameter int N = 2,
    parameter int PIPELINE_PRODUCT = 0,
    parameter int PIPELINE_DSP = 0,
    parameter int INDEX_WIDTH = (N <= 1) ? 1 : $clog2(N),
    parameter int C_DEPTH = N*N,
    parameter int C_ADDR_WIDTH = (C_DEPTH <= 1) ? 1 : $clog2(C_DEPTH)
) (
    input  logic clk,
    input  logic rst,
    input  logic start,

    output logic busy,
    output logic done,
    output logic clear_array,

    output logic [INDEX_WIDTH-1:0] a_read_col [N],
    output logic                   a_read_en  [N],
    output logic [INDEX_WIDTH-1:0] b_read_row [N],
    output logic                   b_read_en  [N],

    output logic                   c_write_en,
    output logic [C_ADDR_WIDTH-1:0] c_write_addr,
    output logic [INDEX_WIDTH-1:0] c_write_row,
    output logic [INDEX_WIDTH-1:0] c_write_col
);

    localparam int PE_PIPELINE_LATENCY = (PIPELINE_DSP != 0) ? 2 : PIPELINE_PRODUCT;
    localparam int T_MAX       = 3*N - 3 + PE_PIPELINE_LATENCY;
    localparam int T_WIDTH     = (T_MAX <= 0) ? 1 : $clog2(T_MAX + 1);

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_CLEAR,
        STATE_RUN,
        STATE_WRITE_OUTPUT,
        STATE_WRITE_FLUSH1,
        STATE_WRITE_FLUSH2,
        STATE_DONE
    } state_t;

    state_t state;
    logic [T_WIDTH-1:0] t_count;
    logic [C_ADDR_WIDTH-1:0] c_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= STATE_IDLE;
            t_count <= '0;
            c_count <= '0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    t_count <= '0;
                    c_count <= '0;
                    if (start) begin
                        state <= STATE_CLEAR;
                    end
                end

                STATE_CLEAR: begin
                    t_count <= '0;
                    c_count <= '0;
                    state   <= STATE_RUN;
                end

                STATE_RUN: begin
                    if (int'(t_count) == T_MAX) begin
                        c_count <= '0;
                        state   <= STATE_WRITE_OUTPUT;
                    end else begin
                        t_count <= t_count + 1'b1;
                    end
                end

                STATE_WRITE_OUTPUT: begin
                    if (int'(c_count) == (C_DEPTH - 1)) begin
                        state <= STATE_WRITE_FLUSH1;
                    end else begin
                        c_count <= c_count + 1'b1;
                    end
                end

                STATE_WRITE_FLUSH1: begin
                    state <= STATE_WRITE_FLUSH2;
                end

                STATE_WRITE_FLUSH2: begin
                    state <= STATE_DONE;
                end

                STATE_DONE: begin
                    t_count <= '0;
                    c_count <= '0;
                    state   <= STATE_IDLE;
                end

                default: begin
                    state   <= STATE_IDLE;
                    t_count <= '0;
                    c_count <= '0;
                end
            endcase
        end
    end

    always_comb begin
        int c_row_idx;
        int c_col_idx;

        busy        = (state == STATE_CLEAR) || (state == STATE_RUN) ||
                      (state == STATE_WRITE_OUTPUT) ||
                      (state == STATE_WRITE_FLUSH1) ||
                      (state == STATE_WRITE_FLUSH2);
        done        = (state == STATE_DONE);
        clear_array = (state == STATE_CLEAR);
        c_write_en  = (state == STATE_WRITE_OUTPUT);
        c_write_addr = '0;
        c_write_row  = '0;
        c_write_col  = '0;

        for (int row = 0; row < N; row++) begin
            a_read_col[row] = '0;
            a_read_en[row]  = 1'b0;
        end

        for (int col = 0; col < N; col++) begin
            b_read_row[col] = '0;
            b_read_en[col]  = 1'b0;
        end

        if (state == STATE_RUN) begin
            for (int row = 0; row < N; row++) begin
                int k_a;

                k_a = int'(t_count) - row;
                if ((k_a >= 0) && (k_a < N)) begin
                    a_read_col[row] = k_a[INDEX_WIDTH-1:0];
                    a_read_en[row]  = 1'b1;
                end
            end

            for (int col = 0; col < N; col++) begin
                int k_b;

                k_b = int'(t_count) - col;
                if ((k_b >= 0) && (k_b < N)) begin
                    b_read_row[col] = k_b[INDEX_WIDTH-1:0];
                    b_read_en[col]  = 1'b1;
                end
            end
        end

        if (state == STATE_WRITE_OUTPUT) begin
            c_row_idx = int'(c_count) / N;
            c_col_idx = int'(c_count) % N;

            c_write_addr = c_count;
            c_write_row  = c_row_idx[INDEX_WIDTH-1:0];
            c_write_col  = c_col_idx[INDEX_WIDTH-1:0];
        end
    end

endmodule
