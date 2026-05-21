if {![info exists TOP]} {
    set TOP tb_matrix_accelerator
}

if {![info exists RTL_SRCS]} {
    set RTL_SRCS {rtl/bram_model.sv rtl/pe.sv rtl/systolic_array.sv rtl/controller_fsm.sv rtl/matrix_accelerator.sv}
}

if {![info exists TB_SRCS]} {
    set TB_SRCS {tb/tb_matrix_accelerator.sv}
}

if {![info exists VSIM_ARGS]} {
    set VSIM_ARGS {}
}

set WORK_LIB work

if {![file exists $WORK_LIB]} {
    vlib $WORK_LIB
}
vmap $WORK_LIB $WORK_LIB

foreach src [concat $RTL_SRCS $TB_SRCS] {
    if {![file exists $src]} {
        error "Missing simulation source: $src"
    }

    vlog -sv +define+SIMULATION $src
}

eval vsim $VSIM_ARGS $TOP

view wave

add wave -divider "Clock and Control"
add wave -radix binary /$TOP/clk
add wave -radix binary /$TOP/rst
add wave -radix binary /$TOP/start
add wave -radix binary /$TOP/busy
add wave -radix binary /$TOP/done

add wave -divider "BRAM Write Ports"
add wave -radix binary  /$TOP/a_write_en
add wave -radix unsigned /$TOP/a_write_row
add wave -radix unsigned /$TOP/a_write_col
add wave -radix decimal /$TOP/a_write_data
add wave -radix binary  /$TOP/b_write_en
add wave -radix unsigned /$TOP/b_write_row
add wave -radix unsigned /$TOP/b_write_col
add wave -radix decimal /$TOP/b_write_data

add wave -divider "BRAM C Read Port"
add wave -radix binary   /$TOP/c_read_en
add wave -radix unsigned /$TOP/c_read_addr
add wave -radix decimal  /$TOP/c_read_data
add wave -radix binary   /$TOP/c_read_valid

add wave -divider "Controller Schedule"
add wave -radix binary   /$TOP/dut/clear_array
add wave -radix unsigned /$TOP/dut/a_read_col
add wave -radix binary   /$TOP/dut/a_read_en
add wave -radix unsigned /$TOP/dut/b_read_row
add wave -radix binary   /$TOP/dut/b_read_en
add wave -radix binary   /$TOP/dut/c_write_en
add wave -radix unsigned /$TOP/dut/c_write_addr
add wave -radix unsigned /$TOP/dut/c_write_row
add wave -radix unsigned /$TOP/dut/c_write_col

add wave -divider "Edge Inputs"
add wave -radix decimal /$TOP/dut/a_array_in
add wave -radix decimal /$TOP/dut/b_array_in
add wave -radix binary  /$TOP/dut/a_array_valid
add wave -radix binary  /$TOP/dut/b_array_valid

add wave -divider "Expected and Accumulated C"
add wave -radix decimal /$TOP/c_expected
add wave -radix decimal /$TOP/acc_out

add wave -divider "Array Internal Buses"
add wave -radix decimal /$TOP/dut/systolic/a_bus
add wave -radix decimal /$TOP/dut/systolic/b_bus
add wave -radix binary  /$TOP/dut/systolic/a_valid_bus
add wave -radix binary  /$TOP/dut/systolic/b_valid_bus

run -all
wave zoom full
