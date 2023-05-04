import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import BRAM::*;

// 'define m_length 4

//TODO: Take a re look over the code and ask any questions on Piazza 
//TODO: make the simplae test case 

typedef Bit#(4) Addr;//this is the max number of rows in the matrix input 

typedef struct { Bit#(32) a; Bit#(32) b;} AB deriving (Eq, FShow, Bits, Bounded);

typedef struct {Bool access; Bit#(2) index;} Bram_access deriving (Eq, FShow, Bits, Bounded);

typedef struct {Addr location; Bit#(32) value;} Response_c deriving (Eq, FShow, Bits, Bounded);

//TODO: use a typedef for all the 4s

//the max index of result here is 4x4
//add the start location to this as well
function Bit#(4) indices_to_location(Bit#(2) h, Bit#(2) w);
    //this should combinationally go through all the PE locations and get us the result out
    Bit#(4) n_h = extend(h);
    Bit#(4) n_w = extend(w);
    return n_h<<2 + n_w; //Essentially h*4 + w
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
    //need to make sure that send_b happens after send_a as after send_b I calculate c
    Reg#(Bit#(32)) c_value <- mkReg(0);
    
    FIFO#(Bit#(32)) q_a <- mkFIFO; //check: what would be differeent with Bypass FIFO - also this is a erg right
    FIFO#(Bit#(32)) q_b <- mkFIFO; 

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

    method ActionValue#(Bit#(32)) send_a();
        let aa = q_a.first();
        q_a.deq();
        prod_a <= aa;
        // prod_ready <= prod_ready + 1;
        return aa;
    endmethod

    method ActionValue#(Bit#(32)) send_b();
        let bb = q_b.first();
        q_b.deq();
        prod_b <= bb;
        // prod_ready <= prod_ready + 1;
        prod_ready <= 2;
        return bb;
    endmethod
    

    method ActionValue#(Bit#(32)) read_c();
        //this is to essentially read the value stored in here that is all
        return c_value;
    endmethod


endmodule


typedef enum {Ready, Start, Fill_scratch_req, Fill_scratch_wait, Fill_scratch_respA, Fill_scratch_respB, Run_sys, Run_sys_bram_read, Stop_sys_input, Stop_sys} SystolicStatus deriving(Bits,Eq);
interface MM_sys;
    method Action start_conversion(Addr loc_a, Addr loc_b, Addr loc_c);//begins the acc, loc are the start 
    //addresses of the matrix in the memory
    method ActionValue#(Addr) aReq(); //Req sends a specific address location to get the value from
    method Action aResp(Bit#(32) a); //responds with the value stored at that location
    method ActionValue#(Addr) bReq(); //Req sends a specific address location to get the value from
    method Action bResp(Bit#(32) a); //responds with the value stored at that location
    method ActionValue#(Response_c) cReq(); //sends the final value to be stored at location for c
endinterface

(* synthesize *)
module mkSystolic(MM_sys);

    /*
    This is the parent which will access all the other smaller modules that I am creating
    */
    Reg#(SystolicStatus) status <- mkReg(Ready);
    Reg#(Addr) start_loca <- mkReg(0);
    Reg#(Addr) start_locb <- mkReg(0);
    Reg#(Addr) start_locc <- mkReg(0);

    FIFO#(Addr) toA <- mkBypassFIFO;
    FIFO#(Bit#(32)) fromA <- mkBypassFIFO;
    FIFO#(Addr) toB <- mkBypassFIFO;
    FIFO#(Bit#(32)) fromB <- mkBypassFIFO;

    Reg#(Bit#(2)) h_fill <- mkReg(0);//param: will change according to the length of the rows and columns 
    Reg#(Bit#(2)) w_fill <- mkReg(0);

    Vector#(4,Vector#(4,PE)) pe_matrix <- replicateM(replicateM(mkPE())); //syntax:check that REg is not needed arround PE

    Vector#(4,BRAM1Port#(Bit#(2),AB)) scratchpad <- replicateM(mkBRAM1Server(defaultValue)); //syntax: is this correct
    //param

    
    Reg#(Bit#(2)) h_sys <- mkReg(0);//param:
    Reg#(Bit#(2)) w_sys <- mkReg(0);

    Reg#(Bit#(2)) h_creq <- mkReg(0);//param:
    Reg#(Bit#(2)) w_creq <- mkReg(0);


    Vector#(4,Reg#(Bit#(32))) b_vec <- replicateM(mkReg(0));
    Vector#(4,Reg#(Bit#(32))) a_vec <- replicateM(mkReg(0));

    Vector#(4,Reg#(Bit#(32))) empty_vec <- replicateM(mkReg(0));

    // Reg#(Bit#(4)) index <- mkReg(0);//param:

    Vector#(4,Reg#(Bram_access)) bram_read <- replicateM(mkReg(Bram_access{access:False,index:0})); //make sure it is insttantiate as False

    Reg#(Bit#(32)) cycles <- mkReg(0);


    rule fill_scratchpad_respond if (status == Fill_scratch_respA && status == Fill_scratch_respB);

        let a_temp = fromA.first();
        let b_temp = fromB.first();
        fromA.deq();
        fromB.deq();//CHECK: hopefully the req method is called asap 

        AB in = AB{a:a_temp,b:b_temp};//TODO: check if this is correct syntax

        scratchpad[w_fill].portA.request.put(BRAMRequest{write: True,
                        responseOnWrite: False,
                        address: h_fill,
                        datain: in});

        status <= Fill_scratch_req;
    endrule

    rule fill_scratchpad_request if (status == Fill_scratch_req);

        if (w_fill == 3) begin
            if (h_fill == 3) begin
                h_fill <= 0;
                w_fill <= 0;
                status <= Run_sys;//scratchpad is filled
            end else begin
                h_fill <= h_fill + 1;
                w_fill <= 0;
                toA.enq(start_loca + indices_to_location(h_fill,3-w_fill));
                toB.enq(start_locb + indices_to_location(3-w_fill,h_fill));
                status <= Fill_scratch_wait;
            end
        end else begin
            w_fill <= w_fill + 1;
            toA.enq(start_loca + indices_to_location(h_fill,3-w_fill));
            toB.enq(start_locb + indices_to_location(3-w_fill,h_fill));
            status <= Fill_scratch_wait;
        end


    endrule


//TODO: this has to be fixed 
//TODO: need multiple rules to access multiple - just add a for loop here
    
    rule write_vectors if (status == Run_sys_bram_read);
        
        for (Integer bank = 0 ; bank < 4 ; bank = bank + 1) begin //param
            if (bram_read[bank].access) begin
                let temp <- scratchpad[bank].portA.response.get(); //TODO: I need the brams vector to be accessible over here
                a_vec[bram_read[bank].index] <=  temp.a;
                b_vec[bram_read[bank].index] <=  temp.b;
                bram_read[bank].access <= False;
            end
            //TODO: issue with the a_vec and b_vec conflictingg - but why? They are independant registers in there?
        end

        //this should be the clock cycles
        //Note not a typical increment - ffollows top then right boundary  
        if (w_sys == 3) begin
            if (h_sys!= 3) begin
                h_sys <= h_sys + 1;
                status <= Run_sys;
            end


            else begin //h_sys is 3
                status <= Stop_sys_input;
            end


        end else begin
            w_sys <= w_sys + 1;
            status <= Run_sys;
        end

    endrule


    rule systolic_cycle if (status == Run_sys); 
        Bit#(2) temp_h = h_sys;//param:
        Bit#(2) temp_w = w_sys;
        Bool in_boundary = True;
        Bit#(2) ind = h_sys;
        
        for (Integer i = 0 ; i < 4 ; i = i + 1) begin
        //Hopefully this is combinational!
            if (in_boundary) begin 
                scratchpad[temp_w].portA.request.put(BRAMRequest{write: False,
                            responseOnWrite: False,
                            address: temp_h,
                            datain: ?}); 

                bram_read[temp_w] <= Bram_access{access:True, index:ind};
                ind = ind + 1;

                //ALl this is nott combinational - or is it? i think it should work - try writing thiis 4 times - it should be fine
                if (temp_w == 0 || temp_h == 3) //params
                    in_boundary = False;
                else begin
                    temp_w = temp_w - 1;
                    temp_h = temp_h + 1;
                end
            end 
        //end of combinational 
        end
        status <= Run_sys_bram_read;

    endrule

    rule systolic_PE_work if (status == Run_sys);
        //this does the work for all the PEs
        //Is this combinational? It must be!! 
        for (Integer j = 0 ; j < 4 ; j = j + 1) begin
            for (Integer i = 0 ; i < 4 ; i = i + 1) begin
                //Recieve the values from the previous Q or from the prervious PE
                //TODO: fix the error here as the commands are actions and acttion values 
                if (i == 0)
                    pe_matrix[j][i].recieve_a(a_vec[j]);
                else begin
                    let a_s <- pe_matrix[j][i-1].send_a();
                    pe_matrix[j][i].recieve_a(a_s);
                end
                
                if (j == 0)
                    pe_matrix[j][i].recieve_b(b_vec[i]);
                else begin
                    let b_s <- pe_matrix[j-1][i].send_b();
                    pe_matrix[j][i].recieve_b(b_s);
                end 
                
                
                //Do product and Dump the values if the last PE
                if (i == 3)
                    let a_ss <- pe_matrix[j][i].send_a(); 
                if (j == 3) 
                    let b_ss <- pe_matrix[j][i].send_b();
            end
        end

        if (cycles == 10) //the 10 here comes from 3n - 2 total clock cycles needed for sys array
            status <= Stop_sys;
        else
            cycles <= cycles + 1; //TODO: make sure it does it the correct number of timee - ie the adding to this 
        
    endrule

    rule systolic_PE_work_two if (status == Stop_sys_input);
        //this does the work for all the PEs
        //Is this combinational? It must be!! 
        for (Integer j = 0 ; j < 4 ; j = j + 1) begin
            for (Integer i = 0 ; i < 4 ; i = i + 1) begin
                //Recieve the values from the previous Q or from the prervious PE
                //TODO: fix the error here as the commands are actions and acttion values 
                if (i != 0) begin
                    let a_s <- pe_matrix[j][i-1].send_a();
                    pe_matrix[j][i].recieve_a(a_s);
                end

                //no worrk on the getting values from aa and b vecs fronnt 
                
                if (j != 0) begin
                    let b_s <- pe_matrix[j-1][i].send_b();
                    pe_matrix[j][i].recieve_b(b_s);
                end 
                
                
                //Do product and Dump the values if the last PE
                if (i == 3)
                    let a_ss <- pe_matrix[j][i].send_a(); 
                if (j == 3) 
                    let b_ss <- pe_matrix[j][i].send_b();
            end
        end

        if (cycles == 10) //the 10 here comes from 3n - 2 total clock cycles needed for sys array
            status <= Stop_sys;
        else
            cycles <= cycles + 1; //TODO: make sure it does it the correct number of timee - ie the adding to this 
        
    endrule


    method Action start_conversion(Addr loc_a, Addr loc_b, Addr loc_c ) if (status == Ready);
        start_loca <= loc_a;
        start_locb <= loc_b;
        start_locc <= loc_c;
        status <= Start;
    endmethod

    method ActionValue#(Addr) aReq(); //gives address to get request from
		toA.deq();
    	return toA.first();
    endmethod
    method Action aResp(Bit#(32) a) if (status == Fill_scratch_wait);//gets tthe vvaluee stored at that address
    	fromA.enq(a);
        status <= Fill_scratch_respA;
    endmethod
    method ActionValue#(Addr) bReq();
		toB.deq();
		return toB.first();
    endmethod
    method Action bResp(Bit#(32) a) if (status == Fill_scratch_wait);
		fromB.enq(a);
        status <= Fill_scratch_respB;
    endmethod

    method ActionValue#(Response_c) cReq() if (status == Stop_sys);
        Response_c c_resp;
        if (w_creq == 3) begin //param:
            if (h_creq == 3) begin
                status <= Ready;
                h_creq <= 0;
                w_creq <= 0;
            end
            else begin
                w_creq <= 0;
                h_creq <= h_creq + 1;
            end
        end else begin
            w_creq <= w_creq + 1;
        end
        c_resp.location = (start_locc + indices_to_location(h_creq,w_creq));
        c_resp.value <- pe_matrix[h_creq][w_creq].read_c();
        return c_resp;

    endmethod




endmodule





