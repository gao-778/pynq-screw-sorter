set fp [open multiclass_pre_bit_slack.tsv w]
foreach delay {max min} {
    set paths [get_timing_paths -delay_type $delay -max_paths 1]
    if {[llength $paths]!=1} {close $fp;error "No timing path for $delay"}
    set slack [get_property SLACK $paths]
    puts $fp "$delay\t$slack"
    if {$slack<0} {close $fp;error "MC18 routed $delay slack is negative: $slack"}
}
close $fp
puts "MC18_FINAL_TIMING_PASS"
