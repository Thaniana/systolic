import Vector::*;
import BRAM::*;

typedef Bit#(4) Addr;

interface MM;
    method Action load_row_a(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action load_row_b(Vector#(16, Bit#(32)) row, Bit#(4) row_idx);
    method Action start();
    method ActionValue#(Vector#(16, Bit#(32))) resp_row_c();
endinterface

function Bit#(32) one_product(Vector#(16, Bit#(32)) row, Vector#(16, Bit#(32)) col);
    Bit#(32) result = 0;
    for (Integer i = 0; i <16 ; i = i+1) begin 
        result = result + row[i]*col[i];
    end 
    return result;
endfunction



(* synthesize *)
module mkMatrixMultiplyFolded(MM);
        
        Reg#(Bool) valid_a <- mkReg(False);
        Reg#(Bool) valid_b <- mkReg(False);
        Reg#(Bool) valid_c <- mkReg(False);
        Reg#(Bool) resp_ready <- mkReg(False);
        Reg#(Bool) mult_ready <- mkReg(False);
        Reg#(Bool) reading_row <- mkReg(False);
        Reg#(Bool) reading_row_bram <- mkReg(False);
        Reg#(Bool) reading_col <- mkReg(False);
        Reg#(Bool) reading_col_bram <- mkReg(False);
        Reg#(Bool) product_row <- mkReg(False);
        Reg#(Bool) product_col <- mkReg(False);
        Reg#(Bool) valid_write_c <- mkReg(False);
        Reg#(Bool) valid_res_respond_c <- mkReg(False);



        Reg#(Bit#(4)) load_row_idx_a <- mkReg(0);
        Reg#(Bit#(4)) row_read_idx <- mkReg(0);
        Reg#(Bit#(4)) col_read_idx <- mkReg(0);
        Reg#(Bit#(4)) load_row_idx_b <- mkReg(0);
        Reg#(Bit#(4)) resp_row_idx <- mkReg(0);
        Reg#(Bit#(4)) every_row_idx <- mkReg(0); 
        Reg#(Bit#(5)) write_c_id <- mkReg(0);

        Reg#(Vector#(16, Bit#(32))) row_a <- mkReg(?);
        Reg#(Vector#(16, Bit#(32))) row_b <- mkReg(?);
        Reg#(Vector#(16, Bit#(32))) row_c <- mkReg(?);

        Reg#(Vector#(16, Bit#(32))) row_a_load <- mkReg(?);
        Reg#(Vector#(16, Bit#(32))) row_b_load <- mkReg(?);
        Reg#(Vector#(16, Bit#(32))) row_c_resp <- mkReg(?);

        Reg#(Vector#(16, Bit#(32))) temp <- mkReg(?);
        Reg#(Bit#(32)) product <- mkReg(0);
        Reg#(Bit#(9)) element_count <- mkReg(0);



        //3 Brams initialised 
        BRAM1Port#(Addr, Vector#(16, Bit#(32))) a <- mkBRAM1Server(defaultValue);
        BRAM1Port#(Addr, Vector#(16, Bit#(32))) b <- mkBRAM1Server(defaultValue);
        BRAM1Port#(Addr, Vector#(16, Bit#(32))) c <- mkBRAM1Server(defaultValue);


        rule load_bram_a if(valid_a);
            
            a.portA.request.put(BRAMRequest{write: True, // False for read
                         responseOnWrite: False,
                         address: load_row_idx_a,
                         datain: row_a_load}); //where would thee response come 

            valid_a <= False;


        endrule

        rule load_bram_b if(valid_b);

            b.portA.request.put(BRAMRequest{write: True, // False for read
                         responseOnWrite: False,
                         address: load_row_idx_b,
                         datain: row_b_load}); //where would thee response come 
            
            valid_b <= False;

        endrule



        rule column_reading if (reading_col && !product_col && !valid_c && !valid_b);
            
            let res_temp <- b.portA.response.get();
            row_b[every_row_idx] <= res_temp[col_read_idx];
            
            if (every_row_idx >= 15) begin
                col_read_idx <= col_read_idx + 1;
                product_col <= True;
                every_row_idx <= 0;
            end else begin
                reading_col_bram <= True; 
                every_row_idx <= every_row_idx + 1;
            end
        endrule

        rule column_reading_bram if (reading_col_bram && !product_col && !valid_c && !valid_b);
            // $display("in col read brram");
            b.portA.request.put(BRAMRequest{write: False,
                        responseOnWrite: False,
                        address: every_row_idx,
                        datain: ?}); 
            reading_col_bram <= False;
            reading_col <= True; 
        endrule

        rule row_reading if (reading_row && !product_row && !valid_a);
            // $display("in row reading");
            let resa <- a.portA.response.get(); //should be a vector
            row_a <= resa;
            product_row <= True;
        endrule

        rule row_reading_bram if (reading_row_bram && !product_row && !valid_a);
            // $display("in row read bram");
            //the goal here is to read the column and return it in row_a
            a.portA.request.put(BRAMRequest{write: False,
                         responseOnWrite: False,
                         address: row_read_idx,
                         datain: ?});
            reading_row_bram <= False;
            reading_row <= True;
        endrule
        rule product_ready if(mult_ready && product_row && product_col && !valid_c);
            if (write_c_id >= 16) begin

                c.portA.request.put(BRAMRequest{write: True, // False for read
                         responseOnWrite: False,
                         address: row_read_idx,
                         datain: row_c}); 
                row_read_idx <= row_read_idx + 1;
                
                write_c_id <= 0;
                //below is done to delay the thing to get the reesponse in
                reading_row <= False;
                reading_col <= False;
                product_col <= False;
                product_row <= False;
                element_count <=  element_count + 1;
            end else begin
                row_c[write_c_id] <= one_product(row_a,row_b);
                if (write_c_id != 15) begin
                    reading_row <= False;
                    reading_col <= False;
                    product_col <= False;
                    product_row <= False;
                    element_count <=  element_count + 1;
                end
                write_c_id <= write_c_id + 1;
            end
        endrule


        rule multiply if(mult_ready && !reading_row && !reading_col && !valid_c && !product_row && !product_col);
            if (element_count >= 256) begin
                mult_ready <= False;
                valid_c <= True;
                row_read_idx <= row_read_idx + 1; //check this 
                col_read_idx <= 0;
                element_count <= 0;
            end else begin
                reading_row_bram <= True;
                reading_col_bram <= True; 
            end
        endrule
        


        //gets the first valid_c from the multiply function 
        rule respond_bram_c if(valid_c && !mult_ready);

            c.portA.request.put(BRAMRequest{write: False,
                         responseOnWrite: False,
                         address: resp_row_idx,
                         datain: ?});  

            valid_res_respond_c <= True;
            valid_c <= False;

        endrule

        rule res_respond_bram_c if (valid_res_respond_c);
            let res <- c.portA.response.get();
            row_c_resp <= res;
            resp_ready <= True;
            valid_res_respond_c <= False;
        endrule

        method Action load_row_a(Vector#(16, Bit#(32)) row, Bit#(4) row_idx) if (!valid_a && !mult_ready && !resp_ready);
            // $display("enters Action 1");
            valid_a <= True;
            load_row_idx_a <= row_idx;
            row_a_load <= row;
        endmethod

        //I am doing the gauurd in both the rule and the action is that fine?
        method Action load_row_b(Vector#(16, Bit#(32)) row, Bit#(4) row_idx) if (!valid_b && !mult_ready  && !resp_ready);
            // $display("enters action 2");
            valid_b <= True;
            load_row_idx_b <= row_idx;
            row_b_load <= row;
        endmethod

        method ActionValue#(Vector#(16, Bit#(32))) resp_row_c() if (resp_ready && !mult_ready);
            // $display("Enters action 3"); //this called but does not go to the rule 
            // let res <- c.portA.response.get();
            // row_c_resp <= res;
            resp_row_idx <= resp_row_idx + 1;
            if (resp_row_idx >= 15)
                valid_c <= False;
            else
                valid_c <= True;
            resp_ready <= False; //do not really need this - i can just use valid_c starting at the right time
            return row_c_resp; //SO at the end of the multiplication save the first row into the row_c variable and assign the row idx to 1 and then begin so that previous value is retured correctly 
        endmethod

        method Action start() if (!mult_ready && !valid_a && !valid_b && !valid_c);

            mult_ready <= True;
            element_count <= 0;
            row_read_idx <= 0; 

        endmethod

endmodule


