import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import BRAM::*;

//DEBUGING STEPS - look at the indexing and see if the righht value is being passes through - used the numbered version for this 
//would make the testing easier this way!
//The scratchpad B is off for some reason! - that I thhink is whhat leads to the issue!

//the scratchpad looks good also 

//next is the systolic reading!

//identity works!!


//All works perfectly in the 2 test cases - need to parameterise now! Maybe also test with 16x16 case if needed!

//TODO the issue of b_vec and a_vec hhas nothing to do with the PE matrix rule where it is being read

// 'define m_length 4

typedef Bit#(6) Addr;//this is the max number of rows in the matrix input 
typedef Bit#(32) Data;

typedef struct { Data a; Data b;} AB deriving (Eq, FShow, Bits, Bounded);

typedef struct {Bool access; Bit#(2) index;} Bram_access deriving (Eq, FShow, Bits, Bounded);

typedef struct {Addr location; Data value;} Response_c deriving (Eq, FShow, Bits, Bounded);

//TODO: use a typedef for all the 4s

//the max index of result here is 4x4
//add the start location to this as well
function Addr indices_to_location(Bit#(2) h_in, Bit#(2) w_in);
    //this should combinationally go through all the PE locations and get us the result out
    Addr h = extend(h_in);
    Addr w = extend(w_in);
    Addr loc = h*4 + w;
    return loc;
endfunction



/*
No locks etc needed as all the rules are Action calls and there is a central Q in the middle of each PE
*/
interface PE;
    method Action recieve_a(Data a); 
    method Action recieve_b(Data b); 
    method ActionValue#(Data) send_a();
    method ActionValue#(Data) send_b();
    method ActionValue#(Data) read_c();
endinterface

module mkPE(PE);
    //need to make sure that send_b happens after send_a as after send_b I calculate c
    Reg#(Data) c_value <- mkReg(0);
    
    FIFO#(Data) q_a <- mkFIFO; //check: what would be differeent with Bypass FIFO - also this is a erg right
    FIFO#(Data) q_b <- mkFIFO; 

    Reg#(Data) prod_a <- mkReg(0);
    Reg#(Data) prod_b <- mkReg(0);

    Reg#(Bool) prod_ready <- mkReg(False);

    rule prod if (prod_ready);
        c_value <= c_value + prod_a*prod_b;
        prod_ready <= False;
    endrule

    method Action recieve_a(Data a);
        q_a.enq(a);
    endmethod

    method Action recieve_b(Data b);
        q_b.enq(b);
    endmethod

    method ActionValue#(Data) send_a();
        let aa = q_a.first();
        q_a.deq();
        prod_a <= aa;
        return aa;
    endmethod

    method ActionValue#(Data) send_b();
        let bb = q_b.first();
        q_b.deq();
        prod_b <= bb;
        prod_ready <= True;
        return bb;
    endmethod
    

    method ActionValue#(Data) read_c();
        //this is to essentially read the value stored in here that is all
        return c_value;
    endmethod


endmodule


typedef enum {Ready, Fill_scratch_req, Fill_scratch_wait, Fill_scratch_respA, Fill_scratch_respB, Run_sys, Run_sys_bram_read, Stop_sys_input, Stop_sys} SystolicStatus deriving(Bits,Eq);
interface MM_sys;
    method Action start_conversion(Addr loc_a, Addr loc_b, Addr loc_c);//begins the acc, loc are the start 
    //addresses of the matrix in the memory
    method ActionValue#(Addr) aReq(); //Req sends a specific address location to get the value from
    method Action aResp(Data a); //responds with the value stored at that location
    method ActionValue#(Addr) bReq(); //Req sends a specific address location to get the value from
    method Action bResp(Data a); //responds with the value stored at that location
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
    FIFO#(Data) fromA <- mkBypassFIFO;
    FIFO#(Addr) toB <- mkBypassFIFO;
    FIFO#(Data) fromB <- mkBypassFIFO;

    Reg#(Bit#(2)) h_fill <- mkReg(0);//param: will change according to the length of the rows and columns 
    Reg#(Bit#(2)) w_fill <- mkReg(0);

    Vector#(4,Vector#(4,PE)) pe_matrix <- replicateM(replicateM(mkPE())); //syntax:check that REg is not needed arround PE

    Vector#(4,BRAM1Port#(Bit#(2),AB)) scratchpad <- replicateM(mkBRAM1Server(defaultValue)); //syntax: is this correct
    //param

    
    Reg#(Bit#(2)) h_sys <- mkReg(0);//param:
    Reg#(Bit#(2)) w_sys <- mkReg(0);

    Reg#(Bit#(2)) h_creq <- mkReg(0);//param:
    Reg#(Bit#(2)) w_creq <- mkReg(0);


    Vector#(4,Reg#(Data)) b_vec <- replicateM(mkReg(0));
    Vector#(4,Reg#(Data)) a_vec <- replicateM(mkReg(0));

    Vector#(4,Reg#(Data)) empty_vec <- replicateM(mkReg(0));

    // Reg#(Bit#(4)) index <- mkReg(0);//param:

    Vector#(4,Reg#(Bram_access)) bram_read <- replicateM(mkReg(Bram_access{access:False,index:0})); //make sure it is insttantiate as False

    Reg#(Data) cycles <- mkReg(0);


    rule fill_scratchpad_respond if (status == Fill_scratch_respB);
        $display("Rule fill_scratchpad_respond");
        let a_temp = fromA.first();
        let b_temp = fromB.first();
        fromA.deq();
        fromB.deq();//CHECK: hopefully the req method is called asap 

        AB in = AB{a:a_temp,b:b_temp};//TODO: check if this is correct syntax

        scratchpad[w_fill].portA.request.put(BRAMRequest{write: True,
                        responseOnWrite: False,
                        address: h_fill,
                        datain: in});


        if (w_fill == 3) begin
            if (h_fill == 3) begin
                h_fill <= 0;
                w_fill <= 0;
                status <= Run_sys;//scratchpad is filled
            end else begin
                h_fill <= h_fill + 1;
                w_fill <= 0;
                status <= Fill_scratch_req;
            end
        end else begin
            w_fill <= w_fill + 1;
            status <= Fill_scratch_req;
        end
    endrule

    rule fill_scratchpad_request if (status == Fill_scratch_req);
        $display("Rule fill_scratchpad_rrequestt");
        
        status <= Fill_scratch_wait;
        toA.enq(start_loca + indices_to_location(h_fill,3-w_fill));
        toB.enq(start_locb + indices_to_location(3-w_fill,h_fill));

    endrule


//TODO: this has to be fixed 
//TODO: need multiple rules to access multiple - just add a for loop here
    
    rule write_vectors if (status == Run_sys_bram_read);
        $display("Rule write_vectors");
        Vector#(4,Data) new_a_vec = replicate(0);
        Vector#(4,Data) new_b_vec = replicate(0);

        for (Integer bank = 0 ; bank < 4 ; bank = bank + 1) begin //param
            if (bram_read[bank].access) begin
                let temp <- scratchpad[bank].portA.response.get(); //TODO: I need the brams vector to be accessible over here
                new_a_vec[bram_read[bank].index] =  temp.a;
                new_b_vec[bram_read[bank].index] =  temp.b;
                bram_read[bank].access <= False;
            end
            //TODO: issue with the a_vec and b_vec conflictingg - but why? They are independant registers in there?
        end
        $display("new_a_vec", fshow(new_a_vec));
        $display("new_b_vec", fshow(new_b_vec));


        // for (Integer v = 0 ; v < 4 ; v = v + 1) begin //param
        //     a_vec[v] <= new_a_vec[v];
        //     b_vec[v] <= new_b_vec[v];
        // end


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

        for (Integer j = 0 ; j < 4 ; j = j + 1) begin
            for (Integer i = 0 ; i < 4 ; i = i + 1) begin
                //Recieve the values from the previous Q or from the prervious PE
                //TODO: fix the error here as the commands are actions and acttion values 
                if (i == 0)
                    pe_matrix[j][i].recieve_a(new_a_vec[j]);
                else begin
                    let a_s <- pe_matrix[j][i-1].send_a();
                    pe_matrix[j][i].recieve_a(a_s);
                end
                
                if (j == 0)
                    pe_matrix[j][i].recieve_b(new_b_vec[i]);
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
        cycles <= cycles + 1;

    endrule


    rule systolic_cycle if (status == Run_sys); 
        $display("Rule systolic_cycle");
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

    // rule systolic_PE_work if (status == Run_sys);
    //     $display("Rule systolic_PE_work");
    //     //this does the work for all the PEs
    //     //Is this combinational? It must be!! 
    //     for (Integer j = 0 ; j < 4 ; j = j + 1) begin
    //         for (Integer i = 0 ; i < 4 ; i = i + 1) begin
    //             //Recieve the values from the previous Q or from the prervious PE
    //             //TODO: fix the error here as the commands are actions and acttion values 
    //             if (i == 0)
    //                 pe_matrix[j][i].recieve_a(a_vec[j]);
    //             else begin
    //                 let a_s <- pe_matrix[j][i-1].send_a();
    //                 pe_matrix[j][i].recieve_a(a_s);
    //             end
                
    //             if (j == 0)
    //                 pe_matrix[j][i].recieve_b(b_vec[i]);
    //             else begin
    //                 let b_s <- pe_matrix[j-1][i].send_b();
    //                 pe_matrix[j][i].recieve_b(b_s);
    //             end 
                
                
    //             //Do product and Dump the values if the last PE
    //             if (i == 3)
    //                 let a_ss <- pe_matrix[j][i].send_a(); 
    //             if (j == 3) 
    //                 let b_ss <- pe_matrix[j][i].send_b();
    //         end
    //     end

    //     if (cycles == 10) //the 10 here comes from 3n - 2 total clock cycles needed for sys array
    //         status <= Stop_sys;
    //     else
    //         cycles <= cycles + 1; //TODO: make sure it does it the correct number of timee - ie the adding to this 
        
    // endrule

    //ERROR: the PE work is the issue!!
    rule systolic_PE_work_two if (status == Stop_sys_input);
        $display("Rule systolic_PE_work_two");
        //this does the work for all the PEs
        //Is this combinational? It must be!! 
        for (Integer j = 0 ; j < 4 ; j = j + 1) begin
            for (Integer i = 0 ; i < 4 ; i = i + 1) begin

                if (i == 0)
                    pe_matrix[j][i].recieve_a(0);
                else begin
                    let a_s <- pe_matrix[j][i-1].send_a();
                    pe_matrix[j][i].recieve_a(a_s);
                end
                
                if (j == 0)
                    pe_matrix[j][i].recieve_b(0);
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


    method Action start_conversion(Addr loc_a, Addr loc_b, Addr loc_c ) if (status == Ready);
        $display("Action start conversion");
        start_loca <= loc_a;
        start_locb <= loc_b;
        start_locc <= loc_c;
        status <= Fill_scratch_req;
        //TODO this would better happen inside the modul with a started gaurd
        for (Integer j = 0 ; j < 4 ; j = j + 1) begin
            for (Integer i = 0 ; i < 4 ; i = i + 1) begin
                pe_matrix[j][i].recieve_a(0);
                pe_matrix[j][i].recieve_b(0);
            end
        end
    endmethod

    method ActionValue#(Addr) aReq(); //gives address to get request from
		$display("Action aReq");
        toA.deq();
    	return toA.first();
    endmethod
    method Action aResp(Data a) if (status == Fill_scratch_wait);//gets tthe vvaluee stored at that address
    	$display("Action aResp");
        fromA.enq(a);
        status <= Fill_scratch_respA;
    endmethod
    method ActionValue#(Addr) bReq();
		$display("Action bReq");
        toB.deq();
		return toB.first();
    endmethod
    method Action bResp(Data b) if (status == Fill_scratch_respA);
		$display("Action bResp");
        fromB.enq(b);
        status <= Fill_scratch_respB;
    endmethod

    method ActionValue#(Response_c) cReq() if (status == Stop_sys);
        let loc = start_locc + indices_to_location(h_creq,w_creq);
        $display("Action cReq ",h_creq,",",w_creq, ", ", loc);
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
        c_resp.location = loc;
        c_resp.value <- pe_matrix[h_creq][w_creq].read_c();
        return c_resp;

    endmethod




endmodule





