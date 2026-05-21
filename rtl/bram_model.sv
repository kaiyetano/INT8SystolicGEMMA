module bram_model #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 2,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic clk,
    input  logic rst,

    input  logic                   write_en,
    input  logic [ADDR_WIDTH-1:0]  write_addr,
    input  logic signed [DATA_WIDTH-1:0] write_data,

    input  logic                   read_en,
    input  logic [ADDR_WIDTH-1:0]  read_addr,
    output logic signed [DATA_WIDTH-1:0] read_data,
    output logic                   read_valid
);

`ifdef SIMULATION

    (* ramstyle = "M10K" *) logic signed [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            read_data  <= '0;
            read_valid <= 1'b0;
        end else begin
            if (write_en) begin
                mem[write_addr] <= write_data;
            end

            read_valid <= read_en;
            if (read_en) begin
                read_data <= mem[read_addr];
            end else begin
                read_data <= '0;
            end
        end
    end

`else

    logic [DATA_WIDTH-1:0] read_data_raw;

    altsyncram #(
        .operation_mode("DUAL_PORT"),
        .intended_device_family("Cyclone V"),
        .ram_block_type("M10K"),
        .width_a(DATA_WIDTH),
        .widthad_a(ADDR_WIDTH),
        .numwords_a(DEPTH),
        .width_b(DATA_WIDTH),
        .widthad_b(ADDR_WIDTH),
        .numwords_b(DEPTH),
        .address_reg_b("CLOCK0"),
        .rdcontrol_reg_b("CLOCK0"),
        .outdata_reg_b("UNREGISTERED"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized("FALSE"),
        .lpm_type("altsyncram")
    ) m10k_ram (
        .clock0(clk),
        .clocken0(1'b1),
        .aclr0(1'b0),
        .address_a(write_addr),
        .data_a(write_data),
        .wren_a(write_en),
        .address_b(read_addr),
        .rden_b(read_en),
        .q_b(read_data_raw),
        .data_b({DATA_WIDTH{1'b0}}),
        .wren_b(1'b0),
        .q_a()
    );

    assign read_data = read_data_raw;

    always_ff @(posedge clk) begin
        if (rst) begin
            read_valid <= 1'b0;
        end else begin
            read_valid <= read_en;
        end
    end

`endif

endmodule
