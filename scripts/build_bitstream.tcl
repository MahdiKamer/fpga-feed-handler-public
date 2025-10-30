# --------------------------------------------------------------------
# Vivado Non-Project Build Flow
# Usage: vivado -mode batch -source build_bitstream.tcl -tclargs <TOP> <PART>
# Example: vivado -mode batch -source build_bitstream.tcl -tclargs top xczu7ev-ffvc1156-2-i
# --------------------------------------------------------------------

# Args
set TOP_MODULE [lindex $argv 0]
set FPGA_PART  [lindex $argv 1]

# --------------------------------------------------------------------
# Directories
# --------------------------------------------------------------------
file mkdir ../build
file mkdir ../IP

# --------------------------------------------------------------------
# Set device part
# --------------------------------------------------------------------
set_part $FPGA_PART

# --------------------------------------------------------------------
# Clocking Wizard IP
# --------------------------------------------------------------------
set clk_ip ../IP/clk_wiz_0/clk_wiz_0.xci
if {![file exists $clk_ip]} {
    puts "==> Creating clk_wiz_0..."
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
        -module_name clk_wiz_0 -dir ../IP

    set_property -dict [list \
        CONFIG.CLKIN1_JITTER_PS {50.0} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
        CONFIG.CLKOUT2_REQUESTED_PHASE {90} \
        CONFIG.CLKOUT2_USED {true} \
        CONFIG.MMCM_CLKIN1_PERIOD {5.000} \
        CONFIG.MMCM_CLKFBOUT_MULT_F {6.250} \
        CONFIG.MMCM_CLKOUT0_DIVIDE_F {10.000} \
        CONFIG.MMCM_CLKOUT1_DIVIDE {10} \
        CONFIG.MMCM_CLKOUT1_PHASE {90.000} \
        CONFIG.NUM_OUT_CLKS {2} \
        CONFIG.PRIM_IN_FREQ {200.000} \
        CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    ] [get_ips clk_wiz_0]
}

# Refresh IP
reset_target all [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
read_ip $clk_ip
set_property generate_synth_checkpoint false [get_files $clk_ip]

# --------------------------------------------------------------------
# ILA IP
# --------------------------------------------------------------------
set ila_ip ../IP/ila_0/ila_0.xci
if {![file exists $ila_ip]} {
    puts "==> Creating ila_0..."
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
        -module_name ila_0 -dir ../IP

    # Set number of probes and each probe width (0..15)
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES {13} \
        CONFIG.C_PROBE0_WIDTH {64} \
        CONFIG.C_PROBE1_WIDTH {64} \
        CONFIG.C_PROBE2_WIDTH {32} \
        CONFIG.C_PROBE3_WIDTH {1}  \
        CONFIG.C_PROBE4_WIDTH {1}  \
        CONFIG.C_PROBE5_WIDTH {32} \
        CONFIG.C_PROBE6_WIDTH {8} \
        CONFIG.C_PROBE7_WIDTH {3}  \
        CONFIG.C_PROBE8_WIDTH {2}  \
        CONFIG.C_PROBE9_WIDTH {2}  \
        CONFIG.C_PROBE10_WIDTH {8} \
        CONFIG.C_PROBE11_WIDTH {3} \
        CONFIG.C_PROBE12_WIDTH {2} \
    ] [get_ips ila_0]

    puts "==> ila_0 created with 16 probes"
} else {
    puts "==> ila_0 IP already exists at $ila_ip"
}

reset_target all [get_ips ila_0]
generate_target all [get_ips ila_0]
read_ip $ila_ip
set_property generate_synth_checkpoint false [get_files $ila_ip]

# --------------------------------------------------------------------
# Ethernet MAC + Support RTL
# --------------------------------------------------------------------
set verilog_ethernet_dir "../deps/verilog-ethernet"
read_verilog $verilog_ethernet_dir/rtl/eth_mac_1g_rgmii_fifo.v
read_verilog $verilog_ethernet_dir/rtl/eth_mac_1g_fifo.v
read_verilog $verilog_ethernet_dir/rtl/ssio_ddr_in.v
read_verilog $verilog_ethernet_dir/rtl/ssio_ddr_out.v
read_verilog $verilog_ethernet_dir/rtl/rgmii_phy_if.v
read_verilog $verilog_ethernet_dir/rtl/eth_mac_1g_rgmii.v
read_verilog $verilog_ethernet_dir/rtl/eth_mac_1g.v
read_verilog $verilog_ethernet_dir/lib/axis/rtl/axis_async_fifo_adapter.v
read_verilog $verilog_ethernet_dir/lib/axis/rtl/axis_async_fifo.v
read_verilog $verilog_ethernet_dir/rtl/axis_gmii_rx.v
read_verilog $verilog_ethernet_dir/rtl/axis_gmii_tx.v
read_verilog $verilog_ethernet_dir/rtl/lfsr.v
read_verilog $verilog_ethernet_dir/rtl/iddr.v
read_verilog $verilog_ethernet_dir/rtl/oddr.v

# --------------------------------------------------------------------
# Project RTL
# --------------------------------------------------------------------
read_verilog [glob ../rtl/*.v]
read_verilog -sv [glob ../rtl/*.sv]

# --------------------------------------------------------------------
# Constraints
# --------------------------------------------------------------------
foreach xdc [glob -nocomplain ../constraints/*.xdc] { read_xdc $xdc }

# --------------------------------------------------------------------
# Set top module
# --------------------------------------------------------------------
set_property top $TOP_MODULE [current_fileset]

# --------------------------------------------------------------------
# Synthesis
# --------------------------------------------------------------------
synth_design -top $TOP_MODULE -part $FPGA_PART
# Report_clocks
# Generate synthesis reports
set stage "synth"
if {[file exists write_reports.tcl]} { source -notrace write_reports.tcl } \
    else { puts "Warning: write_reports.tcl not found, skipping report generation" }

# --------------------------------------------------------------------
# Implementation (optional) implkey =0 --> no implementation
# --------------------------------------------------------------------
set implkey 1
if {$implkey} {

    # Optimization and place
    opt_design
    place_design

    set stage "place"
    if {[file exists write_reports.tcl]} { source -notrace write_reports.tcl }

    # Routing
    route_design
    set stage "route"
    if {[file exists write_reports.tcl]} { source -notrace write_reports.tcl }

    # Post-route reports
    set stage "final"
    if {[file exists write_reports.tcl]} { source -notrace write_reports.tcl }

    # Write checkpoint (.dcp)
    write_checkpoint -force -file ../build/${TOP_MODULE}.dcp

    # Final bitstream
    write_bitstream -force ../build/${TOP_MODULE}.bit
    puts "Build finished: build/${TOP_MODULE}.bit"
}