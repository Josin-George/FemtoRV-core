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

wire isLoad = (instr[6:2] == 5'b00000);//rd <- mem[rs1+Iimm]
wire isAlU


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