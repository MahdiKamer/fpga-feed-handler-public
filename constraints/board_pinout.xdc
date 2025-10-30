# ##############################################################################
# board_pinout.xdc - Pinout & I/O Standards
# Derived pin mapping from vendor reference documentation
# ##############################################################################

# ------------------------------------------------------------------
# Differential 200 MHz PL reference clock on AJ9/AK9 (Bank66, VCCO=1.2V)
# ------------------------------------------------------------------
set_property PACKAGE_PIN AJ9 [get_ports clk_200_p]
set_property PACKAGE_PIN AK9 [get_ports clk_200_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports {clk_200_p clk_200_n}]
# External 100 Ohm across AJ9/AK9 handles termination on the board.
# Do NOT set internal DIFF_TERM for DIFF_SSTL12 (unsupported).
# Direct the router to use dedicated clock routing on the physical pin object:
# Set_property CLOCK_DEDICATED_ROUTE TRUE [get_ports clk_200_p]

# ------------------------------------------------------------------
# PL user key (active-low, Bank 87 @ 3.3V)
# External 10k pull-up to 3.3V and 1k series resistor to FPGA pin.
# ------------------------------------------------------------------
set_property PACKAGE_PIN J9 [get_ports pl_key_n]
set_property IOSTANDARD LVCMOS33 [get_ports pl_key_n]
# External pull-up present - disable internal pullup to avoid redundancy
set_property PULLUP FALSE [get_ports pl_key_n]

# ------------------------------------------------------------------
# PHY2 (PL RGMII) pin mappings - BANK64/65 -> VCCO = 1.8V
# ------------------------------------------------------------------

# MDIO / MDC / RESET
set_property PACKAGE_PIN AN16 [get_ports phy2_mdc]
set_property IOSTANDARD LVCMOS18 [get_ports phy2_mdc]

set_property PACKAGE_PIN AN17 [get_ports phy2_mdio]
set_property IOSTANDARD LVCMOS18 [get_ports phy2_mdio]

set_property PACKAGE_PIN AG23 [get_ports phy2_reset]
set_property IOSTANDARD LVCMOS18 [get_ports phy2_reset]

# TX (FPGA -> PHY)
set_property PACKAGE_PIN AP22 [get_ports rgmii_tx_clk]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_tx_clk]

set_property PACKAGE_PIN AM23 [get_ports rgmii_txd[0]]
set_property PACKAGE_PIN AN23 [get_ports rgmii_txd[1]]
set_property PACKAGE_PIN AH23 [get_ports rgmii_txd[2]]
set_property PACKAGE_PIN AP21 [get_ports rgmii_txd[3]]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_txd[*]]

set_property PACKAGE_PIN AF23 [get_ports rgmii_tx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_tx_ctl]

# RX (PHY -> FPGA)
set_property PACKAGE_PIN AH22 [get_ports rgmii_rx_clk]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_rx_clk]

set_property PACKAGE_PIN AM19 [get_ports rgmii_rxd[0]]
set_property PACKAGE_PIN AE24 [get_ports rgmii_rxd[1]]
set_property PACKAGE_PIN AE23 [get_ports rgmii_rxd[2]]
set_property PACKAGE_PIN AA19 [get_ports rgmii_rxd[3]]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_rxd[*]]

set_property PACKAGE_PIN AN19 [get_ports rgmii_rx_ctl]
set_property IOSTANDARD LVCMOS18 [get_ports rgmii_rx_ctl]