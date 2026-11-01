# Run on the synthesized/routed isolated design; never on the frozen parent.
set color_source [get_cells -quiet -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/reg_color_stage_reg.*}]
set color_meta [get_cells -quiet -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/reg_color_meta_reg.*}]
set color_sync [get_cells -quiet -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/reg_color_sync_reg.*}]
set color_front [get_cells -quiet -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/reg_color_front_reg.*}]
foreach name {color_source color_meta color_sync color_front} {
    if {[llength [set $name]]!=27} {error "Class-color CDC endpoint count $name: expected27 got[llength [set $name]]"}
}
set source_clocks [get_clocks -of_objects [get_pins -of_objects $color_source -filter {REF_PIN_NAME == C}]]
set destination_clocks [get_clocks -of_objects [get_pins -of_objects $color_meta -filter {REF_PIN_NAME == C}]]
if {[llength $source_clocks]!=1 || [llength $destination_clocks]!=1} {error "Class-color clock coverage ambiguous"}
if {abs([get_property PERIOD $source_clocks]-10.000)>0.01} {error "Class-color AXI clock differs from100MHz"}
if {abs([get_property PERIOD $destination_clocks]-13.468)>0.02} {error "Class-color display clock differs from74.25MHz"}
set color_paths [get_timing_paths -quiet -from $color_source -to $color_meta -max_paths 27]
if {[llength $color_paths]==0} {error "Class-color payload timing paths absent or falsely cut"}
puts "CLASSCOLOR_CDC_ENDPOINTS_PASS: source27 meta27 sync27 front27; clock periods100MHz/74.25MHz; explicit payload paths present"
