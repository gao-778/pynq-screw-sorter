set classcolor_source [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/reg_color_stage_reg.*}]
set classcolor_destination [get_cells -hier -filter {IS_SEQUENTIAL == 1} -regexp {.*dashboard/inst/reg_color_meta_reg.*}]
set_max_delay -datapath_only 13.468 -from $classcolor_source -to $classcolor_destination
set_bus_skew 10.000 -from $classcolor_source -to $classcolor_destination
