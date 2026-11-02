set overlay_capture [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*detection_overlay/inst/reg_(xmin|xmax|ymin|ymax|lxmin|lxmax|lymin|lymax|class|angle|count|total_count)_reg.*}]
set_max_delay -datapath_only 20.000 -from [get_clocks clk_fpga_0] -to $overlay_capture
set_false_path -to [get_pins -hier -regexp {.*detection_overlay/inst/reg_done_sync_reg\[0\]/D}]
set capture_sync [get_pins -hier -regexp {.*recognition/inst/frame_snapshot_Inst/reg_(request|complete|error|started)_sync_reg\[0\]/D}]
set_false_path -to $capture_sync
set capture_reset_clr [get_pins -hier -regexp {.*recognition/inst/frame_snapshot_Inst/reg_camera_reset_reg\[[0-1]\]/CLR}]
set_false_path -to $capture_reset_clr
