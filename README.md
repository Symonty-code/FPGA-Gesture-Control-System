# FPGA-Gesture-Control-System

FPGA-based gesture-controlled user interface using accelerometer (Verilog, Nexys A7).

## Project Overview
This project implements a gesture-based control system on the Nexys A7 FPGA board using the onboard 3-axis accelerometer. The system detects gestures such as tilt, shake, tap, and flip, and converts them into control actions through digital hardware.

## Features
- SPI-based accelerometer data acquisition
- Sample-and-hold stabilization
- Moving average filtering for noise reduction
- Gesture detection for tilt, shake, tap, and flip
- Debouncing and temporal stability control
- FSM-based menu navigation and execution control
- LED and seven-segment display output

## Technologies Used
- Verilog HDL
- Xilinx Vivado
- Nexys A7 FPGA Board
- Onboard Accelerometer

## Files Included
- Source Verilog modules
- Constraint file (`.xdc`)
- Testbench files for simulation

## Output
The system uses gesture input to control menu navigation and different LED-based operation modes. The selected mode is shown on the seven-segment display, while LEDs provide real-time visual feedback.

## Author / Team
EEE project team, BUET
