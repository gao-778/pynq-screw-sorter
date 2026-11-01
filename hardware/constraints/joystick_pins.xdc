# A0/A1 analog paths after the PYNQ-Z2 resistor dividers (VAUX1 and VAUX9).
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports joy_axis_x_p]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports joy_axis_x_n]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports joy_axis_y_p]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports joy_axis_y_n]
# D2=Z, D3=SW1, D4=SW2, D5=SW3, D6=SW4; press connects to GND.
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {joy_keys_n[0]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {joy_keys_n[1]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {joy_keys_n[2]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {joy_keys_n[3]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {joy_keys_n[4]}]
