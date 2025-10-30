# !/usr/bin/env bash
set -e

# Vivado environment
source /tools/Xilinx/Vivado/2024.1/settings64.sh

# Top module and FPGA part
TOP_MODULE="top"
FPGA_PART="xczu7ev-ffvc1156-2-i"

# Create build folder
mkdir -p ../build

# Run Vivado batch
vivado -mode batch -notrace -source  build_bitstream.tcl -tclargs $TOP_MODULE $FPGA_PART

echo "Bitstream generated: build/${TOP_MODULE}.bit"