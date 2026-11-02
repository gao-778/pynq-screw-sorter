
################################################################
# This is a generated script based on design: camera_sd_system
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2026.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source camera_sd_system_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# st7789_clock_divider, st7789_camera_control, ov5640_capture, st7789_ready_sync, hdmi_recognition_display, hdmi_clocks, hdmi_serial, st7789_status, snapshot_control, recognition_core_obb, detection_overlay_obb, video_reset_bridge, ddr_gray_reader, ddr_preview, screw_dashboard, snapshot_stream, joystick_inputs, target_inspector, servo_rx_guard

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z020clg400-1
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name camera_sd_system

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:processing_system7:5.5\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:smartconnect:1.0\
xilinx.com:ip:axi_gpio:2.0\
xilinx.com:ip:axi_bram_ctrl:4.1\
xilinx.com:ip:axis_data_fifo:2.0\
xilinx.com:ip:axi_dma:7.1\
xilinx.com:ip:xlconcat:2.1\
xilinx.com:ip:axi_uart16550:2.0\
xilinx.com:ip:xlslice:1.0\
xilinx.com:ip:util_vector_logic:2.0\
xilinx.com:ip:xpm_cdc_gen:1.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
st7789_clock_divider\
st7789_camera_control\
ov5640_capture\
st7789_ready_sync\
hdmi_recognition_display\
hdmi_clocks\
hdmi_serial\
st7789_status\
snapshot_control\
recognition_core_obb\
detection_overlay_obb\
video_reset_bridge\
ddr_gray_reader\
ddr_preview\
screw_dashboard\
snapshot_stream\
joystick_inputs\
target_inspector\
servo_rx_guard\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set DDR [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR ]

  set FIXED_IO [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO ]


  # Create ports
  set sys_clk [ create_bd_port -dir I -type clk -freq_hz 125000000 sys_clk ]
  set cam_pclk [ create_bd_port -dir I -type clk -freq_hz 96000000 cam_pclk ]
  set cam_vsync [ create_bd_port -dir I cam_vsync ]
  set cam_href [ create_bd_port -dir I cam_href ]
  set cam_d [ create_bd_port -dir I -from 7 -to 0 cam_d ]
  set cam_scl [ create_bd_port -dir IO cam_scl ]
  set cam_sda [ create_bd_port -dir IO cam_sda ]
  set cam_rst_n [ create_bd_port -dir O cam_rst_n ]
  set cam_pwdn [ create_bd_port -dir O cam_pwdn ]
  set hdmi_clk_p [ create_bd_port -dir O hdmi_clk_p ]
  set hdmi_clk_n [ create_bd_port -dir O hdmi_clk_n ]
  set hdmi_d_p [ create_bd_port -dir O -from 2 -to 0 hdmi_d_p ]
  set hdmi_d_n [ create_bd_port -dir O -from 2 -to 0 hdmi_d_n ]
  set led [ create_bd_port -dir O -from 3 -to 0 led ]
  set save_rgb [ create_bd_port -dir O -from 2 -to 0 save_rgb ]
  set joy_axis_x_p [ create_bd_port -dir I joy_axis_x_p ]
  set joy_axis_x_n [ create_bd_port -dir I joy_axis_x_n ]
  set joy_axis_y_p [ create_bd_port -dir I joy_axis_y_p ]
  set joy_axis_y_n [ create_bd_port -dir I joy_axis_y_n ]
  set joy_keys_n [ create_bd_port -dir I -from 4 -to 0 joy_keys_n ]
  set servo_txd [ create_bd_port -dir O servo_txd ]
  set servo_tx_en [ create_bd_port -dir O -from 0 -to 0 servo_tx_en ]
  set servo_rx_en [ create_bd_port -dir O -from 0 -to 0 servo_rx_en ]
  set servo_rxd [ create_bd_port -dir I servo_rxd ]

  # Create instance: clocks, and set properties
  set block_name st7789_clock_divider
  set block_cell_name clocks
  if { [catch {set clocks [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $clocks eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: cam_cfg, and set properties
  set block_name st7789_camera_control
  set block_cell_name cam_cfg
  if { [catch {set cam_cfg [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $cam_cfg eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: capture, and set properties
  set block_name ov5640_capture
  set block_cell_name capture
  if { [catch {set capture [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $capture eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: ready, and set properties
  set block_name st7789_ready_sync
  set block_cell_name ready
  if { [catch {set ready [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $ready eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: display, and set properties
  set block_name hdmi_recognition_display
  set block_cell_name display
  if { [catch {set display [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $display eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: video_clock, and set properties
  set block_name hdmi_clocks
  set block_cell_name video_clock
  if { [catch {set video_clock [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $video_clock eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: serializer, and set properties
  set block_name hdmi_serial
  set block_cell_name serializer
  if { [catch {set serializer [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $serializer eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: status, and set properties
  set block_name st7789_status
  set block_cell_name status
  if { [catch {set status [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $status eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: ps, and set properties
  set ps [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps ]
  set_property -dict [list \
    CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {650.000000} \
    CONFIG.PCW_ACT_CAN0_PERIPHERAL_FREQMHZ {23.8095} \
    CONFIG.PCW_ACT_CAN1_PERIPHERAL_FREQMHZ {23.8095} \
    CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.096154} \
    CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {125.000000} \
    CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_I2C_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {50.000000} \
    CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {108.333336} \
    CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {108.333336} \
    CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {108.333336} \
    CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {108.333336} \
    CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {108.333336} \
    CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {108.333336} \
    CONFIG.PCW_ACT_TTC_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_USB0_PERIPHERAL_FREQMHZ {60} \
    CONFIG.PCW_ACT_USB1_PERIPHERAL_FREQMHZ {60} \
    CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {108.333336} \
    CONFIG.PCW_APU_CLK_RATIO_ENABLE {6:2:1} \
    CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {650} \
    CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC {External} \
    CONFIG.PCW_CAN1_PERIPHERAL_CLKSRC {External} \
    CONFIG.PCW_CAN_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_CAN_PERIPHERAL_VALID {0} \
    CONFIG.PCW_CLK0_FREQ {100000000} \
    CONFIG.PCW_CLK1_FREQ {10000000} \
    CONFIG.PCW_CLK2_FREQ {10000000} \
    CONFIG.PCW_CLK3_FREQ {10000000} \
    CONFIG.PCW_CPU_CPU_6X4X_MAX_RANGE {667} \
    CONFIG.PCW_CPU_PERIPHERAL_CLKSRC {ARM PLL} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_DCI_PERIPHERAL_CLKSRC {DDR PLL} \
    CONFIG.PCW_DCI_PERIPHERAL_FREQMHZ {10.159} \
    CONFIG.PCW_DDR_PERIPHERAL_CLKSRC {DDR PLL} \
    CONFIG.PCW_DDR_RAM_BASEADDR {0x00100000} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x1FFFFFFF} \
    CONFIG.PCW_DM_WIDTH {4} \
    CONFIG.PCW_DQS_WIDTH {4} \
    CONFIG.PCW_DQ_WIDTH {32} \
    CONFIG.PCW_ENET0_BASEADDR {0xE000B000} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_ENET0_GRP_MDIO_IO {MIO 52 .. 53} \
    CONFIG.PCW_ENET0_HIGHADDR {0xE000BFFF} \
    CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_PERIPHERAL_FREQMHZ {1000 Mbps} \
    CONFIG.PCW_ENET0_RESET_ENABLE {1} \
    CONFIG.PCW_ENET0_RESET_IO {MIO 9} \
    CONFIG.PCW_ENET1_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_ENET1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_ENET_RESET_ENABLE {1} \
    CONFIG.PCW_ENET_RESET_POLARITY {Active Low} \
    CONFIG.PCW_ENET_RESET_SELECT {Share reset pin} \
    CONFIG.PCW_EN_4K_TIMER {0} \
    CONFIG.PCW_EN_CAN0 {0} \
    CONFIG.PCW_EN_CAN1 {0} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_CLK1_PORT {0} \
    CONFIG.PCW_EN_CLK2_PORT {0} \
    CONFIG.PCW_EN_CLK3_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG0_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG1_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG2_PORT {0} \
    CONFIG.PCW_EN_CLKTRIG3_PORT {0} \
    CONFIG.PCW_EN_DDR {1} \
    CONFIG.PCW_EN_EMIO_CAN0 {0} \
    CONFIG.PCW_EN_EMIO_CAN1 {0} \
    CONFIG.PCW_EN_EMIO_CD_SDIO0 {0} \
    CONFIG.PCW_EN_EMIO_CD_SDIO1 {0} \
    CONFIG.PCW_EN_EMIO_ENET0 {0} \
    CONFIG.PCW_EN_EMIO_ENET1 {0} \
    CONFIG.PCW_EN_EMIO_GPIO {0} \
    CONFIG.PCW_EN_EMIO_I2C0 {0} \
    CONFIG.PCW_EN_EMIO_I2C1 {0} \
    CONFIG.PCW_EN_EMIO_MODEM_UART0 {0} \
    CONFIG.PCW_EN_EMIO_MODEM_UART1 {0} \
    CONFIG.PCW_EN_EMIO_PJTAG {0} \
    CONFIG.PCW_EN_EMIO_SDIO0 {0} \
    CONFIG.PCW_EN_EMIO_SDIO1 {0} \
    CONFIG.PCW_EN_EMIO_SPI0 {0} \
    CONFIG.PCW_EN_EMIO_SPI1 {0} \
    CONFIG.PCW_EN_EMIO_SRAM_INT {0} \
    CONFIG.PCW_EN_EMIO_TRACE {0} \
    CONFIG.PCW_EN_EMIO_TTC0 {0} \
    CONFIG.PCW_EN_EMIO_TTC1 {0} \
    CONFIG.PCW_EN_EMIO_UART0 {0} \
    CONFIG.PCW_EN_EMIO_UART1 {0} \
    CONFIG.PCW_EN_EMIO_WDT {0} \
    CONFIG.PCW_EN_EMIO_WP_SDIO0 {0} \
    CONFIG.PCW_EN_EMIO_WP_SDIO1 {0} \
    CONFIG.PCW_EN_ENET0 {1} \
    CONFIG.PCW_EN_ENET1 {0} \
    CONFIG.PCW_EN_GPIO {1} \
    CONFIG.PCW_EN_I2C0 {0} \
    CONFIG.PCW_EN_I2C1 {0} \
    CONFIG.PCW_EN_MODEM_UART0 {0} \
    CONFIG.PCW_EN_MODEM_UART1 {0} \
    CONFIG.PCW_EN_PJTAG {0} \
    CONFIG.PCW_EN_PTP_ENET0 {0} \
    CONFIG.PCW_EN_PTP_ENET1 {0} \
    CONFIG.PCW_EN_QSPI {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_EN_RST1_PORT {0} \
    CONFIG.PCW_EN_RST2_PORT {0} \
    CONFIG.PCW_EN_RST3_PORT {0} \
    CONFIG.PCW_EN_SDIO0 {1} \
    CONFIG.PCW_EN_SDIO1 {0} \
    CONFIG.PCW_EN_SMC {0} \
    CONFIG.PCW_EN_SPI0 {0} \
    CONFIG.PCW_EN_SPI1 {0} \
    CONFIG.PCW_EN_TRACE {0} \
    CONFIG.PCW_EN_TTC0 {0} \
    CONFIG.PCW_EN_TTC1 {0} \
    CONFIG.PCW_EN_UART0 {1} \
    CONFIG.PCW_EN_UART1 {0} \
    CONFIG.PCW_EN_USB0 {1} \
    CONFIG.PCW_EN_USB1 {0} \
    CONFIG.PCW_EN_WDT {0} \
    CONFIG.PCW_FCLK0_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK1_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK2_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK3_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_FCLK_CLK0_BUF {TRUE} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA3_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_GPIO_BASEADDR {0xE000A000} \
    CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {0} \
    CONFIG.PCW_GPIO_HIGHADDR {0xE000AFFF} \
    CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} \
    CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} \
    CONFIG.PCW_GPIO_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_I2C_RESET_ENABLE {1} \
    CONFIG.PCW_I2C_RESET_POLARITY {Active Low} \
    CONFIG.PCW_IMPORT_BOARD_PRESET {None} \
    CONFIG.PCW_INCLUDE_ACP_TRANS_CHECK {0} \
    CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_0_PULLUP {enabled} \
    CONFIG.PCW_MIO_0_SLEW {slow} \
    CONFIG.PCW_MIO_10_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_10_PULLUP {enabled} \
    CONFIG.PCW_MIO_10_SLEW {slow} \
    CONFIG.PCW_MIO_11_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_11_PULLUP {enabled} \
    CONFIG.PCW_MIO_11_SLEW {slow} \
    CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_12_PULLUP {enabled} \
    CONFIG.PCW_MIO_12_SLEW {slow} \
    CONFIG.PCW_MIO_13_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_13_PULLUP {enabled} \
    CONFIG.PCW_MIO_13_SLEW {slow} \
    CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_14_PULLUP {enabled} \
    CONFIG.PCW_MIO_14_SLEW {slow} \
    CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_15_PULLUP {enabled} \
    CONFIG.PCW_MIO_15_SLEW {slow} \
    CONFIG.PCW_MIO_16_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_16_PULLUP {enabled} \
    CONFIG.PCW_MIO_16_SLEW {slow} \
    CONFIG.PCW_MIO_17_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_17_PULLUP {enabled} \
    CONFIG.PCW_MIO_17_SLEW {slow} \
    CONFIG.PCW_MIO_18_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_18_PULLUP {enabled} \
    CONFIG.PCW_MIO_18_SLEW {slow} \
    CONFIG.PCW_MIO_19_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_19_PULLUP {enabled} \
    CONFIG.PCW_MIO_19_SLEW {slow} \
    CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_1_PULLUP {enabled} \
    CONFIG.PCW_MIO_1_SLEW {slow} \
    CONFIG.PCW_MIO_20_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_20_PULLUP {enabled} \
    CONFIG.PCW_MIO_20_SLEW {slow} \
    CONFIG.PCW_MIO_21_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_21_PULLUP {enabled} \
    CONFIG.PCW_MIO_21_SLEW {slow} \
    CONFIG.PCW_MIO_22_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_22_PULLUP {enabled} \
    CONFIG.PCW_MIO_22_SLEW {slow} \
    CONFIG.PCW_MIO_23_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_23_PULLUP {enabled} \
    CONFIG.PCW_MIO_23_SLEW {slow} \
    CONFIG.PCW_MIO_24_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_24_PULLUP {enabled} \
    CONFIG.PCW_MIO_24_SLEW {slow} \
    CONFIG.PCW_MIO_25_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_25_PULLUP {enabled} \
    CONFIG.PCW_MIO_25_SLEW {slow} \
    CONFIG.PCW_MIO_26_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_26_PULLUP {enabled} \
    CONFIG.PCW_MIO_26_SLEW {slow} \
    CONFIG.PCW_MIO_27_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_27_PULLUP {enabled} \
    CONFIG.PCW_MIO_27_SLEW {slow} \
    CONFIG.PCW_MIO_28_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_28_PULLUP {enabled} \
    CONFIG.PCW_MIO_28_SLEW {slow} \
    CONFIG.PCW_MIO_29_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_29_PULLUP {enabled} \
    CONFIG.PCW_MIO_29_SLEW {slow} \
    CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_2_SLEW {slow} \
    CONFIG.PCW_MIO_30_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_30_PULLUP {enabled} \
    CONFIG.PCW_MIO_30_SLEW {slow} \
    CONFIG.PCW_MIO_31_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_31_PULLUP {enabled} \
    CONFIG.PCW_MIO_31_SLEW {slow} \
    CONFIG.PCW_MIO_32_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_32_PULLUP {enabled} \
    CONFIG.PCW_MIO_32_SLEW {slow} \
    CONFIG.PCW_MIO_33_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_33_PULLUP {enabled} \
    CONFIG.PCW_MIO_33_SLEW {slow} \
    CONFIG.PCW_MIO_34_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_34_PULLUP {enabled} \
    CONFIG.PCW_MIO_34_SLEW {slow} \
    CONFIG.PCW_MIO_35_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_35_PULLUP {enabled} \
    CONFIG.PCW_MIO_35_SLEW {slow} \
    CONFIG.PCW_MIO_36_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_36_PULLUP {enabled} \
    CONFIG.PCW_MIO_36_SLEW {slow} \
    CONFIG.PCW_MIO_37_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_37_PULLUP {enabled} \
    CONFIG.PCW_MIO_37_SLEW {slow} \
    CONFIG.PCW_MIO_38_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_38_PULLUP {enabled} \
    CONFIG.PCW_MIO_38_SLEW {slow} \
    CONFIG.PCW_MIO_39_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_39_PULLUP {enabled} \
    CONFIG.PCW_MIO_39_SLEW {slow} \
    CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_3_SLEW {slow} \
    CONFIG.PCW_MIO_40_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_40_PULLUP {enabled} \
    CONFIG.PCW_MIO_40_SLEW {slow} \
    CONFIG.PCW_MIO_41_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_41_PULLUP {enabled} \
    CONFIG.PCW_MIO_41_SLEW {slow} \
    CONFIG.PCW_MIO_42_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_42_PULLUP {enabled} \
    CONFIG.PCW_MIO_42_SLEW {slow} \
    CONFIG.PCW_MIO_43_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_43_PULLUP {enabled} \
    CONFIG.PCW_MIO_43_SLEW {slow} \
    CONFIG.PCW_MIO_44_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_44_PULLUP {enabled} \
    CONFIG.PCW_MIO_44_SLEW {slow} \
    CONFIG.PCW_MIO_45_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_45_PULLUP {enabled} \
    CONFIG.PCW_MIO_45_SLEW {slow} \
    CONFIG.PCW_MIO_46_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_46_PULLUP {enabled} \
    CONFIG.PCW_MIO_46_SLEW {slow} \
    CONFIG.PCW_MIO_47_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_47_PULLUP {enabled} \
    CONFIG.PCW_MIO_47_SLEW {slow} \
    CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_48_PULLUP {enabled} \
    CONFIG.PCW_MIO_48_SLEW {slow} \
    CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_49_PULLUP {enabled} \
    CONFIG.PCW_MIO_49_SLEW {slow} \
    CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_4_SLEW {slow} \
    CONFIG.PCW_MIO_50_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_50_PULLUP {enabled} \
    CONFIG.PCW_MIO_50_SLEW {slow} \
    CONFIG.PCW_MIO_51_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_51_PULLUP {enabled} \
    CONFIG.PCW_MIO_51_SLEW {slow} \
    CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_52_PULLUP {enabled} \
    CONFIG.PCW_MIO_52_SLEW {slow} \
    CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 1.8V} \
    CONFIG.PCW_MIO_53_PULLUP {enabled} \
    CONFIG.PCW_MIO_53_SLEW {slow} \
    CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_5_SLEW {slow} \
    CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_6_SLEW {slow} \
    CONFIG.PCW_MIO_7_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_7_SLEW {slow} \
    CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_8_SLEW {slow} \
    CONFIG.PCW_MIO_9_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_9_PULLUP {enabled} \
    CONFIG.PCW_MIO_9_SLEW {slow} \
    CONFIG.PCW_MIO_PRIMITIVE {54} \
    CONFIG.PCW_MIO_TREE_PERIPHERALS {GPIO#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#Quad SPI Flash#GPIO#Quad SPI Flash#ENET Reset#GPIO#GPIO#GPIO#GPIO#UART 0#UART 0#Enet\
0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#Enet 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#USB 0#SD 0#SD 0#SD 0#SD 0#SD 0#SD 0#USB Reset#SD 0#GPIO#GPIO#GPIO#GPIO#Enet\
0#Enet 0} \
    CONFIG.PCW_MIO_TREE_SIGNALS {gpio[0]#qspi0_ss_b#qspi0_io[0]#qspi0_io[1]#qspi0_io[2]#qspi0_io[3]/HOLD_B#qspi0_sclk#gpio[7]#qspi_fbclk#reset#gpio[10]#gpio[11]#gpio[12]#gpio[13]#rx#tx#tx_clk#txd[0]#txd[1]#txd[2]#txd[3]#tx_ctl#rx_clk#rxd[0]#rxd[1]#rxd[2]#rxd[3]#rx_ctl#data[4]#dir#stp#nxt#data[0]#data[1]#data[2]#data[3]#clk#data[5]#data[6]#data[7]#clk#cmd#data[0]#data[1]#data[2]#data[3]#reset#cd#gpio[48]#gpio[49]#gpio[50]#gpio[51]#mdc#mdio}\
\
    CONFIG.PCW_M_AXI_GP0_ENABLE_STATIC_REMAP {0} \
    CONFIG.PCW_M_AXI_GP0_ID_WIDTH {12} \
    CONFIG.PCW_M_AXI_GP0_SUPPORT_NARROW_BURST {0} \
    CONFIG.PCW_M_AXI_GP0_THREAD_ID_WIDTH {12} \
    CONFIG.PCW_NAND_CYCLES_T_AR {1} \
    CONFIG.PCW_NAND_CYCLES_T_CLR {1} \
    CONFIG.PCW_NAND_CYCLES_T_RC {11} \
    CONFIG.PCW_NAND_CYCLES_T_REA {1} \
    CONFIG.PCW_NAND_CYCLES_T_RR {1} \
    CONFIG.PCW_NAND_CYCLES_T_WC {11} \
    CONFIG.PCW_NAND_CYCLES_T_WP {1} \
    CONFIG.PCW_NOR_CS0_T_CEOE {1} \
    CONFIG.PCW_NOR_CS0_T_PC {1} \
    CONFIG.PCW_NOR_CS0_T_RC {11} \
    CONFIG.PCW_NOR_CS0_T_TR {1} \
    CONFIG.PCW_NOR_CS0_T_WC {11} \
    CONFIG.PCW_NOR_CS0_T_WP {1} \
    CONFIG.PCW_NOR_CS0_WE_TIME {0} \
    CONFIG.PCW_NOR_CS1_T_CEOE {1} \
    CONFIG.PCW_NOR_CS1_T_PC {1} \
    CONFIG.PCW_NOR_CS1_T_RC {11} \
    CONFIG.PCW_NOR_CS1_T_TR {1} \
    CONFIG.PCW_NOR_CS1_T_WC {11} \
    CONFIG.PCW_NOR_CS1_T_WP {1} \
    CONFIG.PCW_NOR_CS1_WE_TIME {0} \
    CONFIG.PCW_NOR_SRAM_CS0_T_CEOE {1} \
    CONFIG.PCW_NOR_SRAM_CS0_T_PC {1} \
    CONFIG.PCW_NOR_SRAM_CS0_T_RC {11} \
    CONFIG.PCW_NOR_SRAM_CS0_T_TR {1} \
    CONFIG.PCW_NOR_SRAM_CS0_T_WC {11} \
    CONFIG.PCW_NOR_SRAM_CS0_T_WP {1} \
    CONFIG.PCW_NOR_SRAM_CS0_WE_TIME {0} \
    CONFIG.PCW_NOR_SRAM_CS1_T_CEOE {1} \
    CONFIG.PCW_NOR_SRAM_CS1_T_PC {1} \
    CONFIG.PCW_NOR_SRAM_CS1_T_RC {11} \
    CONFIG.PCW_NOR_SRAM_CS1_T_TR {1} \
    CONFIG.PCW_NOR_SRAM_CS1_T_WC {11} \
    CONFIG.PCW_NOR_SRAM_CS1_T_WP {1} \
    CONFIG.PCW_NOR_SRAM_CS1_WE_TIME {0} \
    CONFIG.PCW_OVERRIDE_BASIC_CLOCK {0} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY0 {0.279} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY1 {0.260} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY2 {0.085} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY3 {0.092} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_0 {-0.051} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_1 {-0.006} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_2 {-0.009} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_3 {-0.033} \
    CONFIG.PCW_PACKAGE_NAME {clg400} \
    CONFIG.PCW_PCAP_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_PCAP_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_PERIPHERAL_BOARD_PRESET {None} \
    CONFIG.PCW_PLL_BYPASSMODE_ENABLE {0} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_PS7_SI_REV {PRODUCTION} \
    CONFIG.PCW_QSPI_GRP_FBCLK_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_FBCLK_IO {MIO 8} \
    CONFIG.PCW_QSPI_GRP_IO1_ENABLE {0} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_ENABLE {1} \
    CONFIG.PCW_QSPI_GRP_SINGLE_SS_IO {MIO 1 .. 6} \
    CONFIG.PCW_QSPI_GRP_SS1_ENABLE {0} \
    CONFIG.PCW_QSPI_INTERNAL_HIGHADDRESS {0xFCFFFFFF} \
    CONFIG.PCW_QSPI_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_QSPI_PERIPHERAL_FREQMHZ {200} \
    CONFIG.PCW_QSPI_QSPI_IO {MIO 1 .. 6} \
    CONFIG.PCW_SD0_GRP_CD_ENABLE {1} \
    CONFIG.PCW_SD0_GRP_CD_IO {MIO 47} \
    CONFIG.PCW_SD0_GRP_POW_ENABLE {0} \
    CONFIG.PCW_SD0_GRP_WP_ENABLE {0} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
    CONFIG.PCW_SD1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SDIO0_BASEADDR {0xE0100000} \
    CONFIG.PCW_SDIO0_HIGHADDR {0xE0100FFF} \
    CONFIG.PCW_SDIO_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_SDIO_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_SDIO_PERIPHERAL_VALID {1} \
    CONFIG.PCW_SINGLE_QSPI_DATA_MODE {x4} \
    CONFIG.PCW_SMC_CYCLE_T0 {NA} \
    CONFIG.PCW_SMC_CYCLE_T1 {NA} \
    CONFIG.PCW_SMC_CYCLE_T2 {NA} \
    CONFIG.PCW_SMC_CYCLE_T3 {NA} \
    CONFIG.PCW_SMC_CYCLE_T4 {NA} \
    CONFIG.PCW_SMC_CYCLE_T5 {NA} \
    CONFIG.PCW_SMC_CYCLE_T6 {NA} \
    CONFIG.PCW_SMC_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_SMC_PERIPHERAL_VALID {0} \
    CONFIG.PCW_SPI0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SPI1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SPI_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_SPI_PERIPHERAL_VALID {0} \
    CONFIG.PCW_TPIU_PERIPHERAL_CLKSRC {External} \
    CONFIG.PCW_TTC0_CLK0_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC0_CLK0_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC0_CLK1_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC0_CLK1_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC0_CLK2_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC0_CLK2_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC1_CLK0_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC1_CLK0_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC1_CLK1_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC1_CLK1_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_TTC1_CLK2_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_TTC1_CLK2_PERIPHERAL_DIVISOR0 {1} \
    CONFIG.PCW_UART0_BASEADDR {0xE0000000} \
    CONFIG.PCW_UART0_BAUD_RATE {115200} \
    CONFIG.PCW_UART0_GRP_FULL_ENABLE {0} \
    CONFIG.PCW_UART0_HIGHADDR {0xE0000FFF} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
    CONFIG.PCW_UART1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_UART_PERIPHERAL_CLKSRC {IO PLL} \
    CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
    CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {525.000000} \
    CONFIG.PCW_UIPARAM_DDR_ADV_ENABLE {0} \
    CONFIG.PCW_UIPARAM_DDR_AL {0} \
    CONFIG.PCW_UIPARAM_DDR_BL {8} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.279} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.260} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.085} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.092} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_LENGTH_MM {27.95} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_LENGTH_MM {27.95} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PACKAGE_LENGTH {80.4535} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_STOP_EN {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_LENGTH_MM {32.14} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_PACKAGE_LENGTH {105.056} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_LENGTH_MM {31.12} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_PACKAGE_LENGTH {66.904} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_PACKAGE_LENGTH {89.1715} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_PACKAGE_LENGTH {113.63} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {-0.051} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {-0.006} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {-0.009} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {-0.033} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_LENGTH_MM {32.2} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_PACKAGE_LENGTH {98.503} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_LENGTH_MM {31.08} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_PACKAGE_LENGTH {68.5855} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_PACKAGE_LENGTH {90.295} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_PACKAGE_LENGTH {103.977} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_PROPOGATION_DELAY {160} \
    CONFIG.PCW_UIPARAM_DDR_ECC {Disabled} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {525} \
    CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
    CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {0} \
    CONFIG.PCW_UIPARAM_GENERATE_SUMMARY {NA} \
    CONFIG.PCW_USB0_BASEADDR {0xE0102000} \
    CONFIG.PCW_USB0_HIGHADDR {0xE0102fff} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_USB0_RESET_ENABLE {1} \
    CONFIG.PCW_USB0_RESET_IO {MIO 46} \
    CONFIG.PCW_USB0_USB0_IO {MIO 28 .. 39} \
    CONFIG.PCW_USB1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_USB_RESET_ENABLE {1} \
    CONFIG.PCW_USB_RESET_POLARITY {Active Low} \
    CONFIG.PCW_USB_RESET_SELECT {Share reset pin} \
    CONFIG.PCW_USE_AXI_FABRIC_IDLE {0} \
    CONFIG.PCW_USE_AXI_NONSECURE {0} \
    CONFIG.PCW_USE_CORESIGHT {0} \
    CONFIG.PCW_USE_CROSS_TRIGGER {0} \
    CONFIG.PCW_USE_CR_FABRIC {1} \
    CONFIG.PCW_USE_DDR_BYPASS {0} \
    CONFIG.PCW_USE_DEBUG {0} \
    CONFIG.PCW_USE_DMA0 {0} \
    CONFIG.PCW_USE_DMA1 {0} \
    CONFIG.PCW_USE_DMA2 {0} \
    CONFIG.PCW_USE_DMA3 {0} \
    CONFIG.PCW_USE_EXPANDED_IOP {0} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
    CONFIG.PCW_USE_HIGH_OCM {0} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_M_AXI_GP1 {0} \
    CONFIG.PCW_USE_PROC_EVENT_BUS {0} \
    CONFIG.PCW_USE_PS_SLCR_REGISTERS {0} \
    CONFIG.PCW_USE_S_AXI_ACP {0} \
    CONFIG.PCW_USE_S_AXI_GP0 {0} \
    CONFIG.PCW_USE_S_AXI_GP1 {0} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {0} \
    CONFIG.PCW_USE_S_AXI_HP2 {0} \
    CONFIG.PCW_USE_S_AXI_HP3 {0} \
    CONFIG.PCW_USE_TRACE {0} \
    CONFIG.PCW_VALUE_SILVERSION {3} \
    CONFIG.PCW_WDT_PERIPHERAL_CLKSRC {CPU_1X} \
    CONFIG.PCW_WDT_PERIPHERAL_DIVISOR0 {1} \
  ] $ps


  # Create instance: ps_reset, and set properties
  set ps_reset [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 ps_reset ]

  # Create instance: one, and set properties
  set one [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one ]
  set_property CONFIG.CONST_VAL {1} $one


  # Create instance: cpu_bus, and set properties
  set cpu_bus [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 cpu_bus ]
  set_property -dict [list \
    CONFIG.NUM_MI {7} \
    CONFIG.NUM_SI {1} \
  ] $cpu_bus


  # Create instance: control_gpio, and set properties
  set control_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 control_gpio ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_GPIO2_WIDTH {32} \
    CONFIG.C_GPIO_WIDTH {32} \
    CONFIG.C_IS_DUAL {1} \
  ] $control_gpio


  # Create instance: snapshot_control, and set properties
  set block_name snapshot_control
  set block_cell_name snapshot_control
  if { [catch {set snapshot_control [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $snapshot_control eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: status_zero, and set properties
  set status_zero [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 status_zero ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {3} \
  ] $status_zero


  # Create instance: disabled_buttons, and set properties
  set disabled_buttons [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 disabled_buttons ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {4} \
  ] $disabled_buttons


  # Create instance: recognition, and set properties
  set block_name recognition_core_obb
  set block_cell_name recognition
  if { [catch {set recognition [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $recognition eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.C_MAX_OBJECTS {12} $recognition


  set_property -dict [ list \
   CONFIG.FREQ_HZ {96000000} \
 ] [get_bd_pins $recognition/i_camera_clk]

  # Create instance: recognition_registers, and set properties
  set recognition_registers [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 recognition_registers ]
  set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.SINGLE_PORT_BRAM {1} \
  ] $recognition_registers


  # Create instance: detection_overlay, and set properties
  set block_name detection_overlay_obb
  set block_cell_name detection_overlay
  if { [catch {set detection_overlay [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $detection_overlay eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.C_MAX_OBJECTS {12} $detection_overlay


  # Create instance: overlay_reset, and set properties
  set block_name video_reset_bridge
  set block_cell_name overlay_reset
  if { [catch {set overlay_reset [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $overlay_reset eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: memory_bus, and set properties
  set memory_bus [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 memory_bus ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {4} \
  ] $memory_bus


  # Create instance: gray_fifo, and set properties
  set gray_fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 gray_fifo ]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {1024} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {4} \
  ] $gray_fifo


  # Create instance: gray_dma, and set properties
  set gray_dma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 gray_dma ]
  set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_sg_length_width {23} \
  ] $gray_dma


  # Create instance: gray_reader, and set properties
  set block_name ddr_gray_reader
  set block_cell_name gray_reader
  if { [catch {set gray_reader [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $gray_reader eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: preview_ddr, and set properties
  set block_name ddr_preview
  set block_cell_name preview_ddr
  if { [catch {set preview_ddr [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $preview_ddr eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  set_property -dict [ list \
   CONFIG.FREQ_HZ {96000000} \
 ] [get_bd_pins $preview_ddr/camera_clk]

  # Create instance: dashboard, and set properties
  set block_name screw_dashboard
  set block_cell_name dashboard
  if { [catch {set dashboard [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $dashboard eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.C_MAX_OBJECTS {12} $dashboard


  # Create instance: dashboard_registers, and set properties
  set dashboard_registers [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:4.1 dashboard_registers ]
  set_property -dict [list \
    CONFIG.PROTOCOL {AXI4LITE} \
    CONFIG.SINGLE_PORT_BRAM {1} \
  ] $dashboard_registers


  # Create instance: screen_capture, and set properties
  set block_name snapshot_stream
  set block_cell_name screen_capture
  if { [catch {set screen_capture [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $screen_capture eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property -dict [list \
    CONFIG.C_SOFT_RESET {1} \
    CONFIG.FRAME_PIXELS {921600} \
  ] $screen_capture


  # Create instance: screen_fifo, and set properties
  set screen_fifo [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:2.0 screen_fifo ]
  set_property -dict [list \
    CONFIG.FIFO_DEPTH {4096} \
    CONFIG.HAS_TKEEP {1} \
    CONFIG.HAS_TLAST {1} \
    CONFIG.IS_ACLK_ASYNC {1} \
    CONFIG.TDATA_NUM_BYTES {4} \
  ] $screen_fifo


  # Create instance: screen_dma, and set properties
  set screen_dma [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 screen_dma ]
  set_property -dict [list \
    CONFIG.c_include_mm2s {0} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_sg {0} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_sg_length_width {23} \
  ] $screen_dma


  # Create instance: screen_status_pack, and set properties
  set screen_status_pack [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 screen_status_pack ]
  set_property CONFIG.NUM_PORTS {3} $screen_status_pack


  # Create instance: joystick_inputs, and set properties
  set block_name joystick_inputs
  set block_cell_name joystick_inputs
  if { [catch {set joystick_inputs [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $joystick_inputs eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: inspector, and set properties
  set block_name target_inspector
  set block_cell_name inspector
  if { [catch {set inspector [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $inspector eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.C_MAX_OBJECTS {12} $inspector


  # Create instance: servo_uart, and set properties
  set servo_uart [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uart16550:2.0 servo_uart ]
  set_property -dict [list \
    CONFIG.C_HAS_EXTERNAL_RCLK {0} \
    CONFIG.C_HAS_EXTERNAL_XIN {0} \
    CONFIG.C_IS_A_16550 {16550} \
    CONFIG.C_USE_MODEM_PORTS {0} \
    CONFIG.C_USE_USER_PORTS {0} \
  ] $servo_uart


  # Create instance: arm_direction, and set properties
  set arm_direction [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 arm_direction ]
  set_property -dict [list \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000000} \
    CONFIG.C_GPIO_WIDTH {2} \
    CONFIG.C_IS_DUAL {0} \
  ] $arm_direction


  # Create instance: arm_tx_request, and set properties
  set arm_tx_request [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 arm_tx_request ]
  set_property -dict [list \
    CONFIG.DIN_FROM {0} \
    CONFIG.DIN_TO {0} \
    CONFIG.DIN_WIDTH {2} \
    CONFIG.DOUT_WIDTH {1} \
  ] $arm_tx_request


  # Create instance: arm_rx_request, and set properties
  set arm_rx_request [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 arm_rx_request ]
  set_property -dict [list \
    CONFIG.DIN_FROM {1} \
    CONFIG.DIN_TO {1} \
    CONFIG.DIN_WIDTH {2} \
    CONFIG.DOUT_WIDTH {1} \
  ] $arm_rx_request


  # Create instance: arm_exclusive, and set properties
  set arm_exclusive [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 arm_exclusive ]
  set_property -dict [list \
    CONFIG.C_OPERATION {xor} \
    CONFIG.C_SIZE {1} \
  ] $arm_exclusive


  # Create instance: arm_tx_interlock, and set properties
  set arm_tx_interlock [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 arm_tx_interlock ]
  set_property -dict [list \
    CONFIG.C_OPERATION {and} \
    CONFIG.C_SIZE {1} \
  ] $arm_tx_interlock


  # Create instance: arm_rx_interlock, and set properties
  set arm_rx_interlock [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 arm_rx_interlock ]
  set_property -dict [list \
    CONFIG.C_OPERATION {and} \
    CONFIG.C_SIZE {1} \
  ] $arm_rx_interlock


  # Create instance: servo_rx_sync, and set properties
  set servo_rx_sync [ create_bd_cell -type ip -vlnv xilinx.com:ip:xpm_cdc_gen:1.0 servo_rx_sync ]
  set_property -dict [list \
    CONFIG.CDC_TYPE {xpm_cdc_single} \
    CONFIG.DEST_CLK_PERIOD {10000} \
    CONFIG.DEST_SYNC_FF {4} \
    CONFIG.SRC_CLK_PERIOD {10000} \
    CONFIG.SRC_INPUT_REG {false} \
  ] $servo_rx_sync


  # Create instance: servo_rx_guard, and set properties
  set block_name servo_rx_guard
  set block_cell_name servo_rx_guard
  if { [catch {set servo_rx_guard [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $servo_rx_guard eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  set_property -dict [ list \
   CONFIG.FREQ_HZ {100000000} \
 ] [get_bd_pins $servo_rx_guard/i_clk]

  # Create interface connections
  connect_bd_intf_net -intf_net cpu_bus_M00_AXI [get_bd_intf_pins cpu_bus/M00_AXI] [get_bd_intf_pins control_gpio/S_AXI]
  connect_bd_intf_net -intf_net cpu_bus_M01_AXI [get_bd_intf_pins cpu_bus/M01_AXI] [get_bd_intf_pins recognition_registers/S_AXI]
  connect_bd_intf_net -intf_net cpu_bus_M02_AXI [get_bd_intf_pins cpu_bus/M02_AXI] [get_bd_intf_pins gray_dma/S_AXI_LITE]
  connect_bd_intf_net -intf_net cpu_bus_M03_AXI [get_bd_intf_pins cpu_bus/M03_AXI] [get_bd_intf_pins dashboard_registers/S_AXI]
  connect_bd_intf_net -intf_net cpu_bus_M04_AXI [get_bd_intf_pins cpu_bus/M04_AXI] [get_bd_intf_pins screen_dma/S_AXI_LITE]
  connect_bd_intf_net -intf_net cpu_bus_M05_AXI [get_bd_intf_pins cpu_bus/M05_AXI] [get_bd_intf_pins servo_uart/S_AXI]
  connect_bd_intf_net -intf_net cpu_bus_M06_AXI [get_bd_intf_pins cpu_bus/M06_AXI] [get_bd_intf_pins arm_direction/S_AXI]
  connect_bd_intf_net -intf_net gray_dma_M_AXI_S2MM [get_bd_intf_pins gray_dma/M_AXI_S2MM] [get_bd_intf_pins memory_bus/S00_AXI]
  connect_bd_intf_net -intf_net gray_fifo_M_AXIS [get_bd_intf_pins gray_fifo/M_AXIS] [get_bd_intf_pins gray_dma/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net gray_reader_M_AXI [get_bd_intf_pins gray_reader/M_AXI] [get_bd_intf_pins memory_bus/S01_AXI]
  connect_bd_intf_net -intf_net memory_bus_M00_AXI [get_bd_intf_pins memory_bus/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0]
  connect_bd_intf_net -intf_net preview_ddr_M_AXI [get_bd_intf_pins preview_ddr/M_AXI] [get_bd_intf_pins memory_bus/S02_AXI]
  connect_bd_intf_net -intf_net ps_DDR [get_bd_intf_ports DDR] [get_bd_intf_pins ps/DDR]
  connect_bd_intf_net -intf_net ps_FIXED_IO [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps/FIXED_IO]
  connect_bd_intf_net -intf_net ps_M_AXI_GP0 [get_bd_intf_pins ps/M_AXI_GP0] [get_bd_intf_pins cpu_bus/S00_AXI]
  connect_bd_intf_net -intf_net screen_dma_M_AXI_S2MM [get_bd_intf_pins screen_dma/M_AXI_S2MM] [get_bd_intf_pins memory_bus/S03_AXI]
  connect_bd_intf_net -intf_net screen_fifo_M_AXIS [get_bd_intf_pins screen_fifo/M_AXIS] [get_bd_intf_pins screen_dma/S_AXIS_S2MM]

  # Create port connections
  connect_bd_net -net Net  [get_bd_ports cam_scl] \
  [get_bd_pins cam_cfg/cam_scl]
  connect_bd_net -net Net1  [get_bd_ports cam_sda] \
  [get_bd_pins cam_cfg/cam_sda]
  connect_bd_net -net arm_direction_gpio_io_o  [get_bd_pins arm_direction/gpio_io_o] \
  [get_bd_pins arm_tx_request/Din] \
  [get_bd_pins arm_rx_request/Din]
  connect_bd_net -net arm_exclusive_Res  [get_bd_pins arm_exclusive/Res] \
  [get_bd_pins arm_tx_interlock/Op2] \
  [get_bd_pins arm_rx_interlock/Op2]
  connect_bd_net -net arm_rx_interlock_Res  [get_bd_pins arm_rx_interlock/Res] \
  [get_bd_ports servo_rx_en] \
  [get_bd_pins servo_rx_guard/i_rx_enable]
  connect_bd_net -net arm_rx_request_Dout  [get_bd_pins arm_rx_request/Dout] \
  [get_bd_pins arm_exclusive/Op2] \
  [get_bd_pins arm_rx_interlock/Op1]
  connect_bd_net -net arm_tx_interlock_Res  [get_bd_pins arm_tx_interlock/Res] \
  [get_bd_ports servo_tx_en]
  connect_bd_net -net arm_tx_request_Dout  [get_bd_pins arm_tx_request/Dout] \
  [get_bd_pins arm_exclusive/Op1] \
  [get_bd_pins arm_tx_interlock/Op1]
  connect_bd_net -net cam_cfg_cam_pwdn  [get_bd_pins cam_cfg/cam_pwdn] \
  [get_bd_ports cam_pwdn]
  connect_bd_net -net cam_cfg_cam_rst_n  [get_bd_pins cam_cfg/cam_rst_n] \
  [get_bd_ports cam_rst_n]
  connect_bd_net -net cam_cfg_init_done  [get_bd_pins cam_cfg/init_done] \
  [get_bd_pins status/init_done]
  connect_bd_net -net cam_cfg_nack_count  [get_bd_pins cam_cfg/nack_count] \
  [get_bd_pins status/nack_count]
  connect_bd_net -net cam_cfg_sensor_status  [get_bd_pins cam_cfg/sensor_status] \
  [get_bd_pins snapshot_control/sensor_status]
  connect_bd_net -net cam_d_1  [get_bd_ports cam_d] \
  [get_bd_pins capture/cam_data]
  connect_bd_net -net cam_href_1  [get_bd_ports cam_href] \
  [get_bd_pins capture/cam_href]
  connect_bd_net -net cam_pclk_1  [get_bd_ports cam_pclk] \
  [get_bd_pins gray_fifo/s_axis_aclk] \
  [get_bd_pins capture/pclk] \
  [get_bd_pins preview_ddr/camera_clk] \
  [get_bd_pins recognition/i_camera_clk]
  connect_bd_net -net cam_vsync_1  [get_bd_ports cam_vsync] \
  [get_bd_pins capture/cam_vsync]
  connect_bd_net -net capture_de  [get_bd_pins capture/de] \
  [get_bd_pins preview_ddr/pixel_valid] \
  [get_bd_pins recognition/i_pixel_valid]
  connect_bd_net -net capture_frame_start  [get_bd_pins capture/frame_start] \
  [get_bd_pins preview_ddr/frame_start] \
  [get_bd_pins recognition/i_frame_start]
  connect_bd_net -net capture_line_start  [get_bd_pins capture/line_start] \
  [get_bd_pins preview_ddr/line_start] \
  [get_bd_pins recognition/i_line_start]
  connect_bd_net -net capture_rgb  [get_bd_pins capture/rgb] \
  [get_bd_pins preview_ddr/pixel_rgb] \
  [get_bd_pins recognition/i_rgb]
  connect_bd_net -net clocks_control_clk  [get_bd_pins clocks/control_clk] \
  [get_bd_pins cam_cfg/control_clk] \
  [get_bd_pins status/control_clk]
  connect_bd_net -net control_gpio_gpio_io_o  [get_bd_pins control_gpio/gpio_io_o] \
  [get_bd_pins cam_cfg/gpio_control] \
  [get_bd_pins snapshot_control/gpio_control] \
  [get_bd_pins screen_capture/i_control]
  connect_bd_net -net dashboard_o_axes_visible  [get_bd_pins dashboard/o_axes_visible] \
  [get_bd_pins display/axes_visible]
  connect_bd_net -net dashboard_o_bus_data  [get_bd_pins dashboard/o_bus_data] \
  [get_bd_pins dashboard_registers/bram_rddata_a]
  connect_bd_net -net dashboard_o_class_color_control  [get_bd_pins dashboard/o_class_color_control] \
  [get_bd_pins detection_overlay/i_class_color_control]
  connect_bd_net -net dashboard_o_command  [get_bd_pins dashboard/o_command] \
  [get_bd_pins inspector/i_command]
  connect_bd_net -net dashboard_o_command_toggle  [get_bd_pins dashboard/o_command_toggle] \
  [get_bd_pins inspector/i_command_toggle]
  connect_bd_net -net dashboard_o_overlays_hidden1  [get_bd_pins dashboard/o_overlays_hidden] \
  [get_bd_pins detection_overlay/i_overlays_hidden] \
  [get_bd_pins inspector/i_overlays_hidden]
  connect_bd_net -net dashboard_o_pixel  [get_bd_pins dashboard/o_pixel] \
  [get_bd_pins display/sidebar_pixel]
  connect_bd_net -net dashboard_registers_bram_addr_a  [get_bd_pins dashboard_registers/bram_addr_a] \
  [get_bd_pins dashboard/i_bus_address]
  connect_bd_net -net dashboard_registers_bram_en_a  [get_bd_pins dashboard_registers/bram_en_a] \
  [get_bd_pins dashboard/i_bus_enable]
  connect_bd_net -net dashboard_registers_bram_we_a  [get_bd_pins dashboard_registers/bram_we_a] \
  [get_bd_pins dashboard/i_bus_write]
  connect_bd_net -net dashboard_registers_bram_wrdata_a  [get_bd_pins dashboard_registers/bram_wrdata_a] \
  [get_bd_pins dashboard/i_bus_data]
  connect_bd_net -net detection_overlay_o_pixel  [get_bd_pins detection_overlay/o_pixel] \
  [get_bd_pins inspector/i_pixel]
  connect_bd_net -net detection_overlay_o_result_address  [get_bd_pins detection_overlay/o_result_address] \
  [get_bd_pins recognition/i_overlay_address]
  connect_bd_net -net detection_overlay_o_scene_boxes  [get_bd_pins detection_overlay/o_scene_boxes] \
  [get_bd_pins inspector/i_scene_boxes]
  connect_bd_net -net detection_overlay_o_scene_classes  [get_bd_pins detection_overlay/o_scene_classes] \
  [get_bd_pins inspector/i_scene_classes] \
  [get_bd_pins dashboard/i_scene_classes]
  connect_bd_net -net detection_overlay_o_scene_count  [get_bd_pins detection_overlay/o_scene_count] \
  [get_bd_pins inspector/i_scene_count] \
  [get_bd_pins dashboard/i_scene_count]
  connect_bd_net -net detection_overlay_o_scene_toggle  [get_bd_pins detection_overlay/o_scene_toggle] \
  [get_bd_pins inspector/i_scene_toggle] \
  [get_bd_pins dashboard/i_scene_toggle]
  connect_bd_net -net detection_overlay_o_scene_valid  [get_bd_pins detection_overlay/o_scene_valid] \
  [get_bd_pins inspector/i_scene_valid] \
  [get_bd_pins dashboard/i_scene_valid]
  connect_bd_net -net disabled_buttons_dout  [get_bd_pins disabled_buttons/dout] \
  [get_bd_pins snapshot_control/button]
  connect_bd_net -net display_frame_sent  [get_bd_pins display/frame_sent] \
  [get_bd_pins status/frame_sent]
  connect_bd_net -net display_framebuffer_address  [get_bd_pins display/framebuffer_address]
  connect_bd_net -net display_framebuffer_x  [get_bd_pins display/framebuffer_x] \
  [get_bd_pins preview_ddr/display_x] \
  [get_bd_pins detection_overlay/i_pixel_x] \
  [get_bd_pins inspector/i_pixel_x]
  connect_bd_net -net display_framebuffer_y  [get_bd_pins display/framebuffer_y] \
  [get_bd_pins preview_ddr/display_y] \
  [get_bd_pins detection_overlay/i_pixel_y] \
  [get_bd_pins inspector/i_pixel_y]
  connect_bd_net -net display_preview_row  [get_bd_pins display/preview_row] \
  [get_bd_pins preview_ddr/display_next_row]
  connect_bd_net -net display_preview_row_start  [get_bd_pins display/preview_row_start] \
  [get_bd_pins preview_ddr/display_row_start]
  connect_bd_net -net display_preview_vblank  [get_bd_pins display/preview_vblank] \
  [get_bd_pins preview_ddr/display_vblank] \
  [get_bd_pins detection_overlay/i_frame_start] \
  [get_bd_pins inspector/i_vblank] \
  [get_bd_pins dashboard/i_vblank]
  connect_bd_net -net display_q_blue  [get_bd_pins display/q_blue] \
  [get_bd_pins serializer/q_blue]
  connect_bd_net -net display_q_green  [get_bd_pins display/q_green] \
  [get_bd_pins serializer/q_green]
  connect_bd_net -net display_q_red  [get_bd_pins display/q_red] \
  [get_bd_pins serializer/q_red]
  connect_bd_net -net display_sidebar_x  [get_bd_pins display/sidebar_x] \
  [get_bd_pins dashboard/i_pixel_x]
  connect_bd_net -net display_sidebar_y  [get_bd_pins display/sidebar_y] \
  [get_bd_pins dashboard/i_pixel_y]
  connect_bd_net -net display_snapshot_rgb  [get_bd_pins display/snapshot_rgb] \
  [get_bd_pins screen_capture/pixel_rgb]
  connect_bd_net -net display_snapshot_start  [get_bd_pins display/snapshot_start] \
  [get_bd_pins screen_capture/frame_start]
  connect_bd_net -net display_snapshot_valid  [get_bd_pins display/snapshot_valid] \
  [get_bd_pins screen_capture/pixel_valid]
  connect_bd_net -net frame_store_display_pixel  [get_bd_pins preview_ddr/display_pixel] \
  [get_bd_pins detection_overlay/i_pixel]
  connect_bd_net -net frame_store_frame_complete  [get_bd_pins preview_ddr/frame_complete] \
  [get_bd_pins ready/frame_complete]
  connect_bd_net -net gray_dma_s2mm_introut  [get_bd_pins gray_dma/s2mm_introut] \
  [get_bd_pins recognition/i_dma_done]
  connect_bd_net -net gray_fifo_s_axis_tready  [get_bd_pins gray_fifo/s_axis_tready] \
  [get_bd_pins recognition/i_stream_ready]
  connect_bd_net -net gray_reader_o_data  [get_bd_pins gray_reader/o_data] \
  [get_bd_pins recognition/i_frame_data]
  connect_bd_net -net gray_reader_o_error  [get_bd_pins gray_reader/o_error] \
  [get_bd_pins recognition/i_frame_error]
  connect_bd_net -net gray_reader_o_idle  [get_bd_pins gray_reader/o_idle] \
  [get_bd_pins recognition/i_gray_idle]
  connect_bd_net -net gray_reader_o_valid  [get_bd_pins gray_reader/o_valid] \
  [get_bd_pins recognition/i_frame_valid]
  connect_bd_net -net inspector_o_command_ack  [get_bd_pins inspector/o_command_ack] \
  [get_bd_pins dashboard/i_command_ack]
  connect_bd_net -net inspector_o_pixel  [get_bd_pins inspector/o_pixel] \
  [get_bd_pins display/framebuffer_pixel]
  connect_bd_net -net inspector_o_status  [get_bd_pins inspector/o_status] \
  [get_bd_pins dashboard/i_selection_status]
  connect_bd_net -net joy_axis_x_n_1  [get_bd_ports joy_axis_x_n] \
  [get_bd_pins joystick_inputs/i_axis_x_n]
  connect_bd_net -net joy_axis_x_p_1  [get_bd_ports joy_axis_x_p] \
  [get_bd_pins joystick_inputs/i_axis_x_p]
  connect_bd_net -net joy_axis_y_n_1  [get_bd_ports joy_axis_y_n] \
  [get_bd_pins joystick_inputs/i_axis_y_n]
  connect_bd_net -net joy_axis_y_p_1  [get_bd_ports joy_axis_y_p] \
  [get_bd_pins joystick_inputs/i_axis_y_p]
  connect_bd_net -net joy_keys_n_1  [get_bd_ports joy_keys_n] \
  [get_bd_pins joystick_inputs/i_keys_n]
  connect_bd_net -net joystick_inputs_o_axis_x  [get_bd_pins joystick_inputs/o_axis_x] \
  [get_bd_pins dashboard/i_axis_x]
  connect_bd_net -net joystick_inputs_o_axis_y  [get_bd_pins joystick_inputs/o_axis_y] \
  [get_bd_pins dashboard/i_axis_y]
  connect_bd_net -net joystick_inputs_o_keys  [get_bd_pins joystick_inputs/o_keys] \
  [get_bd_pins dashboard/i_keys]
  connect_bd_net -net joystick_inputs_o_samples  [get_bd_pins joystick_inputs/o_samples] \
  [get_bd_pins dashboard/i_samples]
  connect_bd_net -net one_dout  [get_bd_pins one/dout] \
  [get_bd_pins ps_reset/dcm_locked]
  connect_bd_net -net overlay_reset_o_rstn  [get_bd_pins overlay_reset/o_rstn] \
  [get_bd_pins screen_capture/reset_n] \
  [get_bd_pins detection_overlay/i_rstn] \
  [get_bd_pins inspector/i_rstn] \
  [get_bd_pins dashboard/i_display_rstn]
  connect_bd_net -net preview_ddr_camera_status  [get_bd_pins preview_ddr/camera_status] \
  [get_bd_pins snapshot_control/camera_status]
  connect_bd_net -net preview_ddr_o_camera_frames  [get_bd_pins preview_ddr/o_camera_frames] \
  [get_bd_pins dashboard/i_camera_frames]
  connect_bd_net -net preview_ddr_o_display_frames  [get_bd_pins preview_ddr/o_display_frames] \
  [get_bd_pins dashboard/i_display_frames]
  connect_bd_net -net preview_ddr_o_idle  [get_bd_pins preview_ddr/o_idle] \
  [get_bd_pins recognition/i_preview_idle]
  connect_bd_net -net preview_ddr_o_video_status  [get_bd_pins preview_ddr/o_video_status] \
  [get_bd_pins dashboard/i_video_status]
  connect_bd_net -net preview_ddr_o_written_frames  [get_bd_pins preview_ddr/o_written_frames] \
  [get_bd_pins dashboard/i_written_frames]
  connect_bd_net -net preview_ddr_screen_status  [get_bd_pins preview_ddr/screen_status] \
  [get_bd_pins snapshot_control/screen_status]
  connect_bd_net -net ps_FCLK_CLK0  [get_bd_pins ps/FCLK_CLK0] \
  [get_bd_pins ps/M_AXI_GP0_ACLK] \
  [get_bd_pins ps/S_AXI_HP0_ACLK] \
  [get_bd_pins ps_reset/slowest_sync_clk] \
  [get_bd_pins video_clock/sys_clk] \
  [get_bd_pins cpu_bus/aclk] \
  [get_bd_pins control_gpio/s_axi_aclk] \
  [get_bd_pins recognition_registers/s_axi_aclk] \
  [get_bd_pins memory_bus/aclk] \
  [get_bd_pins gray_fifo/m_axis_aclk] \
  [get_bd_pins gray_dma/s_axi_lite_aclk] \
  [get_bd_pins gray_dma/m_axi_s2mm_aclk] \
  [get_bd_pins gray_reader/i_clk] \
  [get_bd_pins dashboard_registers/s_axi_aclk] \
  [get_bd_pins screen_fifo/m_axis_aclk] \
  [get_bd_pins screen_dma/s_axi_lite_aclk] \
  [get_bd_pins screen_dma/m_axi_s2mm_aclk] \
  [get_bd_pins snapshot_control/clk] \
  [get_bd_pins joystick_inputs/i_clk] \
  [get_bd_pins servo_uart/s_axi_aclk] \
  [get_bd_pins arm_direction/s_axi_aclk] \
  [get_bd_pins servo_rx_sync/src_clk] \
  [get_bd_pins servo_rx_sync/dest_clk] \
  [get_bd_pins servo_rx_guard/i_clk] \
  [get_bd_pins preview_ddr/i_clk] \
  [get_bd_pins recognition/i_clk] \
  [get_bd_pins dashboard/i_clk]
  connect_bd_net -net ps_FCLK_RESET0_N  [get_bd_pins ps/FCLK_RESET0_N] \
  [get_bd_pins ps_reset/ext_reset_in]
  connect_bd_net -net ps_reset_peripheral_aresetn  [get_bd_pins ps_reset/peripheral_aresetn] \
  [get_bd_pins cpu_bus/aresetn] \
  [get_bd_pins control_gpio/s_axi_aresetn] \
  [get_bd_pins recognition_registers/s_axi_aresetn] \
  [get_bd_pins memory_bus/aresetn] \
  [get_bd_pins gray_dma/axi_resetn] \
  [get_bd_pins gray_reader/i_rstn] \
  [get_bd_pins dashboard_registers/s_axi_aresetn] \
  [get_bd_pins screen_dma/axi_resetn] \
  [get_bd_pins snapshot_control/reset_n] \
  [get_bd_pins joystick_inputs/i_rstn] \
  [get_bd_pins servo_uart/s_axi_aresetn] \
  [get_bd_pins arm_direction/s_axi_aresetn] \
  [get_bd_pins servo_rx_guard/i_rstn] \
  [get_bd_pins recognition/i_rstn] \
  [get_bd_pins dashboard/i_rstn]
  connect_bd_net -net ready_camera_ready  [get_bd_pins ready/camera_ready] \
  [get_bd_pins status/camera_ready] \
  [get_bd_pins display/camera_ready]
  connect_bd_net -net recognition_o_bus_data  [get_bd_pins recognition/o_bus_data] \
  [get_bd_pins recognition_registers/bram_rddata_a]
  connect_bd_net -net recognition_o_camera_rstn  [get_bd_pins recognition/o_camera_rstn] \
  [get_bd_pins gray_fifo/s_axis_aresetn]
  connect_bd_net -net recognition_o_capture_active  [get_bd_pins recognition/o_capture_active]
  connect_bd_net -net recognition_o_frame_address  [get_bd_pins recognition/o_frame_address] \
  [get_bd_pins gray_reader/i_address]
  connect_bd_net -net recognition_o_frame_bank  [get_bd_pins recognition/o_frame_bank] \
  [get_bd_pins gray_reader/i_bank]
  connect_bd_net -net recognition_o_frame_enable  [get_bd_pins recognition/o_frame_enable] \
  [get_bd_pins gray_reader/i_enable]
  connect_bd_net -net recognition_o_frame_invalidate  [get_bd_pins recognition/o_frame_invalidate] \
  [get_bd_pins gray_reader/i_invalidate]
  connect_bd_net -net recognition_o_gray_base  [get_bd_pins recognition/o_gray_base] \
  [get_bd_pins gray_reader/i_base_address]
  connect_bd_net -net recognition_o_object_count  [get_bd_pins recognition/o_object_count] \
  [get_bd_pins detection_overlay/i_count_async]
  connect_bd_net -net recognition_o_overlay_data  [get_bd_pins recognition/o_overlay_data] \
  [get_bd_pins detection_overlay/i_result_data]
  connect_bd_net -net recognition_o_preview_base  [get_bd_pins recognition/o_preview_base] \
  [get_bd_pins preview_ddr/i_base_address]
  connect_bd_net -net recognition_o_preview_hold  [get_bd_pins recognition/o_preview_hold]
  connect_bd_net -net recognition_o_preview_run  [get_bd_pins recognition/o_preview_run] \
  [get_bd_pins preview_ddr/i_run]
  connect_bd_net -net recognition_o_results_valid  [get_bd_pins recognition/o_results_valid] \
  [get_bd_pins detection_overlay/i_done_async]
  connect_bd_net -net recognition_o_stream_data  [get_bd_pins recognition/o_stream_data] \
  [get_bd_pins gray_fifo/s_axis_tdata]
  connect_bd_net -net recognition_o_stream_keep  [get_bd_pins recognition/o_stream_keep] \
  [get_bd_pins gray_fifo/s_axis_tkeep]
  connect_bd_net -net recognition_o_stream_last  [get_bd_pins recognition/o_stream_last] \
  [get_bd_pins gray_fifo/s_axis_tlast]
  connect_bd_net -net recognition_o_stream_valid  [get_bd_pins recognition/o_stream_valid] \
  [get_bd_pins gray_fifo/s_axis_tvalid]
  connect_bd_net -net recognition_registers_bram_addr_a  [get_bd_pins recognition_registers/bram_addr_a] \
  [get_bd_pins recognition/i_bus_address]
  connect_bd_net -net recognition_registers_bram_en_a  [get_bd_pins recognition_registers/bram_en_a] \
  [get_bd_pins recognition/i_bus_enable]
  connect_bd_net -net recognition_registers_bram_we_a  [get_bd_pins recognition_registers/bram_we_a] \
  [get_bd_pins recognition/i_bus_write]
  connect_bd_net -net recognition_registers_bram_wrdata_a  [get_bd_pins recognition_registers/bram_wrdata_a] \
  [get_bd_pins recognition/i_bus_data]
  connect_bd_net -net screen_capture_busy  [get_bd_pins screen_capture/busy] \
  [get_bd_pins screen_status_pack/In0]
  connect_bd_net -net screen_capture_done  [get_bd_pins screen_capture/done] \
  [get_bd_pins screen_status_pack/In1]
  connect_bd_net -net screen_capture_error  [get_bd_pins screen_capture/error] \
  [get_bd_pins screen_status_pack/In2]
  connect_bd_net -net screen_capture_m_axis_tdata  [get_bd_pins screen_capture/m_axis_tdata] \
  [get_bd_pins screen_fifo/s_axis_tdata]
  connect_bd_net -net screen_capture_m_axis_tkeep  [get_bd_pins screen_capture/m_axis_tkeep] \
  [get_bd_pins screen_fifo/s_axis_tkeep]
  connect_bd_net -net screen_capture_m_axis_tlast  [get_bd_pins screen_capture/m_axis_tlast] \
  [get_bd_pins screen_fifo/s_axis_tlast]
  connect_bd_net -net screen_capture_m_axis_tvalid  [get_bd_pins screen_capture/m_axis_tvalid] \
  [get_bd_pins screen_fifo/s_axis_tvalid]
  connect_bd_net -net screen_capture_o_fifo_rstn  [get_bd_pins screen_capture/o_fifo_rstn] \
  [get_bd_pins screen_fifo/s_axis_aresetn]
  connect_bd_net -net screen_fifo_s_axis_tready  [get_bd_pins screen_fifo/s_axis_tready] \
  [get_bd_pins screen_capture/m_axis_tready]
  connect_bd_net -net screen_status_pack_dout  [get_bd_pins screen_status_pack/dout] \
  [get_bd_pins snapshot_control/screenshot_status]
  connect_bd_net -net serializer_hdmi_clk_n  [get_bd_pins serializer/hdmi_clk_n] \
  [get_bd_ports hdmi_clk_n]
  connect_bd_net -net serializer_hdmi_clk_p  [get_bd_pins serializer/hdmi_clk_p] \
  [get_bd_ports hdmi_clk_p]
  connect_bd_net -net serializer_hdmi_d_n  [get_bd_pins serializer/hdmi_d_n] \
  [get_bd_ports hdmi_d_n]
  connect_bd_net -net serializer_hdmi_d_p  [get_bd_pins serializer/hdmi_d_p] \
  [get_bd_ports hdmi_d_p]
  connect_bd_net -net servo_rx_guard_o_uart_sin  [get_bd_pins servo_rx_guard/o_uart_sin] \
  [get_bd_pins servo_uart/sin]
  connect_bd_net -net servo_rx_sync_dest_out  [get_bd_pins servo_rx_sync/dest_out] \
  [get_bd_pins servo_rx_guard/i_rx_sync]
  connect_bd_net -net servo_rxd_1  [get_bd_ports servo_rxd] \
  [get_bd_pins servo_rx_sync/src_in]
  connect_bd_net -net servo_uart_sout  [get_bd_pins servo_uart/sout] \
  [get_bd_ports servo_txd]
  connect_bd_net -net snapshot_control_capture_reset_n  [get_bd_pins snapshot_control/capture_reset_n] \
  [get_bd_pins preview_ddr/i_rstn]
  connect_bd_net -net snapshot_control_gpio_status  [get_bd_pins snapshot_control/gpio_status] \
  [get_bd_pins control_gpio/gpio2_io_i]
  connect_bd_net -net snapshot_control_rgb_led  [get_bd_pins snapshot_control/rgb_led] \
  [get_bd_ports save_rgb]
  connect_bd_net -net snapshot_control_screen_arm  [get_bd_pins snapshot_control/screen_arm] \
  [get_bd_pins screen_capture/arm_async]
  connect_bd_net -net status_led  [get_bd_pins status/led] \
  [get_bd_ports led]
  connect_bd_net -net status_zero_dout  [get_bd_pins status_zero/dout]
  connect_bd_net -net sys_clk_1  [get_bd_ports sys_clk] \
  [get_bd_pins clocks/sys_clk]
  connect_bd_net -net video_clock_pixel_clk  [get_bd_pins video_clock/pixel_clk] \
  [get_bd_pins ready/sys_clk] \
  [get_bd_pins status/sys_clk] \
  [get_bd_pins serializer/clk_1x] \
  [get_bd_pins screen_fifo/s_axis_aclk] \
  [get_bd_pins screen_capture/clk] \
  [get_bd_pins preview_ddr/display_clk] \
  [get_bd_pins detection_overlay/i_clk] \
  [get_bd_pins inspector/i_clk] \
  [get_bd_pins dashboard/i_display_clk] \
  [get_bd_pins display/clk]
  connect_bd_net -net video_clock_reset  [get_bd_pins video_clock/reset] \
  [get_bd_pins serializer/rst] \
  [get_bd_pins overlay_reset/i_reset] \
  [get_bd_pins display/reset]
  connect_bd_net -net video_clock_serial_clk  [get_bd_pins video_clock/serial_clk] \
  [get_bd_pins serializer/clk_5x]

  # Create address segments
  assign_bd_address -offset 0x41210000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs arm_direction/S_AXI/Reg] -force
  assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs control_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0x43000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs dashboard_registers/S_AXI/Mem0] -force
  assign_bd_address -offset 0x40400000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs gray_dma/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x42000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs recognition_registers/S_AXI/Mem0] -force
  assign_bd_address -offset 0x40410000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs screen_dma/S_AXI_LITE/Reg] -force
  assign_bd_address -offset 0x43C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs servo_uart/S_AXI/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces gray_dma/Data_S2MM] [get_bd_addr_segs ps/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces gray_reader/M_AXI] [get_bd_addr_segs ps/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces preview_ddr/M_AXI] [get_bd_addr_segs ps/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x20000000 -target_address_space [get_bd_addr_spaces screen_dma/Data_S2MM] [get_bd_addr_segs ps/S_AXI_HP0/HP0_DDR_LOWOCM] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


