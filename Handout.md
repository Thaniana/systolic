# Matrix multiply specification

We want to build a module that can compute the matrix multiplication (c = a * b).
For now, we consider that the matrix elements are 32-bits integers. 

We propose the following interface for a simple, folded matrix multiply unit.

```
interface MM;
    method Action load_row_a(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action load_row_b(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action start();
    method ActionValue#(Vector#(16, Bit#(32))) resp_row_c();
endinterface
```

For this first sequential machine, we suggest to use 3 different BRAMs to hold the two input matrix and the output matrix, your first design should use a single multiplier. The following diagram summarize the blueprint of the module:
<img src="Classfig/Classfig%20-%20page%201.png" alt="Matrix multiply module overview" width=600>

The `load` methods allows one to write the input matrices in their corresponding BRAM, one row at a time. 
The `start` instruct the machine to start the matrix multiplication `c=a*b`, as long as the machine is producing the resulting C matrix, the guard of both the `load_row_*` and the `resp_row_c` methods should be false whenever the machine is performing the computation.


The method `resp_row_c` is expected to produce the rows of the result matrix c in increasing order (from 0 to 15).

In the file `FoldedMM.bsv`, implement the module `mkMatrixMultiplyFolded`. In this version, you can use the naive "*" operator for the multiplication on scalar.

To test your code:

```
make
./TbMM
```

There are 4 tests performed in sequence:
- test0: Multiply the identity matrix with itself
- test1: Again multiply the identity matrix with itself
- test2: Multiply two random matrices
- test3: Multiply two other random matrices

## BRAM usage
Initializing a BRAM module:
```
BRAM_Configure cfg = defaultValue;
BRAM1Port#(Bit#(addrSize), Bit#(dataSize)) a <- mkBRAM1Server(cfg);
```

To send a request:
```
a.portA.request.put(BRAMRequest{write: True, // False for read
                         responseOnWrite: False,
                         address: _,
                         datain: _});
```

To read a response:
```
let resp <- a.portA.response.get();
```
