import Vector::*;


typedef struct { Bit#(32) a; Bit#(32) b; Bit#(32) c} PE deriving (Eq, FShow, Bits, Bounded);

//TODO: use a typedef for all the 4s
function Vector#(4,Vector#(4,Reg#(PE))) peWork(Vector#(4,Vector#(4,Reg#(PE))) in);
    //this should combinationally go through all the PE locations and then update their c value in them
    Vector#(4,Vector#(4,Reg#(PE))) out = in; 
    for (Integer i = 0; i <4 ; i = i+1) begin 
        for (Integer j = 0; j<4) begin
            out[i][j].c = in[i][j].c + in[i][j].a*in[i][j].b;
        end
    end 
    return out;
endfunction


function Vector#(4,Vector#(4,Reg#(32))) peToResult(Vector#(4,Vector#(4,Reg#(PE))) in);
    //this should combinationally go through all the PE locations and get us the result out
    Vector#(4,Vector#(4,Reg#(32))) out;  //prolly will have to assign to 0s though
    for (Integer i = 0; i <4 ; i = i+1) begin 
        for (Integer j = 0; j<4) begin
            out[i][j] = in[i][j].c;
        end
    end 
    return out;
endfunction



interface sysMM;
    method Action load_row_a(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action load_row_b(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action start();
    method ActionValue#(Vector#(16, Bit#(32))) resp_row_c();
endinterface

(* synthesize *)
module mkSystolic(sysMM);

    Vector#(4,Vector#(4,Reg#(Bit#(32)))) c; //this is the result matrix ie it is 4x4

    /*
    Ok so there is two parts to thie:
    1. making each PE - this does the accumulation as well as takes in the next value 
    2. finding a way to pass on a correct new value to the PEs each time


    maybe have a 2D array with each position holding a strruct which holds the rrunning result, the values a and b  
    then we slowly have a data passing methodology which somehow passes the values into the ech part of the struct
    combinationally in one cycle read through all thee PEs and then product of a,b and add to tthe result 
    
    Now that I have both the functions above what i need is a way to create the above stuct for each clock cycle
    and then a way to test it - this is very domain specific - that is has to do with what can be done and how it will be done on bluespec


    Maybe now I will have to go through the hard logic of traversing through the array in the diagonal fashions
    Will be a lot of indexing!!


    The toughest part comes from the fact that the array I am speaking of maay be stored in the bram which leads to a 
    delay as well as some added logic as we have to wait for a response  - 

    - https://leetcode.com/problems/diagonal-traverse/description/
    - the above is from leetcode doing a type of this traversal

    Hopefully i do not have to store the PE in tthe BRAM that would cause even more delay 


    Also I will have to take a look on whether all this can happen on just square matrices or can be extended onwards 


    Questions for Thomas:
    1) How much space do I have - can I just use vectors
    2) How to test stuff? 





    */



endmodule


