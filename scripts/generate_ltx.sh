# !/bin/bash
# Generate_probes.sh
# Usage: ./generate_ltx.sh

# Vivado environment
source /tools/Xilinx/Vivado/2024.1/settings64.sh


TOP_MODULE="top"
CHECKPOINT="../build/${TOP_MODULE}.dcp"
LTX_FILE="../build/${TOP_MODULE}.ltx"

vivado -mode batch -notrace -source /dev/stdin <<EOF
# Open the implemented design checkpoint
open_checkpoint $CHECKPOINT

# Generate the hardware probes file
write_debug_probes -force -file $LTX_FILE
exit
EOF

echo "LTX file generated: $LTX_FILE"