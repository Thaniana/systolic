//CHECK WITH LIKE A 2x2 or a 3x3 to figure out if the issue is with making due to the size
import BRAM::*;
import systolicMM::*;
import memTypes::*;

typedef enum {Ready, ReqA,Save_RespA,ReqB,RespA,RespB,ReqC, Compare, Compare_check} Status deriving(Bits,Eq);


module mkSystolicTest(Empty);


    BRAM_Configure cfgA = defaultValue();
    cfgA.loadFormat = tagged Hex "identityvector.vmh";//param
    BRAM2Port#(LineAddr, MainMemResp) bram <- mkBRAM2Server(cfgA);//param
    //What is this 4 over here? - the n one 
    //the addrress length should now 

    let debug = True;

    Reg#(Status) status<- mkReg(Ready);


    //make 1 bram with all 3 addresses! - will have  to change some of the stuff inside fo it to workr with this!

    MM_sys mma <- mkSystolic();



    Reg#(Addr) cycle_count <- mkReg(0);
    Reg#(Addr) cycle_count_c <- mkReg(0);

    //for 16x16
    // Reg#(Addr) cmp_cnt <- mkReg(512);//param
    Reg#(Addr) cmp_cnt <- mkReg(2);//4x4
    // Reg#(Addr) cmp_cnt <- mkReg(8);//2x2


    //NEW STUFF

    Reg#(MainMemReq) areq <- mkRegU;
    Reg#(MainMemReq) breq <- mkRegU;

    Reg#(MainMemResp) data_a <- mkReg(?);    

    rule requestA if (status == ReqA);
        $display("test requestA");
        let req <- mma.aReq;
        if (debug) $display("Get AReq", fshow(req));
        areq <= req;
        bram.portB.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: req.addr,
                datain: ?});
        status <= Save_RespA;
    endrule

    //TODO: try getting rid of this and see if it still works?
    rule save_responseA if (status == Save_RespA);
        let x <- bram.portB.response.get();
        let req = areq;
        if (debug) $display("Save AResp ", fshow(req), fshow(x));
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
        let req <- mma.bReq;
        breq <= req;
        if (debug) $display("Get BReq", fshow(req));
        bram.portB.request.put(BRAMRequest{
          write: False,
          responseOnWrite: False,
          address: req.addr,
          datain: ?});
        status <= RespA;
    endrule

    rule responseB if (status == RespB);
        let x <- bram.portB.response.get();
        let req = breq;
        if (debug) $display("Get BResp ", fshow(req), fshow(x));
        mma.bResp(x);
        status <= ReqC;
        // if (cycle_count == 15) begin //param
        // // if (cycle_count == 255) begin //16x16
        // // if (cycle_count == 7) begin //2x2
        //     status <= ReqC;
        //     cycle_count <= 0;
        // end
        // else begin
        //     cycle_count <= cycle_count + 1;
        //     status <= ReqA;
        // end
    endrule


    rule requestC if (status == ReqC);
        let req <- mma.cReq;
        if (debug) $display("Get CReq", fshow(req));//this prints correctly here and then messes up someplace else
        bram.portB.request.put(BRAMRequest{
          write: True,
          responseOnWrite: False,
          address: req.addr,
          datain: req.data});
          status <= Compare;
        // if (cycle_count_c == 15) begin //param
        // // if (cycle_count_c == 7) begin //2x2
        // // if (cycle_count_c == 255) begin //16x16
        //     status <= Compare;
        //     cycle_count_c <= 0;
        // end
        // else
        //     cycle_count_c <= cycle_count_c + 1;
    endrule


    rule cmp_check  if (status == Compare_check);
        let x <- bram.portB.response.get();
        // $display("cnt = ", cmp_cnt-32, " Value = ",x);//param
        $display("c = ", fshow(x));
        // $display("cnt = ", cmp_cnt-8, " Value = ",x);//2x2
        // $display("cnt = ", cmp_cnt-512, " Value = ",x);

        // if (cmp_cnt == 47) begin //param
        //     cmp_cnt <= 32;//param
        // if (cmp_cnt == 767) begin //16x16
        //     cmp_cnt <= 512;//16x16
        // if (cmp_cnt == 11) begin //2x2
        //     cmp_cnt <= 8;//2x2
        status <= Ready;
        $display("end test");
        $fflush(stderr);
        $finish;
        // end 
        // else begin
        //     cmp_cnt <= cmp_cnt + 1;
        //     status <= Compare;
        // end
    endrule
    
    rule cmp if (status == Compare);
        bram.portB.request.put(BRAMRequest{
          write: False,
          responseOnWrite: False,
          address: 2, //param
          datain: ?});
        status <= Compare_check;
    endrule

    rule start if (status == Ready);
        $display("test started");
        mma.start_conversion(0,1,2);//param
        // mma.start_conversion(0,256,512);
        // mma.start_conversion(0,4,8);//2x2

        status <= ReqA;
    endrule



endmodule

