import Vector::*;
import FIFO::*;

// 'define m_length 4

typedef Bit#(4) Addr;//this is the max number of rows in the matrix input 


//TODO: is this possible?


typedef struct { Bit#(32) a; Bit#(32) b} a_and_b deriving (Eq, FShow, Bits, Bounded);

//TODO: use a typedef for all the 4s


//TODO: noe this will not be a PE struct but the PE here is now a module so I will have to read and not just access
function Vector#(4,Vector#(4,Reg#(32))) peToResult(Vector#(4,Vector#(4,Reg#(PE))) in);
    //this should combinationally go through all the PE locations and get us the result out
    Vector#(4,Vector#(4,Reg#(32))) out;  //TODO: prolly will have to assign to 0s though
    for (Integer i = 0; i <4 ; i = i+1) begin 
        for (Integer j = 0; j<4) begin
            out[i][j] = in[i][j].c;
        end
    end 
    return out;
endfunction

//the max index of result here is 4x4
//add the start location to this as well
function Bit#(4) indices_to_location(Bit#(2) h, Bit#(2) w);
    //this should combinationally go through all the PE locations and get us the result out
    return h<<2 + w; //Essentially h*4 + w
endfunction



/*
No locks etc needed as all the rules are Action calls and there is a central Q in the middle of each PE
*/
interface PE;
    method Action recieve_a(Bit#(32) a); 
    method Action recieve_b(Bit#(32) b); 
    method ActionValue#(Bit#(32)) send_a();
    method ActionValue#(Bit#(32)) send_b();
    method ActionValue#(Bit#(32)) read_c();
endinterface

module mkPE(PE);
    Reg#(Bit#(32)) c_value <- mkReg(0); //this is the value stored in here that is the running sum every time - TODO: instantiated to 0 when
    
    FIFO#(Bit#(32)) q_a <- mkBypassFIFO; //doing independantly  - could do a and b together too
    FIFO#(Bit#(32)) q_b <- mkBypassFIFO; //doing independantly - TODO: hopefully the sie here is not 1 of thee FIFO

    Reg#(Bit#(32)) prod_a <- mkReg(0);
    Reg#(Bit#(32)) prod_b <- mkReg(0);

    Reg#(Bit#(2)) prod_ready <- mkReg(0);


    method Action recieve_a(Bit#(32) a);
        //Note the a and b here is togetheer - may havee to changee the logic here depending on thee outer logic

        //reads the values from a previous queue from the outer queue and then adds it to the inner queue
        q_a.enq(a);
    endmethod

    method Action recieve_b(Bit#(32) b);
        //Note the a and b here is togetheer - may havee to changee the logic here depending on thee outer logic

        //reads the values from a previous queue from the outer queue and then adds it to the inner queue
        q_a.enq(b);
    endmethod

    rule prod if (prod_ready == 2);
        c_value <= c_value + prod_a*prod_b;
        prod_ready <= 0;
    endrule

    method ActionValue(Bit#(32)) send_a();
        //maybe make the above things, ie holding a and b into a strruct of the two values 
        //rreads the value frrom thee queue and then returns it to the 
        
        let aa = q_a.first();
        q_a.deq();
        prod_a <= aa;
        prod_ready <= prod_ready + 1;
        return aa;
    endmethod

    method ActionValue(Bit#(32)) send_b();
        //maybe make the above things, ie holding a and b into a strruct of the two values 
        //rreads the value frrom thee queue and then returns it to the 
        
        let bb = q_b.first();
        q_b.deq();
        prod_b <= bb;
        prod_ready <= prod_ready + 1;
        return bb;
    endmethod
    

    method ActionValue#(Bit#(32)) read_c();
        //this is to essentially read the value stored in here that is all
        return c_value;
    endmethod


endmodule


typedef enum {Ready,Bram_read, Running} convertStatus deriving(Bits,Eq);


interface ab;
    method Action start_conversion(Addr loc_a, Addr loc_b );//this assumes that there is a Bram outside that has both a and b stored in it - it will have to be filled else where
    //ok what about c - should i create the vector of brams here or should I create it outside and just access it here?
    //TODO: look at the comment in the line above
endinterface


module convertab(ab);
    //this module essentially converts the square matrix into a longer rectagularr matrix that can do the reading for us
    
    //look at implementation in python in the MatTest file - creating a vector of a number of brams that stores both a and b

    // look at notes for what exactly is being done


    /*
    This function actually would pick up a and b from the L1 cache orr the main memory - still works given the addresses

    The only issue is that a and b you should be able to get in the same cycle!! If not there will be an added complexity!
    */

    Reg#(Addr) start_loca <- mkReg(0);
    Reg#(Addr) start_locb <- mkReg(0);

    Reg#(convertStatus) status <- mkReg(Ready);

    Vector#(4,BRAM1Port#(Addr, Vector#(4, Bit#(32)))) brams <- mk___; //TODO: fix this 
    //TODO take a look at thee addr value and what it is meant to be 
    //how a brram is instantiated
    // BRAM1Port#(Addr, Vector#(16, Bit#(32))) a <- mkBRAM1Server(defaultValue);

    //Try to make a and b different brams so that they can be accessed parallely - reduces one cycle off work!!

    Reg#(Bit#(2)) h <- mkReg(0);//TODO : will change according to the length of the rows and columns 
    Reg#(Bit#(2)) w <- mkReg(0);


    rule brams_respond if (status == Bram_read);

        let a_temp <- a.portA.response.get();
        let b_temp <- a.portA.response.get();

        a_and_b in = a_and_b(a:a_temp,b:b_temp);//TODO: check if this is correct syntax

        //TODO: would this work since the bram respond and write is in the same rule - if not make another rule for writing - EASY!
        brams[w].portA.request.put(BRAMRequest{write: True,
                        responseOnWrite: False,
                        address: h,
                        datain: in});

        status <= Running;

    endrule
    

    //TODO: add a gaurd - make an enum - makes life much easier

    rule traverse if (status == Running);
        if (w == 3) begin
            if (h == 3) begin
                h <= 0;
                status <= Ready;
            end else 
                h <= h + 1;
            w <= 0;
        end else
            w <= w + 1;

        a.portA.request.put(BRAMRequest{write: False,
                        responseOnWrite: False,
                        address: (start_loca+indices_to_location(h,3-w)),
                        datain: ?}); 
        b.portA.request.put(BRAMRequest{write: False,
                        responseOnWrite: False,
                        address: (start_locb + indices_to_location(w,3-h)),
                        datain: ?}); 
        status <= Bram_read;

    endrule

    method Action start_conversion(Addr loc_a, Addr loc_b ) if (status == Ready);
        start_loca <= loc_a;
        start_locb <= loc_b;
        status <= Running;
    endmethod


endmodule




interface sysMM;
    method Action load_row_a(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action load_row_b(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action start();
    method ActionValue#(Vector#(16, Bit#(32))) resp_row_c();
endinterface

(* synthesize *)
module mkSystolic(sysMM);

    /*
    THis is the parent which will access all the other smaller modules that I am creating
    */

    Vector#(4,Vector#(4,Reg#(Bit#(32)))) c; //TODO
    Vector#(4,Vector#(4,Reg#(PE))) PE_matrix <- mkModule____; //TODO 

    FIFO#(Vector#(4,Reg#(Bit#(32)))) b_q <- mkBypassFIFO;
    FIFO#(Vector#(4,Reg#(Bit#(32)))) a_q <- mkBypassFIFO;

    Reg#(Bit#(2)) h <- mkReg(0);
    Reg#(Bit#(2)) w <- mkReg(0);


    rule bram_access; //TODO: some if has to be here

    endrule


    rule doTask; //TODO: when will this task run till - there has to be a number of clocks or a stopping time 


        //Logic to populate the large Queues - hopefully it enqueues after a clock cycle and not in the same cycle!
        let temp_h = h;
        let temp_w = w;
        Vector#(4,Bit#(32)) temp_b_vec <- ReplicateM(0);
        Vector#(4,Bit#(32)) temp_a_vec <- ReplicateM(0);
        Bool in_boundary = True;
        let index = h;
        
        //Hopefully this is combinational!
        while (in_boundary) begin
            //TODO : requires an extra rule for this!! 
            temp_a_vec[index] =  //Get value from bram - the position being accessed will be Bram_vec[temp_w] - temp_h
            temp_b_vec[index] =  //Get value from bram  - the read is just once as both the a and b is in the same place!
            //TODO: somewhere I need to add the temp_vecs to the queue itself - this should happen once all the things have been added though!!
            // Do I even need that queue I could just use this vector aas it does thee job as well - fill it up and then use it when needed
            index = index + 1;
            if (temp_w == 0 || temp_h == 3) //TODO: find all 3s and 2s and 4s that are hardcoded 
                in_boundary = False;
            else begin
                temp_w = temp_w - 1;
                temp_h = temp_h + 1;
            end
        end
        //end of combinational 

        if (w == 3) begin
            if (h!= 3) 
                h <= h + 1;
        end else begin
            w <= w + 1;
        end

        //this does the work for all the PEs
        let b_vec = b_q.first();
        let a_vec = a_q.first();//TODO - the first run should be empty! - but what is the end condition for this rule
        a_q.deq();
        b_q.deq();
        //Is this combinational? It must be 
        for (Integer j = 0 ; i < 4 ; i ++) begin
            for (Integer i = 0 ; j < 4 ; j ++) begin
                //Recieve the values from the previous Q or from the prervious PE
                if (j == 0)
                    PE_matrix[j][i].recieve_b(b_vec[i]);
                else
                    PE_matrix[j][i].recieve_b(PE_matrix[j-1][i].send_b());
                if (i == 0)
                    PE_matrix[j][i].recieve_a(a_vec[j]);
                else
                    PE_matrix[j][i].recieve_a(PE_matrix[j][i-1].send_a());
                
                //Do product and Dump the values if the last PE
                if (i == 3)
                    PE_matrix[j][i].send_a()
                if (j == 3)
                    PE_matrix[j][i].send_b()

            end
        end

    endrule




    /*
    Questions:
    1. THe define and then how to paass arround the BRAM stuff
    2. parameterisation - how can you give in a size of a matrix in the test or the function and expect 
        everything to adapt to this value - is there a way to do this? 






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

    Also I need to figure out when to end this 


    Questions for Thomas:
    1) How much space do I have - can I just use vectors
    2) How to test stuff? 


    Maybe thee best way to do this is to indeed have the stuff be saved in the BRAM - cause remember that there
    will be a cache as well!! So maybe we can shift from the BRAM access to thhe cache accessing later on


    NOTE IMPORTANT - also exploit the  fact that you can move the value from cell in the PE to a new corresponding cell 
                   - this can be done in the same combinational circuit no? Or even if it is done sequentially can it be in
                   - one cycle only? Yes hopefully as each PE should be able to work simulttaneously!!

                   -the complicated part is filling in the left most column and rows


    */



endmodule


