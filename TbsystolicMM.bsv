/*
the brams and the gaurds!!

Should I rather use an FSM!

Ok much better now - it is reading and at least moving on - some logic maybe incorrect

The question is how to parametize the function!

THe issue is with the testcase - request for one of them gets over writteen

*/

//toppipeline.bsv - is th file to look into for how to gt 

//vmh file starts with @0 and thn each line is th lin with th bit 32 value to hold and the n no need to end 
//add tag Bin instead of tag Hex in the top pipeline bsv


import BRAM::*;
import systolicMM::*;

typedef enum {Ready, ReqA,Save_RespA,ReqB,RespA,RespB,ReqC, Compare, Compare_check} Status deriving(Bits,Eq);


module mkSystolicTest(Empty);

    BRAM_Configure cfgA = defaultValue();
    cfgA.loadFormat = tagged Hex "numbered.vmh";
    BRAM2PortBE#(Addr, Data,4) bram <- mkBRAM2ServerBE(cfgA);//param
    //What is this 4 over here? - the n one 
    //the addrress length should now 

    let debug = True;

    Reg#(Status) status<- mkReg(Ready);


    //make 1 bram with all 3 addresses! - will have  to change some of the stuff inside fo it to workr with this!

    MM_sys mma <- mkSystolic();



    Reg#(Data) cycle_count <- mkReg(0);
    Reg#(Data) cycle_count_c <- mkReg(0);

    Reg#(Addr) cmp_cnt <- mkReg(32);//param


    // rule tic;
    //     if (debug) $display("Test Multiplication");
	//     cycle_count <= cycle_count + 1;
    // endrule

    //use fdisplay to end the function itself - ie the test case



    //NEW STUFF

    Reg#(Addr) areq <- mkRegU;
    Reg#(Addr) breq <- mkRegU;

    Reg#(Data) data_a <- mkReg(0);    

    rule requestA if (status == ReqA);
        $display("test requestA");
        let req <- mma.aReq;
        if (debug) $display("Get AReq", fshow(req));
        areq <= req;
        bram.portB.request.put(BRAMRequestBE{
                writeen: 0,
                responseOnWrite: False,
                address: req,
                datain: ?});
        status <= Save_RespA;
    endrule

    //TODO: try getting rid of this and see if it still works?
    rule save_responseA if (status == Save_RespA);
        let x <- bram.portB.response.get();
        let req = areq;
        // if (debug) $display("Save AResp ", fshow(req), fshow(x));
        data_a <= x;
        status <= ReqB;
    endrule

    rule responseA if (status == RespA);
        let x = data_a;
        let req = areq;
        if (debug) $display("Get AResp ", fshow(req), fshow(x));
        mma.aResp(x);
        status <= RespB;
    endrule

    rule requestB if (status == ReqB);
        let req <- mma.bReq;//TODO: do I need the rvcore
        breq <= req;
        if (debug) $display("Get BReq", fshow(req));
        bram.portB.request.put(BRAMRequestBE{
          writeen: 0,
          responseOnWrite: False,
          address: req,
          datain: ?});
        status <= RespA;
    endrule

    rule responseB if (status == RespB);
        let x <- bram.portB.response.get();
        let req = breq;
        if (debug) $display("Get BResp ", fshow(req), fshow(x));
        mma.bResp(x);
        if (cycle_count == 15) begin
            status <= ReqC;
            cycle_count <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;
            status <= ReqA;
        end
    endrule


    rule requestC if (status == ReqC);
        let req <- mma.cReq;
        if (debug) $display("Get CReq", fshow(req));//this prints correctly here and then messes up someplace else
        bram.portB.request.put(BRAMRequestBE{
          writeen: 11,
          responseOnWrite: False,
          address: req.location,
          datain: req.value});
        if (cycle_count_c == 15) begin
            status <= Compare;
            cycle_count_c <= 0;
        end
        else
            cycle_count_c <= cycle_count_c + 1;
    endrule


    rule cmp_check  if (status == Compare_check);
        Data x <- bram.portB.response.get();
        $display("Value = ",x);//TODO it is cutting off at 2 hexadecimal digits 
        if (cmp_cnt == 47) begin
            cmp_cnt <= 32;
            status <= Ready;
            $display("end test");
            $fflush(stderr);
            $finish;
        end 
        else begin
            cmp_cnt <= cmp_cnt + 1;
            status <= Compare;
        end
    endrule
    
    rule cmp if (status == Compare);
        bram.portB.request.put(BRAMRequestBE{
          writeen: 0,
          responseOnWrite: False,
          address: cmp_cnt,
          datain: ?});
        status <= Compare_check;
    endrule

    rule start if (status == Ready);
        $display("test started");
        mma.start_conversion(0,16,32);//param
        status <= ReqA;
    endrule



endmodule

