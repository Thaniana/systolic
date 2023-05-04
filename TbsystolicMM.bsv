/*
This file creates the test bench for the systolic array method

The goal is to store a matrix in a bram in the Tb and then during the test itself call the systolic array method and see 
it work

The question is how to parametize the function!

*/

//toppipeline.bsv - is th file to look into for how to gt 

//vmh file starts with @0 and thn each line is th lin with th bit 32 value to hold and the n no need to end 
//add tag Bin instead of tag Hex in the top pipeline bsv


//Lab2 test.hex is an example 

//also can create it via python - print - "{0:0{1}b}".format(v,size)
import BRAM::*;
import systolicMM::*;



module mkSystolicTest(Empty);
    BRAM_Configure cfgA = defaultValue();
    cfgA.loadFormat = tagged Hex "a.vmh";
    BRAM2PortBE#(Bit#(4), Bit#(32), 4) bramA <- mkBRAM2ServerBE(cfgA);//param
    //What is this 4 over here?

    BRAM_Configure cfgB = defaultValue();
    cfgB.loadFormat = tagged Hex "b.vmh";
    BRAM2PortBE#(Bit#(4), Bit#(32), 4) bramB <- mkBRAM2ServerBE(cfgB);//param

    MM_sys mma <- mkSystolic();

    $display("Test Multiplication");

endmodule

