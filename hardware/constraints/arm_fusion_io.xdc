# Only the UART TX line changes from the dedicated arm board:
# PYNQ RPi physical 18 (Y7) -> RasAdapter physical 8.
# PYNQ physical 8/V6 remains the camera reset output.
set_property PACKAGE_PIN Y7 [get_ports servo_txd]
set_property PACKAGE_PIN Y6 [get_ports servo_rxd]
set_property PACKAGE_PIN V7 [get_ports servo_tx_en]
set_property PACKAGE_PIN Y18 [get_ports servo_rx_en]
set_property IOSTANDARD LVCMOS33 [get_ports {servo_txd servo_rxd servo_tx_en servo_rx_en}]
set_property SLEW SLOW [get_ports {servo_txd servo_tx_en servo_rx_en}]
set_property DRIVE 8 [get_ports {servo_txd servo_tx_en servo_rx_en}]
set_property PULLUP true [get_ports servo_rxd]
set_property PULLDOWN true [get_ports {servo_tx_en servo_rx_en}]
# UART input is asynchronous; an explicit four-stage XPM chain receives it.
set_false_path -from [get_ports servo_rxd]
set_false_path -to [get_ports {servo_txd servo_tx_en servo_rx_en}]
