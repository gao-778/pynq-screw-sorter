# Toggle synchronizers: only the first synchronizer stage is asynchronous.
set preview_sync [get_pins -hier -regexp {.*preview_ddr/inst/reg_(request|response|offer|accept)_sync_reg\[0\]/D}]
set_false_path -to $preview_sync
# Observational event/status synchronizers. Only the first receiving stage is
# asynchronous; their data never feed the recognition or movement decisions.
set preview_metric_sync [get_pins -hier -regexp {.*preview_ddr/inst/reg_(camera_frame|camera_overflow|underflow)_sync_reg\[0\]/D}]
set_false_path -to $preview_metric_sync
# Reset asserts asynchronously, then releases through three local clock flops.
# Only their asynchronous clear pins are excepted, not data/clock paths.
set_false_path -to [get_pins -hier -regexp {.*preview_ddr/inst/reg_(cam|video)_reset_reg\[[0-2]\]/CLR}]
# Bundled data remain held until the synchronized acknowledgement. Bound the
# propagation to 20 ns, below the three-stage handshake settling interval.
set preview_to_axi [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*preview_ddr/inst/reg_read_(row|base)_reg.*}]
set preview_row_source [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*preview_ddr/inst/reg_request_row_reg.*}]
set preview_video_clock [get_clocks -of_objects [get_pins -of_objects $preview_row_source -filter {REF_PIN_NAME == C}]]
set_max_delay -datapath_only 20.000 -from $preview_video_clock -to $preview_to_axi
set preview_to_video [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*preview_ddr/inst/(flag_front_bank|flag_request_bank|reg_line_valid|flag_display_ready)_reg.*}]
set_max_delay -datapath_only 20.000 -from [get_clocks clk_fpga_0] -to $preview_to_video
