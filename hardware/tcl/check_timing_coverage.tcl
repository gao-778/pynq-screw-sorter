# Actual runtime clocks are unchanged; insist they are analyzed, not waived.
set fclk [get_clocks -quiet clk_fpga_0]
if {[llength $fclk]!=1 || abs([get_property PERIOD $fclk]-10.0)>0.0001} {
    error "Missing or incorrect 100 MHz PS FCLK timing constraint"
}
set fp [open multiclass_clocks.tsv w]
foreach clk [get_clocks] {puts $fp "[get_property NAME $clk]\t[get_property PERIOD $clk]\t[get_property WAVEFORM $clk]"}
close $fp
check_timing -verbose -file multiclass_timing_coverage.rpt
set fp [open multiclass_timing_coverage.rpt r]
set checks [read $fp]
close $fp
if {![regexp {checking no_clock \(([0-9]+)\)} $checks all count] || $count!=0} {
    error "Unclocked sequential pins are not allowed: $count"
}
if {![regexp {checking unconstrained_internal_endpoints \(([0-9]+)\)} $checks all count] || $count!=0} {
    error "Unconstrained internal endpoints are not allowed: $count"
}
puts "MC18_TIMING_COVERAGE_PASS no_clock=0 unconstrained_internal_endpoints=0 fclk=10ns"
