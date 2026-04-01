##############################################################################
# Clock
##############################################################################
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS18} [get_ports CLK100MHZ]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports CLK100MHZ]

##############################################################################
# SPI to Accelerometer (ADXL345)
##############################################################################
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS18} [get_ports ACL_MISO]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS18} [get_ports ACL_MOSI]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS18} [get_ports ACL_SCLK]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS18} [get_ports ACL_CSN]

##############################################################################
# LEDs (ALL 16!)
##############################################################################
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS18} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS18} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS18} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS18} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS18} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS18} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS18} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS18} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS18} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS18} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS18} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS18} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS18} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS18} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS18} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS18} [get_ports {LED[15]}]

##############################################################################
# 7-Segment Display
##############################################################################
# Anodes
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS18} [get_ports {AN[0]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS18} [get_ports {AN[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS18} [get_ports {AN[2]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS18} [get_ports {AN[3]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS18} [get_ports {AN[4]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS18} [get_ports {AN[5]}]
set_property -dict {PACKAGE_PIN K2  IOSTANDARD LVCMOS18} [get_ports {AN[6]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS18} [get_ports {AN[7]}]

# Segments
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS18} [get_ports {SEG[0]}]
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS18} [get_ports {SEG[1]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS18} [get_ports {SEG[2]}]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS18} [get_ports {SEG[3]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS18} [get_ports {SEG[4]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS18} [get_ports {SEG[5]}]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS18} [get_ports {SEG[6]}]

# Decimal Point
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS18} [get_ports DP]

##############################################################################
# Configuration Bank
##############################################################################
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]