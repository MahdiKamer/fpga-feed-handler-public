# Using FPGA Constraints in fpga-feed-handler

This project provides a minimal set of FPGA constraint files for evaluation boards.
They are split into **pin mapping**, **basic timing**, and **background documentation**.

---

## Files

- `constraints/board_pinout.xdc`
  Maps FPGA pins to RGMII signals, reset, LEDs, and clocks.
  Derived from **public vendor schematics**.

- `constraints/timing_basic.xdc`
  Provides generic RGMII input/output delay constraints using values from the **JL2121 datasheet**.
  Covers clock setup, data alignment, and I/O standards.

- `docs/rgmii_timing_requirements.md`
  Background document explaining how RGMII timing constraints are derived.
  Includes formulas, datasheet parameters, and references.
  Does **not** include board-specific trace delays (refer to vendor docs if required).

---

## How to Use

1. Add both constraint files to your Vivado project:
   ```tcl
   read_xdc constraints/board_pinout.xdc
   read_xdc constraints/timing_basic.xdc
   ```
2. Ensure your top-level ports match the names used in the XDC files
(e.g. ```rgmii_txd[3:0]```, ```rgmii_rxd[3:0]```, ```rgmii_tx_ctl```, ```rgmii_rx_ctl```, ```rgmii_tx_clk```, ```rgmii_rx_clk```).
3. Adjust clock period in ```timing_basis.xdc``` if your reference clock is different
(default: 125 MHz for gigabit RGMII).

> **Note:**
>- Trace-delay-based skew numbers are excluded from this repo to respect vendor IP.
>- If you need precise per-board skew constraints, refer to vendor's official documentation or measure your own board.