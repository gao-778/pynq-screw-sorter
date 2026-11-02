set check_dir [file dirname [info script]]
foreach check {check_hd_cdc.tcl check_hide_cdc.tcl check_timing_coverage.tcl check_final_timing.tcl} {
    source [file join $check_dir $check]
}
