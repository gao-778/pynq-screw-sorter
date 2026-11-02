if {[version -short] ne "2026.1"} {
    error "This export is validated for Vivado 2026.1; do not silently upgrade IP"
}
set project_dir [file join $build_output_root project]
create_project screw_sort_ui $project_dir -part xc7z020clg400-1
set_property TARGET_LANGUAGE Verilog [current_project]
set_property SIMULATOR_LANGUAGE Mixed [current_project]
set_property DEFAULT_LIB xil_defaultlib [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO XPM_MEMORY} [current_project]
set_property IP_CACHE_PERMISSIONS {read write} [current_project]
set_property include_dirs [list [file join $hardware_source_root rtl]] [get_filesets sources_1]
foreach name $rtl_files {add_files -norecurse [file join $hardware_source_root $name]}
foreach entry $constraint_entries {
    lassign $entry name use_synth use_impl
    set path [file join $hardware_source_root $name]
    add_files -fileset constrs_1 -norecurse $path
    set_property USED_IN_SYNTHESIS $use_synth [get_files $path]
    set_property USED_IN_IMPLEMENTATION $use_impl [get_files $path]
}
foreach name $rom_files {add_files -norecurse [file join $hardware_source_root data $name]}
source [file join $hardware_source_root bd camera_sd_system.tcl]
if {[llength [get_bd_designs -quiet camera_sd_system]] != 1} {error "Block Design recreation failed"}
validate_bd_design
foreach {port width} {o_scene_classes 60 o_scene_boxes 528} {
    set net [get_bd_nets -of_objects [get_bd_pins detection_overlay/$port]]
    foreach pin [get_bd_pins -of_objects $net] {
        if {[expr {[get_property LEFT $pin]-[get_property RIGHT $pin]+1}] != $width} {
            error "Unexpected scene bus width: $pin"
        }
    }
}
save_bd_design
set bd [get_files */camera_sd_system.bd]
set_property synth_checkpoint_mode None $bd
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.SHREG_MIN_SIZE 3 [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD auto [get_runs synth_1]
foreach step {OPT_DESIGN PLACE_DESIGN PHYS_OPT_DESIGN ROUTE_DESIGN} {
    set_property STEPS.${step}.ARGS.DIRECTIVE Explore [get_runs impl_1]
}
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $hardware_source_root tcl check_timing_coverage.tcl] [get_runs impl_1]
set_property STEPS.WRITE_BITSTREAM.TCL.PRE [file join $hardware_source_root tcl check_all_cdc.tcl] [get_runs impl_1]
generate_target all $bd
set wrappers [make_wrapper -files $bd -top]
add_files -norecurse $wrappers
set_property TOP camera_sd_system_wrapper [get_filesets sources_1]
source [file join $hardware_source_root tcl restore_ip_constraints.tcl]
update_compile_order -fileset sources_1
set audit [open [file join $build_output_root source_audit.txt] w]
fconfigure $audit -encoding utf-8
foreach f [get_files -all] {
    set name [file normalize [get_property NAME $f]]
    if {![file exists $name]} {error "Missing source: $name"}
    if {![string match -nocase "${build_output_root}/*" $name]} {error "Source outside output directory: $name"}
    puts $audit $name
}
close $audit
set compile_audit [open [file join $build_output_root compile_sources.txt] w]
foreach f [get_files -compile_order sources -used_in synthesis] {
    puts $compile_audit [get_property NAME $f]
}
close $compile_audit
write_bd_tcl -force [file join $build_output_root recreated_bd.tcl]
set props [open [file join $build_output_root recreated_properties.tsv] w]
foreach p {PART BOARD_PART TARGET_LANGUAGE DEFAULT_LIB XPM_LIBRARIES SIMULATOR_LANGUAGE} {
    puts $props "PROJECT\t$p\t[get_property $p [current_project]]"
}
foreach run {synth_1 impl_1} {
    foreach p [lsort [list_property [get_runs $run]]] {
        if {[string match STEPS.* $p] || $p eq "STRATEGY" || $p eq "FLOW"} {
            puts $props "$run\t$p\t[get_property $p [get_runs $run]]"
        }
    }
}
close $props
launch_runs synth_1 -scripts_only
launch_runs impl_1 -to_step write_bitstream -scripts_only
close_project
puts "MC18_OPEN_SOURCE_PREPARE_PASS"
