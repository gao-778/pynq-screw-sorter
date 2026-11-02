set_false_path -to [get_pins -hier -regexp {.*dashboard/inst/reg_(scene|front|text|axes)_sync_reg\[0\]/D}]
set_false_path -to [get_pins -hier -regexp {.*screen_capture/inst/arm_sync_reg\[0\]/D}]
set_false_path -to [get_pins -hier -regexp {.*screen_capture/inst/reg_local_reset_reg\[[0-2]\]/CLR}]
set_false_path -to [get_pins -hier -regexp {.*snapshot_control/inst/screenshot_meta_reg.*\/D}]
set scene_source [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*detection_overlay/inst/o_scene_(classes|count|valid)_reg.*}]
set scene_destination [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/(reg_classes|reg_pending_count|flag_pending_valid)_reg.*}]
set_max_delay -datapath_only 20.000 -from $scene_source -to $scene_destination
set_bus_skew 10.000 -from $scene_source -to $scene_destination
