import Vector::*;
import FIFO::*;

// 'define m_length 4

typedef Bit#(4) Addr;//this is the max number of rows in the matrix input 

typedef struct { Bit#(32) a; Bit#(32) b} ab deriving (Eq, FShow, Bits, Bounded);

//TODO: use a typedef for all the 4s

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
    Reg#(Bit#(32)) c_value <- mkReg(0);
    
    FIFO#(Bit#(32)) q_a <- mkBypassFIFO; 
    FIFO#(Bit#(32)) q_b <- mkBypassFIFO; 

    Reg#(Bit#(32)) prod_a <- mkReg(0);
    Reg#(Bit#(32)) prod_b <- mkReg(0);

    Reg#(Bit#(2)) prod_ready <- mkReg(0);

    rule prod if (prod_ready == 2);
        c_value <= c_value + prod_a*prod_b;
        prod_ready <= 0;
    endrule

    method Action recieve_a(Bit#(32) a);
        q_a.enq(a);
    endmethod

    method Action recieve_b(Bit#(32) b);
        q_b.enq(b);
    endmethod

    method ActionValue(Bit#(32)) send_a();
        let aa = q_a.first();
        q_a.deq();
        prod_a <= aa;
        prod_ready <= prod_ready + 1;
        return aa;
    endmethod

    method ActionValue(Bit#(32)) send_b();
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



interface sysMM;
    method Action start_conversion(Addr loc_a, Addr loc_b, Addr loc_c);//begins the acc, loc are the start 
    //addresses of the matrix in the memory
    method ActionValue#(Addr) AReq(); //Req sends a specific address location to get the value from
    method Action AResp(Bit#(32) a); //responds with the value stored at that location
    method ActionValue#(Addr) BReq(); //Req sends a specific address location to get the value from
    method Action BResp(Bit#(32) a); //responds with the value stored at that location
    method ActionValue#(Addr, Bit#(32)) CReq(); //sends the final value to be stored at location for c
endinterface


typedef enum {ready, start, fill_scratch_req, fill_scratch_wait, fill_scratch_respA, fill_scratch_respB, ready_sys, run_sys, stop_sys_input, stop_sys} systolicStatus deriving(Bits,Eq);


(* synthesize *)
module mkSystolic(sysMM);

    /*
    This is the parent which will access all the other smaller modules that I am creating
    */
    Reg#(systolicStatus) status <- mkReg(ready);
    Reg#(Addr) start_loca <- mkReg(0);
    Reg#(Addr) start_locb <- mkReg(0);
    Reg#(Addr) start_locc <- mkReg(0);

    FIFO#(Addr) toA <- mkBypassFIFO;
    FIFO#(Bit#(32)) fromA <- mkBypassFIFO;
    FIFO#(Addr) toB <- mkBypassFIFO;
    FIFO#(Bit#(32)) fromB <- mkBypassFIFO;

    Reg#(Bit#(2)) h_fill <- mkReg(0);//param: will change according to the length of the rows and columns 
    Reg#(Bit#(2)) w_fill <- mkReg(0);

    Vector#(4,BRAM1Port#(Addr, Vector#(4, ab))) scratchpad <- mkReplicate(0); //syntax: is this correct

    Vector#(4,Vector#(4,Reg#(PE))) PE_matrix <- mkReplicate(0); //syntax:How to instantiate as PE is a module

    Reg#(Bit#(2)) h_sys <- mkReg(0);//param:
    Reg#(Bit#(2)) w_sys <- mkReg(0);

    Vector#(4,Reg#(Bit#(32))) b_vec <- ReplicateM(0);
    Vector#(4,Reg#(Bit#(32))) a_vec <- ReplicateM(0);
    Reg#(Bit#(4)) index <- mkReg(0);//param:

    Reg#(Bit#(32)) cycles <- mkReg(0);


    rule fill_scratchpad_respond if (status == fill_scratch_respA && status == fill_scratch_respB);

        let a_temp = fromA.first();
        let b_temp = fromB.first();
        fromA.deq();
        fromB.deq();//CHECK: hopefully the req method is called asap 

        ab in = ab(a:a_temp,b:b_temp);//TODO: check if this is correct syntax

        scratchpad[w_fill].portA.request.put(BRAMRequest{write: True,
                        responseOnWrite: False,
                        address: h_fill,
                        datain: in});

        status <= fill_scratch_req;
    endrule

    rule fill_scratchpad_request if (status == fill_scratch_req);

        if (w_fill == 3) begin
            w_fill <= 0;
            if (h_fill == 3) begin
                h_fill <= 0;
                status <= ready_sys;//scratchpad is filled
            end else 
                h_fill <= h_fill + 1;
        end else
            w_fill <= w_fill + 1;

        toA.enq(start_loca + indices_to_location(h,3-w));
        toB.enq(start_locb + indices_to_location(3-w,h));
        status <= fill_scratch_wait;

    endrule


//TODO: this has to be fixed 
//TODO: need multiple rules to access multiple - just add a for loop here
    rule bram_access if (access_brams);
        let temp <- scratchpad.portA.response.get(); //TODO: I need the brams vector to be accessible over here
        a_vec[index] =  temp.a;
        b_vec[index] =  temp.b;
        access_brams <= False;
    endrule


    rule systolic_cycle if (status == ready_sys); 
        let temp_h = h_sys;
        let temp_w = w_sys;
        Bool in_boundary = True;
        index <= h_sys;
        
        //TODO: fix!!
        for (Integer i = 0 ; i < 4 ; i = i + 1) begin
            scratchpad[i].portA.request.put(BRAMRequest{write: False,
                        responseOnWrite: False,
                        address: temp_w,
                        datain: ?}); 
        end 


        //Hopefully this is combinational!
        while (in_boundary) begin 
            scratchpad[temp_h].portA.request.put(BRAMRequest{write: False,
                        responseOnWrite: False,
                        address: temp_w,
                        datain: ?}); 
            //TODO: may  have to make it a vector?? Else will not be combinational
            access_brams <= True;//NOTE: remember all of this is combinational - not sure how this would 
            //TODO: make the circuit alongside the brams which are to be fairr all different so should be fine - rule could be an issue??
            //Follow up to above - will the following rule be combinational as well?
            
            index <= index + 1;
            if (temp_w == 0 || temp_h == 3) //params
                in_boundary = False;
            else begin
                temp_w = temp_w - 1;
                temp_h = temp_h + 1;
            end
        end
        //end of combinational 
        //TODO:fix ends 

        //maybe creat a vector with the temp_w and then just store the temp_h, and index in there - the loop would stay the same but writing the bram would be more consistent

        //this should be the clock cycles 
        if (w_sys == 3) begin
            if (h_sys!= 3) 
                h_sys <= h_sys + 1;
            else begin
                a_vec <= {0,0,0,0};//syntax
                b_vec <= {0,0,0,0};
                sysStatus <= stop_input;
            end
        end else begin
            w_sys <= w_sys + 1;
        end

    endrule

    rule systolic_PE_work if (status == Run || status == stop_input)  
        //TODO: the below needs more cycles that the above and hence we need to make sure that I am not doing the above 
        // when it is not needed!! Some sort of break condition or something is needed 
        if (cycles == 10) //the 10 here comes from 3n - 2 total clock cycles needed for sys array
            sysStatus <= stop;
        else
            cycles <= cycles + 1; //TODO: make sure it does it the correct number of timee - ie the adding to this 
        
        //this does the work for all the PEs
        //Is this combinational? It must be!! 
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

    rule if (sysStatus  == stop);
        for (Integer j = 0 ; i < 4 ; i ++) begin
            for (Integer i = 0 ; j < 4 ; j ++) begin
            c[j][i] <= PE_matrix[j][i].read_c();
            end
        end
        sysStatus <= Ready;
    endrule


    method Action start_conversion(Addr loc_a, Addr loc_b ) if (status == ready);
        start_loca <= loc_a;
        start_locb <= loc_b;
        start_locc <= loc_c;
        status <= start;
    endmethod

    method ActionValue#(Addr) AReq(); //gives address to get request from
		toA.deq();
    	return toA.first();
    endmethod
    method Action AResp(Bit#(32) a) if (status == fill_scratch_wait);//gets tthe vvaluee stored at that address
    	fromA.enq(a);
        status <= fill_scratch_respA;
    endmethod
    method ActionValue#(Addr) BReq();
		toB.deq();
		return toB.first();
    endmethod
    method Action BResp(Bit#(32) a) if (status == fill_scratch_wait);
		fromB.enq(a);
        status <= fill_scratch_respB;
    endmethod

    /*
    Questions:
    1. THe define and then how to paass arround the BRAM stuff
    2. parameterisation - how can you give in a size of a matrix in the test or the function and expect 
        everything to adapt to this value - is there a way to do this? 
    */



endmodule





