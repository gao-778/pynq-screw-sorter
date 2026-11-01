# Run Vivado's generated synthesis Tcl directly when Windows Script Host
# cannot launch runme.bat. The generated script stays the source of truth.
set root [file dirname [file dirname [info script]]]
set support [file join $::env(XILINX_VIVADO) data XilinxTclStore support]
lappend ::auto_path $support
set dir [file join $support appinit]
source [file join $dir pkgIndex.tcl]
package require ::tclapp::support::appinit 1.2
foreach {sim_pkg sim_version} {xsim 2.527 modelsim 2.381 questa 2.346 xcelium 11.200 vcs 18.3} {
    set sim_dir [file join $::env(XILINX_VIVADO) data XilinxTclStore tclapp xilinx $sim_pkg]
    lappend ::auto_path $sim_dir
    set dir $sim_dir
    source [file join $dir pkgIndex.tcl]
    package require ::tclapp::xilinx::$sim_pkg $sim_version
}
foreach {sim_pkg sim_version} {riviera 1.42 activehdl 1.42} {
    set sim_dir [file join $::env(XILINX_VIVADO) data XilinxTclStore tclapp aldec $sim_pkg]
    lappend ::auto_path $sim_dir
    set dir $sim_dir
    source [file join $dir pkgIndex.tcl]
    package require ::tclapp::aldec::$sim_pkg $sim_version
}
