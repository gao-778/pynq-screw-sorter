set ip_xdc [get_files -all -filter {FILE_TYPE == XDC && IS_GENERATED == 1}]
set n_enabled 0
foreach f $ip_xdc {
    set name [file tail [get_property NAME $f]]
    if {$name eq "ooc.xdc" || [string match *_ooc.xdc $name]} {
        set_property USED_IN_IMPLEMENTATION false $f
    } else {
        set_property USED_IN_IMPLEMENTATION true $f
        incr n_enabled
    }
}
set ps_xdc [get_files -all -filter {NAME =~ */camera_sd_system_ps_0.xdc}]
if {[llength $ps_xdc]!=1 || ![get_property USED_IN_IMPLEMENTATION $ps_xdc]} {
    error "PS FCLK timing constraint is not enabled"
}
puts "MC18_IP_CONSTRAINT_RESTORE enabled=$n_enabled"
