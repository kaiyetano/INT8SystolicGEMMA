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

eval vsim -c $VSIM_ARGS $TOP
run -all

if {[coverage attribute -name TESTSTATUS -concise] != 0} {
    quit -code 1 -f
}

quit -code 0 -f
