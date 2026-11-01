set capture_sync [get_pins -hier -regexp {.*recognition/inst/frame_snapshot_Inst/reg_(request|complete|error|started)_sync_reg\[0\]/D}]
if {[llength $capture_sync]!=4} {error "Capture CDC endpoints must be four"}
set capture_reset_clr [get_pins -hier -regexp {.*recognition/inst/frame_snapshot_Inst/reg_camera_reset_reg\[[0-1]\]/CLR}]
if {[llength $capture_reset_clr]!=2} {error "Capture reset endpoints must be two"}
puts "HD_CDC_ENDPOINTS_PASS"
set scene_source [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*detection_overlay/inst/o_scene_(classes|count|valid)_reg.*}]
set scene_destination [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/(reg_classes|reg_pending_count|flag_pending_valid)_reg.*}]
if {[llength $scene_source]==0 || [llength $scene_destination]==0} {error "Dashboard scene CDC endpoints missing"}
foreach pattern {
    {.*dashboard/inst/reg_(scene|front|text|axes)_sync_reg\[0\]/D}
    {.*screen_capture/inst/arm_sync_reg\[0\]/D}
    {.*screen_capture/inst/reg_local_reset_reg\[[0-2]\]/CLR}
    {.*snapshot_control/inst/screenshot_meta_reg.*\/D}
} {
    if {[llength [get_pins -hier -regexp $pattern]]==0} {error "Dashboard CDC endpoints missing: $pattern"}
}
puts "DASHBOARD_CDC_ENDPOINTS_PASS"
set text_bram [get_cells -hier -filter {IS_PRIMITIVE == 1 && NAME =~ *dashboard_text_bram* && REF_NAME =~ RAMB*}]
if {[llength $text_bram]==0} {error "Dashboard text buffer did not map to BRAM"}
puts "DASHBOARD_TEXT_BRAM_PASS=[llength $text_bram]"

set axes_sync [get_pins -hier -regexp {.*dashboard/inst/reg_axes_sync_reg\[0\]/D}]
if {[llength $axes_sync]!=1} {error "Axes visibility CDC first stage missing"}
puts "AXES_VISIBILITY_CDC_PASS"
set preview_metric_sync [get_pins -hier -regexp {.*preview_ddr/inst/reg_(camera_frame|camera_overflow|underflow)_sync_reg\[0\]/D}]
if {[llength $preview_metric_sync]!=3} {error "Preview metric CDC endpoints must be three"}
puts "PREVIEW_METRIC_CDC_ENDPOINTS_PASS count=[llength $preview_metric_sync]"

# Source-synchronous camera data is launched on PCLK's falling edge. The
# default system-synchronous ZHOLD compensation inserted ~7.3ns into these
# IOB paths and violated setup at96MHz. Disable that physical delay only;
# external min/max budgets and both setup/hold checks remain unchanged.
# UG912 IOBDELAY applies to input-buffer cells in timing/place/route.
set camera_ibufs [get_cells -hier -regexp {^cam_(d_IBUF\[[0-7]\]_inst|href_IBUF_inst|vsync_IBUF_inst)$}]
if {[llength $camera_ibufs]!=10} {error "Camera input buffers must be ten"}
foreach camera_ibuf $camera_ibufs {
    if {[get_property REF_NAME $camera_ibuf] ne "IBUF"} {error "Camera input buffer type mismatch"}
}
set_property IOBDELAY NONE $camera_ibufs
foreach camera_ibuf $camera_ibufs {
    if {[get_property IOBDELAY $camera_ibuf] ne "NONE"} {error "Camera ZHOLD disable did not apply"}
}
puts "CAMERA_SOURCE_SYNC_ZHOLD_DISABLED_PASS count=[llength $camera_ibufs]"
