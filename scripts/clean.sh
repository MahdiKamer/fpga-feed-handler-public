# !/bin/bash
# Clean.sh - Clean up build, IP, and Vivado logs
# Run this from the scripts/ folder

set -e

# Move to project root (one level up from scripts/)
cd "$(dirname "$0")/.."

echo "Cleaning build/ and IP/ folders..."
rm -rf build
rm -rf IP
rm -rf scripts/.Xil

echo "Cleaning Vivado logs in scripts/..."
rm -f scripts/*.jou
rm -f scripts/*.log
rm -f scripts/*.rpt
rm -f scripts/*.str
rm -f scripts/*.pb
rm -f scripts/clockInfo.txt

echo "Cleanup complete."