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
end

