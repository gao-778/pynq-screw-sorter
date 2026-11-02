set run_meta [get_pins -hier -regexp {.*preview_ddr/inst/reg_run_camera_reg\[0\]/D}]
set_false_path -to $run_meta
