# Third-Party Components

This project makes use of the following external open-source component:

- **verilog-ethernet**  
  Repository: [https://github.com/alexforencich/verilog-ethernet](https://github.com/alexforencich/verilog-ethernet)  
  Author: Alex Forencich  
  License: MIT  

The component is not included directly in this repository.  
Instead, it should be fetched as a git submodule:

```bash
git submodule add https://github.com/alexforencich/verilog-ethernet deps/verilog-ethernet
git submodule update --init --recursive
```
For license details, please refer to the verilog-ethernet repository.