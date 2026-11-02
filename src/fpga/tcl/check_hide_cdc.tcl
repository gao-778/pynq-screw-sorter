set hide_first [get_pins -hier -regexp {.*dashboard/inst/reg_hide(_ack)?_sync_reg\[0\]/D}]
if {[llength $hide_first]!=2} {error "Expected exactly two hide CDC first-stage pins"}
set hide_chain [get_cells -hier -regexp {.*dashboard/inst/reg_hide(_ack)?_sync_reg\[[0-2]\]}]
if {[llength $hide_chain]!=6} {error "Expected two complete three-flop hide synchronizers"}
foreach cell $hide_chain {
    if {[get_property ASYNC_REG $cell] ne "1" && [get_property ASYNC_REG $cell] ne "TRUE"} {error "Unmarked hide synchronizer stage: $cell"}
}
foreach pin $hide_first {
    set dest [get_cells -of_objects $pin]
    set launch [all_fanin -flat -startpoints_only -to $pin]
    set launch_cells [get_cells -of_objects $launch]
    set destclock [get_clocks -of_objects [get_pins $dest/C]]
    set launchclock [get_clocks -of_objects [get_pins -of_objects $launch_cells -filter {REF_PIN_NAME == C}]]
    puts "HIDE_CDC_PATH source=$launch source_clock=$launchclock dest=$pin dest_clock=$destclock"
}
puts "HIDE_CDC_FIRST_STAGE_PASS count=[llength $hide_first] chain_flops=[llength $hide_chain]"
