# Constraints

This folder contains only constraints derived from:
- Public vendor schematics (pin mapping, I/O standards)
- JL2121 Ethernet PHY datasheet (RGMII timing)

Files such as vendor CAD trace lengths and derived skew/delay constraints 
are excluded to respect vendor intellectual property. If you require 
precise trace delays, please refer to official vendor documentation 
or contact their support.
>Additional background on derivation is in [constraints_usage.md](../docs/constraints_usage.md) and [rgmii_timing_requirement](../docs/rgmii_timing_requirement.md)
