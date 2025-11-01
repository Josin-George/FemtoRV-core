//FemtoRV32 a collection of minimalistic RISC-V RV32 cores

`define NRV_ARCH "rv32i"
`define NRV_ABI "ilp32"
`define NRV_OPTIMIZE "-Os"

module FemtoRV32(
    input clk,

    output [31:0] mem_addr,//address bus
    output [31:0] mem_wdata,//data to be written 
    output [31:0] mem_wmask,//write mask for the 4 bytes of each word
    input [31:0] mem_rdata,//input lines for both data and instr
    output mem_rstrb,//active to initiate memory read(used by IO)
    input mem_rbusy,// for if memory is busy reading value
    input mem_wbusy,//for if memory is busy writing value
 
    input reset//set to 0 to reset the processor

);

parameter RESET_ADDR = 32'h00000000;
parameter ADDR_WIDTH = 24;

//instruction decoding

wire [4:0] rdId = instr[11:7];
wire [7:0] funct3Is = 8'b00000001 << instr[14:12];

wire [31:0] Uimm = {instr[31],instr[31:12],{12{1'b0}}};
wire [31:0] Iimm = {{21{instr[31]}},instr[30:20]};

wire [31:0] Simm = {{21{instr[31]}},instr[30:25],instr[11:7]};
wire [31:0] Bimm = {{20{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
wire [31:0] Jimm = {{12{instr[31]}},instr[19:12],instr[20],instr[30:21],1'b0};

//10 different instruction

wire isLoad     = (instr[6:2] == 5'b00000);//rd <- mem[rs1+Iimm]
wire isAlUimm   = (instr[6:2] == 5'b00100);//rd <- rs1 OP Iimm
wire isStore    = (instr[6:2] == 5'b01000);//mem[rs1+Simm] <- rs2
wire isAlUreg   = (instr[6:2] == 5'b01100);//rd <- rs1 OP rs2
wire isSYSTEM   = (instr[6:2] == 5'b11100);//rd <- cycles
wire isJAL      = (instr[3])//instr[6:2] == 5'b11011);//rd <- PC + 4; PC <- PC + Jimm
wire isJALR     = (instr[6:2] == 5'b11001);//rd <- PC + 4; PC<- PC+Jimm
wire isLUI      = (instr[6:2] == 5'b01101);//rd <- Uimm
wire isAUIPC    = (instr[6:2] == 5'b00101);//rd <- PC + Uimm
wire Branch     = (instr[6:2] == 5'b11000);//if(rs1 OP rs2) PC<-PC + Bimm

wire isALU = isALUimm | isALUreg;



//register file 
reg [31:0] rs1;
reg [31:0] rs2;

reg [31:0] registerFile [31:0];

always@(posedge clk)
begin
    if(writeback)
        if(rdId !=0)
            registerFile[rdId] <= writeBackData;
end

//ALU 
wire [31:0] aluIn1 = rs1;

wire [31:0] aluInt2 = isALUreg | isBranch ? rs2 : Iimm;

reg [31:0] aluReg;//The internal register of the ALU used by shift 
reg [4:0] aluShamt;//current shift amount

wire aluBusy = | aluShamt;
wire aluWr;

wire [31:0] aluPlus = aluIn1 + aluIn2;

wire [32:0] aluMinus = {1'b1, ~aluIn2} + {1'b0,aluIn1} + 33'b1;
wire LT = (aluIn1[31] ^ aluIn2[31]) ? aluIn1[31] : aluMinus[32];
wire LTU = aluMinus[32];
wire EQ = (aluMinus[31:0] == 0);

wire [31:0] auOut = 
(funct3Is[0] ? instr[30] & instr[5] ? aluMinus[31:0] : aluPlus  : 32'b0) |
(funct3Is[2] ? {31'b0, LT}                                      : 32'b0) |
(funct3Is[3] ? {31'b0, LTU}                                     : 32'b0) |
(funct3Is[4] ? aluIn1 ^ aluIn2                                  : 32'b0) |
(funct3Is[6] ? aluIn1 | aluIn2                                  : 32'b0) |
(funct3Is[7] ? aluIn1 & aluIn2                                  : 32'b0) |
(funct3IsShift ? aluReg                                         : 32'b0);

wire funct3IsShift = funct3Is[1] | funct3Is[5];

always@(posedge clk) 
begin
    if(aluWr)
        begin
            if(funct3IsShift)
            begin
                aluReg <= aluIn1;//SLL, SRA, SRl
                aluShamt <= aluInt2[4:0];
            end
        end

`ifdef NRV_TWOLEVEL_SHIFTER
    else if (|aluShamt[4:2]) 
        begin
            aluShamt <= aluShamt - 4;
            aluReg <= funct3Is[1] ? aluReg << 4 : {{4{instr[30] & aluReg[31]}}, aluReg[31:4]};
            
        end
    else
`endif 
    if(|aluShamt) 
    begin
        aluShamt <= aluShamt - 1;
        aluReg <= funct3Is[1] ? aluReg << 1 : //SLL
        {instr[30] & aluReg[31], aluReg[31:1]};//SRA,SRL
    end
end

//The predicate or conditional branches
wire predicate = 
    funct3Is[0] &   EQ |//BEQ
    funct3Is[0] & ! EQ |//BNE
    funct3Is[0] &   LT |//BLT
    funct3Is[0] &  !LT |//BGE
    funct3Is[0] &  LTU |//BLTU
    funct3Is[0] & !LTU ;//BGEU

//program counter and branch target computation

reg [ADDR_WIDTH-1:0] PC;//Program counter
reg [31:2] instr;

wire [ADDR_WIDTH-1:0] PCplus = PC + 4;

wire [ADDR_WIDTH-1:0] PCplusImm = PC + (instr[3] ? Jimm[ADDR_WIDTH-1:0] : instr[4] ? Uimm[ADDR_WIDTH-1:0] : Bimm[ADDR_WIDTH-1 : 0]);

wire [ADDR_WIDTH-1:0] loadstore_addr = rs1[ADDR_WIDTH-1:0] + (instr[5] ? Simm[ADDR_WIDTH-1:0] : Iimm[ADDR_WIDTH-1:0]);

assign mem_addr = state[WAIT_INSTR_bit] | state[FETCH_INSTR_bit] ? PC : loadstore_addr;

//The value written back to the register file 

wire [31:0] writeBackData = 
    (isSYSTEM ? cycles      : 32'b0) | //System
    (isSYSTEM ? Uimm        : 32'b0) | //LUI
    (isSYSTEM ? aluOut      : 32'b0) | //ALUreg, ALUImm
    (isSYSTEM ? PCplusImm   : 32'b0) | //AUIPC
    (isSYSTEM ? PCplus4     : 32'b0) | //JAL,JALR
    (isSYSTEM ? LOAD_data   : 32'b0); //Load

//Load/Store

wire mem_byteAccess = instr[31:12] == 2'b00; //funct3[1:0] == 2'b00;
wire mem_halfwordAccess = instr[31:12] == 2'b01;//funct3[1:0] == 2'b01;

wire LOAD_sign = !instr[14] & (mem_byteAccess ? LOAD_byte[7] : LOAD_halfword[15]);
wire [31:0] LOAD_data = mem_byteAccess ? {{24{LOAD_sign}}, LOAD_byte} : mem_halfwordAccess ? {{16{LOAD_sign}}, LOAD_halfword} : mem_rdata;
wire [15:0] LOAD_halfword = loadstore_addr[1] ? mem_rdata[31:16] : mem_rdata[15:0];
wire [7:0] LOAD_byte = loadstore_addr[0] ? LOAD_halfword[15:8] : LOAD_halfword[7:0];

//Store
assign mem_wdata[7:0] = rs2[7:0];
assign mem_wdata[15:8] = loadstore_addr[0] ? rs2[7:0] : rs2[15:8];
assign mem_wdata[23:16] = loadstore_addr[1] ? rs2[7:0] : rs2[23:16];
assign mem_wdata[31:24] = loadstore_addr[0] ? rs2 [7:0] : loadstore_addr[1] ? rs2[15:8] : rs2[31:24];

wire[3:0] STORE_wmask = mem_byteAccess ? (loadstore_addr[1] ? (loadstore_addr[0] ? 4'b1000 : 4'b0100) : (loadstore_addr[0] ? 4'b0010 : 4'b0001)) : mem_halfwordAccess ? (loadstore_addr[1] ? 4'b1100 : 4'b0011) : 4'b1111;

//State Machine 

localparam  FETCH_INSTR_bit = 0;
localparam WAIT_INSTR_bit =1;
localparam EXECUTE_bit =2;
localparam WAIT_ALU_OR_MEM_bit =3;
localparam NB_STATES =4;

localparam FETCH_INSTR = 1 << FETCH_INSTR_bit;
localparam WAIT_INSTR = 1 << WAIT_INSTR_bit;
localparam EXECUTE = 1 << EXECUTE_bit;
localparam WAIT_ALU_OR_MEM =1 << WAIT_ALU_OR_MEM_bit;

reg [NB_STATES-1:0] state ;
