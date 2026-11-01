# PYNQ-Z2 OV5640 inputs and ST7789 4-wire SPI on PMOD B.
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports sys_clk]
create_clock -name sys_clk -period 8.000 [get_ports sys_clk]

set_property -dict { PACKAGE_PIN W8  IOSTANDARD LVCMOS33 } [get_ports {cam_d[0]}]
set_property -dict { PACKAGE_PIN B20 IOSTANDARD LVCMOS33 } [get_ports {cam_d[1]}]
set_property -dict { PACKAGE_PIN Y8  IOSTANDARD LVCMOS33 } [get_ports {cam_d[2]}]
set_property -dict { PACKAGE_PIN B19 IOSTANDARD LVCMOS33 } [get_ports {cam_d[3]}]
set_property -dict { PACKAGE_PIN W9  IOSTANDARD LVCMOS33 } [get_ports {cam_d[4]}]
set_property -dict { PACKAGE_PIN A20 IOSTANDARD LVCMOS33 } [get_ports {cam_d[5]}]
set_property -dict { PACKAGE_PIN Y9  IOSTANDARD LVCMOS33 } [get_ports {cam_d[6]}]
set_property -dict { PACKAGE_PIN C20 IOSTANDARD LVCMOS33 } [get_ports {cam_d[7]}]
set_property -dict { PACKAGE_PIN V8  IOSTANDARD LVCMOS33 } [get_ports cam_vsync]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports cam_href]
set_property -dict { PACKAGE_PIN W10 IOSTANDARD LVCMOS33 } [get_ports cam_pclk]
create_clock -name cam_pclk -period 10.416 [get_ports cam_pclk]
# 96 MHz DVP candidate: 4740[5]=1 updates data on the falling edge.
# External delay budget is an engineering assumption, not a measured sensor
# tCO specification: allow -0.5..4.0 ns including cable skew. Bench validation
# is required on the existing non-CCIO W10 wiring; no input paths are waived.
set_input_delay -clock [get_clocks cam_pclk] -clock_fall -min -0.500 [get_ports {cam_d[*] cam_vsync cam_href}]
set_input_delay -clock [get_clocks cam_pclk] -clock_fall -max 4.000 [get_ports {cam_d[*] cam_vsync cam_href}]
set_clock_uncertainty -setup 0.250 [get_clocks cam_pclk]
set_clock_uncertainty -hold 0.100 [get_clocks cam_pclk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk]
set_property -dict { PACKAGE_PIN U7 IOSTANDARD LVCMOS33 PULLUP true } [get_ports cam_scl]
set_property -dict { PACKAGE_PIN U8 IOSTANDARD LVCMOS33 PULLUP true } [get_ports cam_sda]
set_property -dict { PACKAGE_PIN V6 IOSTANDARD LVCMOS33 } [get_ports cam_rst_n]
set_property -dict { PACKAGE_PIN W6 IOSTANDARD LVCMOS33 } [get_ports cam_pwdn]

# PMOD B: JB1, JB2, JB3, JB4, JB7, JB8.

set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

create_generated_clock -name control_divided -source [get_ports sys_clk] -divide_by 4 [get_pins -hier -filter {NAME =~ */control_buffer/O}]
set_clock_groups -asynchronous -group [get_clocks cam_pclk] -group [get_clocks -include_generated_clocks sys_clk]


set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {save_rgb[0]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {save_rgb[1]}]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {save_rgb[2]}]
# PS FCLK is independent of both the oscillator divider and camera PCLK.
# Transfers use dual-clock frame memories and explicit synchronizers.
# Camera/FCLK crossings are constrained by XPM IP and endpoint-specific XDC.
# A broad cam_pclk group would override the FIFO Gray-pointer max_delays.
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks clk_fpga_0] -group [get_clocks -include_generated_clocks sys_clk]

set_property -dict { PACKAGE_PIN L16 IOSTANDARD TMDS_33 } [get_ports {hdmi_clk_p}]
set_property -dict { PACKAGE_PIN L17 IOSTANDARD TMDS_33 } [get_ports {hdmi_clk_n}]
set_property -dict { PACKAGE_PIN K17 IOSTANDARD TMDS_33 } [get_ports {hdmi_d_p[0]}]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD TMDS_33 } [get_ports {hdmi_d_n[0]}]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD TMDS_33 } [get_ports {hdmi_d_p[1]}]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD TMDS_33 } [get_ports {hdmi_d_n[1]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD TMDS_33 } [get_ports {hdmi_d_p[2]}]
set_property -dict { PACKAGE_PIN H18 IOSTANDARD TMDS_33 } [get_ports {hdmi_d_n[2]}]
# Snapshot control/status intentionally use two-stage synchronizers even when
# the pixel clock is derived from PS FCLK. Only the first stage is asynchronous.
set_false_path -to [get_pins -hier -filter {NAME =~ */status_meta_reg*/D}]
# Reset synchronizers assert asynchronously and release synchronously.
set_false_path -to [get_pins -hier -filter {NAME =~ */released_reg*/CLR}]

