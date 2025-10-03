# !/usr/bin/env bash

# ----------------------------------------------------------------
# Automated batch simulation script with per-TB simulation times
# ----------------------------------------------------------------

# Load Vivado environment
source /tools/Xilinx/Vivado/2024.1/settings64.sh

rtl_dir="../rtl"
model_dir="../models"
tb_dir="../tb"
sim_dir="../sim"
config_file="sim-config.txt"

# -----------------------------
# Clean sim folder
# -----------------------------
rm -rf "$sim_dir"
mkdir -p "$sim_dir"

# -----------------------------
# Load simulation configuration
# -----------------------------
declare -A sim_times
default_time="2000ns"

echo "Loading simulation configuration from $config_file"
while IFS=: read -r key value; do
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)
    echo " -> Setting sim_times[$key] = $value"   # <--- add this line
    sim_times["$key"]="$value"
done < "$config_file"


# -----------------------------
# Compile RTL files
# -----------------------------
for rtl in "$rtl_dir"/*; do
    [ -e "$rtl" ] || continue
    ext="${rtl##*.}"
    if [ "$ext" = "sv" ]; then
        echo "Compiling RTL (SV): $rtl"
        xvlog -sv "$rtl"
    elif [ "$ext" = "v" ]; then
        echo "Compiling RTL (Verilog): $rtl"
        xvlog "$rtl"
    fi
done
# -----------------------------
# Compile model files
# -----------------------------
for model in "$model_dir"/*; do
    [ -e "$model" ] || continue
    ext="${model##*.}"
    if [ "$ext" = "sv" ]; then
        echo "Compiling model (SV): $model"
        xvlog -sv "$model"
    elif [ "$ext" = "v" ]; then
        echo "Compiling model (Verilog): $model"
        xvlog "$model"
    fi
done

# -----------------------------
# Compile and simulate each TB
# -----------------------------
summary=()

for tb in "$tb_dir"/*.v "$tb_dir"/*.sv; do
    [ -e "$tb" ] || continue

    ext="${tb##*.}"
    if [ "$ext" = "sv" ]; then
        echo "Compiling Testbench (SV): $tb"
        xvlog -sv "$tb"
    elif [ "$ext" = "v" ]; then
        echo "Compiling Testbench (Verilog): $tb"
        xvlog "$tb"
    fi

    # Tb_mod=$(basename "$tb" | sed 's/\.[^.]*$//') # module name
    tb_mod=$(basename "$tb" | sed -E 's/\.(v|sv)$//')
    # Debug line
    # Echo "Testbench file: $tb -> module: $tb_mod -> runtime: ${sim_times[$tb_mod]:-$default_time}"

    xelab -debug typical "$tb_mod" -s "${tb_mod}_sim"

    # Determine run time
    if [ -n "${sim_times[$tb_mod]}" ]; then
        run_time="${sim_times[$tb_mod]}"
    else
        run_time="$default_time"
    fi
    wdb_file="$sim_dir/${tb_mod}.wdb"
    tcl_tmp="$sim_dir/run_${tb_mod}.tcl"

    # Create temporary run Tcl
    cat > "$tcl_tmp" <<EOL
log_wave [get_objects -r /*]
run $run_time
quit
EOL

    # Run xsim with WDB output
    echo "Running simulation for $tb_mod ($run_time) -> $wdb_file"
    xsim "${tb_mod}_sim" -wdb "$wdb_file" -tclbatch "$tcl_tmp"

    summary+=("$tb_mod | $run_time | $wdb_file")
done

# -----------------------------
# Cleanup unnecessary files
# -----------------------------
find . -maxdepth 1 -type f \( -name "*.jou" -o -name "*.log" -o -name "*.pb" -o -name "*.vcd" \) -delete
rm -rf xsim.dir

# -----------------------------
# Print summary
# -----------------------------
echo ""
echo "================ Simulation Summary ================"
printf "%-20s %-10s %-50s\n" "Testbench" "Run Time" "WDB File"
echo "----------------------------------------------------"
for entry in "${summary[@]}"; do
    IFS="|" read -r tb_mod run_time wdb_file <<< "$entry"
    printf "%-20s %-10s %-50s\n" "$tb_mod" "$run_time" "$wdb_file"
done
echo "===================================================="
echo "All simulations complete. Waveforms saved in $sim_dir"