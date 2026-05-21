load_package flow

proc env_or_default {name default_value} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default_value
}

proc normalize_mode {mode} {
    switch -exact -- $mode {
        map -
        synth -
        synth_only {
            return synth_only
        }
        compile -
        full_compile {
            return full_compile
        }
        default {
            error "Unknown QUARTUS_MODE '$mode'. Use 'synth_only' or 'full_compile'."
        }
    }
}

proc family_for_part {part} {
    set upper_part [string toupper $part]

    if {[string match "5C*" $upper_part]} {
        return "Cyclone V"
    }

    if {[string match "10A*" $upper_part]} {
        return "Arria 10"
    }

    return ""
}

proc strip_qsf_parameters {qsf_file parameter_names} {
    if {![file exists $qsf_file]} {
        return
    }

    set input [open $qsf_file r]
    set lines [split [read $input] "\n"]
    close $input

    set output_lines [list]
    foreach line $lines {
        set keep_line 1

        foreach param $parameter_names {
            if {[string match "set_parameter -name $param *" $line]} {
                set keep_line 0
            }
        }

        if {$keep_line} {
            lappend output_lines $line
        }
    }

    set output [open $qsf_file w]
    puts -nonewline $output [join $output_lines "\n"]
    close $output
}

set project INT8SystolicGEMMA
set revision $project
set mode [env_or_default QUARTUS_MODE synth_only]
set top [env_or_default SYNTH_TOP ""]
set part [env_or_default PART ""]
set n_value [env_or_default N ""]
set pipeline_product [env_or_default PIPELINE_PRODUCT ""]
set pipeline_dsp [env_or_default PIPELINE_DSP ""]
set enable_bias [env_or_default ENABLE_BIAS ""]
set enable_relu [env_or_default ENABLE_RELU ""]

if {[llength $argv] >= 1} {
    set project [lindex $argv 0]
}

if {[llength $argv] >= 2} {
    set revision [lindex $argv 1]
}

if {[llength $argv] >= 3} {
    set mode [lindex $argv 2]
}

if {[llength $argv] >= 4} {
    set top [lindex $argv 3]
}

if {[llength $argv] >= 5} {
    set part [lindex $argv 4]
}

if {[llength $argv] >= 6} {
    set n_value [lindex $argv 5]
}

if {[llength $argv] >= 7} {
    set pipeline_product [lindex $argv 6]
}

if {[llength $argv] >= 8} {
    set pipeline_dsp [lindex $argv 7]
}

if {[llength $argv] >= 9} {
    set enable_bias [lindex $argv 8]
}

if {[llength $argv] >= 10} {
    set enable_relu [lindex $argv 9]
}

set mode [normalize_mode $mode]

if {![file exists "$project.qpf"]} {
    error "Quartus project file not found: $project.qpf"
}

puts "Quartus project: $project"
puts "Quartus revision: $revision"
puts "Quartus mode: $mode"

if {$top ne ""} {
    puts "Temporary top override: $top"
}

if {$part ne ""} {
    puts "Temporary device override: $part"
}

set parameter_overrides [list]

if {$n_value ne ""} {
    lappend parameter_overrides N $n_value
}

if {$pipeline_product ne ""} {
    lappend parameter_overrides PIPELINE_PRODUCT $pipeline_product
}

if {$pipeline_dsp ne ""} {
    lappend parameter_overrides PIPELINE_DSP $pipeline_dsp
}

if {$enable_bias ne ""} {
    lappend parameter_overrides ENABLE_BIAS $enable_bias
}

if {$enable_relu ne ""} {
    lappend parameter_overrides ENABLE_RELU $enable_relu
}

if {[llength $parameter_overrides] > 0} {
    puts "Temporary parameter overrides:"
    foreach {param value} $parameter_overrides {
        puts "  $param=$value"
    }
}

project_open -revision $revision $project

set original_top [get_global_assignment -name TOP_LEVEL_ENTITY]
set original_device [get_global_assignment -name DEVICE]
set original_family [get_global_assignment -name FAMILY]
set original_parameters [list]
set parameters_to_strip [list]
set changed_assignments 0

if {$top ne ""} {
    set_global_assignment -name TOP_LEVEL_ENTITY $top
    set changed_assignments 1
}

if {$part ne ""} {
    set_global_assignment -name DEVICE $part

    set part_family [family_for_part $part]
    if {$part_family ne ""} {
        set_global_assignment -name FAMILY $part_family
    }

    set changed_assignments 1
}

foreach {param value} $parameter_overrides {
    set had_parameter 1
    set original_value ""

    if {[catch {set original_value [get_parameter_value "" "" $param]}]} {
        set had_parameter 0
    }

    lappend original_parameters $param $had_parameter $original_value
    set_parameter -name $param $value
    set changed_assignments 1
}

if {$changed_assignments} {
    export_assignments
}

set run_status [catch {
    if {$mode eq "synth_only"} {
        execute_module -tool map
    } elseif {$mode eq "full_compile"} {
        execute_flow -compile
    }
} run_result run_options]

if {$changed_assignments} {
    if {$original_top ne ""} {
        set_global_assignment -name TOP_LEVEL_ENTITY $original_top
    }

    if {$original_device ne ""} {
        set_global_assignment -name DEVICE $original_device
    }

    if {$original_family ne ""} {
        set_global_assignment -name FAMILY $original_family
    }

    foreach {param had_parameter original_value} $original_parameters {
        if {$had_parameter} {
            set_parameter -name $param $original_value
        } else {
            lappend parameters_to_strip $param
        }
    }

    export_assignments
}

project_close

if {[llength $parameters_to_strip] > 0} {
    strip_qsf_parameters "$revision.qsf" $parameters_to_strip
}

if {$run_status != 0} {
    puts stderr "Quartus $mode failed."

    if {$part ne ""} {
        puts stderr "Requested DEVICE=$part."
        puts stderr "If this Arria 10 part is unavailable in this Quartus installation, rerun with ARRIA10_PART=<valid_device_name>."
        puts stderr "Arria 10 support may also require a Quartus edition/device package that includes the selected part."
    }

    return -options $run_options $run_result
}
