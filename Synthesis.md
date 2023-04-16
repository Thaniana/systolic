# Install yosys

Either install yosys from the repository (Ubuntu/WSL/Debian):
```
sudo apt install yosys
```
Or on Apple/Mac
```
brew install yosys
```

Or install it from source (https://github.com/YosysHQ/yosys)

# Proto-ASICS with 004 repository (for the synth)

```
git clone git@github.mit.edu:6004/minispec.git 
```

Once your Lab2 is finished, you can synthesize your design:

```
# First path points to where you cloned the minispec folder
./minispec/synth/synth --synthdir build FoldedMM.bsv mkMatrixMultiplyFolded
```

# Open FPGAs (ecp5/ice40) 

You can also use yosys to do synthesis for a few FPGA (ice40 and ecp5 boards, among others).
Typically:

```
yosys #start yosys
# And then within yosys:
read_verilog build/mkMatrixMultiplyFolded.v
read_verilog verilog/*.v
synth_ecp5 -top mkMatrixMultiplyFolded #This will give you some area/utilization report
sta #This will give you some crude static timing analysis report
```
