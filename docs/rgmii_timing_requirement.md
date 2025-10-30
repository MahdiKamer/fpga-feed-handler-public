# RGMII Timing Requirement and Constraint Derivation

This document consolidates the derivation of timing constraints for RGMII interfaces based on measured net lengths (not included in this repo), PHY timing parameters, and propagation delay constants.

---

### **Board Propagation Delay:**
  A propagation constant of **173 ps per inch** was used, following the design guideline provided by vendor for their development board PCB stack-up.
  This value is applied to convert trace lengths into board delays for both TX and RX data lanes.
> **Note:** Board-specific trace delays are not included in this repository.
> Please consult vendor documentation or measure your board if precise skew values are required.

### **Computed PCB traces and FPGA silicon pad-to-pin skews**

  1. pcb_skew = pcb_data[^11] - pcb_clk[^12]

  [^11]: ```pcb_data``` = one-way board trace + connector + series-resistor effective delay for the data net between driver pin and receiver pin (ns). (Include series resistor RC delay here.)

  [^12]:```pcb_clk``` = one-way board trace + connector + series-resistor effective delay for the clock net between driver pin and receiver pin (ns).

  2. pad_delta[^13] = pad_data - pad_clk

  [^13]:```pad_delta (ns).``` Only include this difference if FPGA internal pad-to-IOB delays differ for the data and clock pins; otherwise leave pad_delta = 0. (Vivado models absolute pad-to-IOB internally, you only add the delta.)

  - ("1 & 2") $\implies$ **total_skew** = pcb_skew + pad_delta

  - These were calculated per lane in a spread sheet.

### **PHY Timing Parameters (JL2121):**
  Extracted directly from the JL2121 datasheet (page 16 and 17)[^1].

  [^1]:[RGMII specification](https://www.renesas.com/en/document/mah/pcb-design-guideline-rgmii-interface?srsltid=AfmBOorRBZV9Gkgd77oddb_p0d__6S5dbWGbV0ZINpNGhUn_MY0cAvQg) can also be used.
  - Clock-to-data skew (RX path):
    - **tskewR_min = 1.0 ns**
    - **tskewR_max = 2.6 ns**
    - FPGA RX port direction $::$ input $\implies$ Use these in Tcl XDC directive : "*set_input_delay* .."
  - TX path requirements (PHY receive timing):
    - **tsetupT_max = 2.0 ns**
    - **tholdT_min = 1.2 ns**
    - FPGA TX port direction $::$ output $\implies$ Use these in Tcl XDC directive : "*set_output_delay* .."

### **Formulas to compute final set\_\*\_delay values**[^2]
[^2]: Vivado constraints guidance (UG903) and Vivado methodology guide (UG949)

* **RX (PHY $\rightarrow$ FPGA)** - reference clock: rgmii_rx_clk

  These input_* numbers are what you supply to set_input_delay. They are external delays relative to the clock at the interface pin of FPGA[^10].
  [^10]:This defines the valid data eye as observed at the FPGA input.
  * input_min = tskewR_min + total_skew + RXDLY[^9]
   [^9]: Internal PHY RX clock delay. if the PHY JL2121 - pin 25
(RXD0/RXDLY) is;  $1 \implies$ (RXDLY = 2ns) or $0 \implies$ (RXDLY = 0).




  ```tcl
  set_input_delay -clock rgmii_rx_clk -min <input_min> [get_ports <rx_data_pin>]
  ```
  * input_max = tskewR_max + total_skew + RXDLY[^9]
  ```tcl
  set_input_delay -clock  rgmii_rx_clk max <input_max> [get_ports <rx_data_pin>]
  ```

* **TX (FPGA $\rightarrow$  PHY)** - reference clock: rgmii_tx_clk

  For outputs we compute how late/early the FPGA may launch signals so the PHY meets its input tholdT/tsetupT requirement:
  * output_min[^3] = - (tholdT_min + total_skew)
  [^3]: ```output_min``` is negative (Vivado expects a negative number for min when the receiver requires hold-time after its clock). It states how long the FPGA must hold the data after the launching clock edge. We use tholdT_min (PHY hold) and add total_skew since if data is delayed relative to clock this increases the hold requirement (the data will be seen even later).
  ```tcl
  set_output_delay -clock rgmii_tx_clk -min <output_min> [get_ports <tx_data_pin>]
  ```
  * output_max[^4] = tsetupT_max - total_skew
  [^4]: Regarding ```output_max```, the FPGA must launch data early enough to satisfy the PHY's setup. If total_skew is positive (data slower), the FPGA has to launch earlier, reducing output_max.
  ```tcl
  set_output_delay -clock rgmii_tx_clk -max <output_max> [get_ports <tx_data_pin>]
  ```



