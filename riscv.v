`timescale 1ns / 1ps

//Program counter
module Program_counter(clk, reset, PC_in, PC_out);
    input clk, reset;
    input [31:0] PC_in;
    output reg [31:0] PC_out;
    initial PC_out = 32'b0;
    always @(posedge clk or posedge reset) begin
        if (reset) PC_out <= 32'b0;
        else       PC_out <= PC_in;
    end
endmodule

// ---------------- PC + 4
module PCplus4(fromPC, nextopc);
    input  [31:0] fromPC;
    output [31:0] nextopc;
    assign nextopc = fromPC + 32'd4;
endmodule

// Generic adder (branch target) 
module adder32(a, b, y);
    input  [31:0] a, b;
    output [31:0] y;
    assign y = a + b;
endmodule

//Instruction memory
//t.
module Instruction_mem(reset, read_address, instruction_out);
    input reset;
    input  [31:0] read_address;
    output [31:0] instruction_out;
    reg [31:0] I_Mem [63:0];
    integer k;

    initial begin
        for (k = 0; k < 64; k = k + 1) I_Mem[k] = 32'b0;
        // Test program
        I_Mem[0] = 32'h00500093; // addi x1,x0,5
        I_Mem[1] = 32'h00300113; // addi x2,x0,3
        I_Mem[2] = 32'h002081B3; // add  x3,x1,x2   -> 8
        I_Mem[3] = 32'h40208233; // sub  x4,x1,x2   -> 2
        I_Mem[4] = 32'h00302023; // sw   x3,0(x0)
        I_Mem[5] = 32'h00002283; // lw   x5,0(x0)   -> 8
        I_Mem[6] = 32'h00518463; // beq  x3,x5,+8   (taken, skips next)
        I_Mem[7] = 32'h00100313; // addi x6,x0,1    (skipped)
        I_Mem[8] = 32'h00200393; // addi x7,x0,2    -> 2
    end

    assign instruction_out = I_Mem[read_address[7:2]];
endmodule

// ---------------- Register file ----------------
module reg_file(clk, reset, reg_write, rs1, rs2, rd, write_data, read_data1, read_data2);
    input clk, reset, reg_write;
    input [4:0] rs1, rs2, rd;
    input [31:0] write_data;
    output [31:0] read_data1, read_data2;
    reg [31:0] register [31:0];
    integer k;
    initial for (k = 0; k < 32; k = k + 1) register[k] = 32'b0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (k = 0; k < 32; k = k + 1) register[k] <= 32'b0;
        end
        else if (reg_write && rd != 5'b0) begin   // x0 stays zero
            register[rd] <= write_data;
        end
    end
    assign read_data1 = register[rs1];
    assign read_data2 = register[rs2];
endmodule

module immgen(opcode, instruction, immext);
    input  [6:0]  opcode;
    input  [31:0] instruction;
    output reg [31:0] immext;
    always @(*) begin
        case (opcode)
            7'b0000011,
            7'b0010011: immext = {{20{instruction[31]}}, instruction[31:20]};                       // I-type (lw, addi)
            7'b0100011: immext = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};    // S-type (sw)
            7'b1100011: immext = {{19{instruction[31]}}, instruction[31], instruction[7],
                                  instruction[30:25], instruction[11:8], 1'b0};                     // B-type (beq)
            default:    immext = 32'b0;
        endcase
    end
endmodule

// ---------------- Main control ----------------
// FIX: outputs must be reg, use blocking assignments in combinational logic,

module control_unit(instruction, branch, memread, memtoreg, aluop, memwrite, alusrc, regwrite);
    input [6:0] instruction;
    output reg branch, memread, memtoreg, memwrite, alusrc, regwrite;
    output reg [1:0] aluop;
    always @(*) begin
        case (instruction)
            //                                  alusrc memtoreg regwrite memread memwrite branch aluop
            7'b0110011: {alusrc,memtoreg,regwrite,memread,memwrite,branch,aluop} = 8'b0010_0010; // R-type
            7'b0010011: {alusrc,memtoreg,regwrite,memread,memwrite,branch,aluop} = 8'b1010_0011; // addi/andi/ori
            7'b0000011: {alusrc,memtoreg,regwrite,memread,memwrite,branch,aluop} = 8'b1111_0000; // lw
            7'b0100011: {alusrc,memtoreg,regwrite,memread,memwrite,branch,aluop} = 8'b1000_1000; // sw
            7'b1100011: {alusrc,memtoreg,regwrite,memread,memwrite,branch,aluop} = 8'b0000_0101; // beq
            default:    {alusrc,memtoreg,regwrite,memread,memwrite,branch,aluop} = 8'b0;
        endcase
    end
endmodule
//alu
module alu_unit(A, B, control_in, alu_result, zero);
    input [31:0] A, B;
    input [3:0] control_in;
    output reg [31:0] alu_result;
    output zero;
    always @(*) begin
        case (control_in)
            4'b0000: alu_result = A & B;
            4'b0001: alu_result = A | B;
            4'b0010: alu_result = A + B;
            4'b0110: alu_result = A - B;
            default: alu_result = 32'b0;
        endcase
    end
    assign zero = (alu_result == 32'b0);
endmodule

// //alucontrol
// func7 is only instruction[30] (the add/sub distinguisher).
module alu_control(aluop, func7, func3, control_out);
    input func7;
    input [2:0] func3;
    input [1:0] aluop;
    output reg [3:0] control_out;
    always @(*) begin
        casex ({aluop, func7, func3})
            6'b00_x_xxx: control_out = 4'b0010; // lw/sw  -> add
            6'b01_x_xxx: control_out = 4'b0110; // beq    -> subtract
            6'b10_0_000: control_out = 4'b0010; // add
            6'b10_1_000: control_out = 4'b0110; // sub
            6'b10_0_111: control_out = 4'b0000; // and
            6'b10_0_110: control_out = 4'b0001; // or
            6'b11_x_000: control_out = 4'b0010; // addi
            6'b11_x_111: control_out = 4'b0000; // andi
            6'b11_x_110: control_out = 4'b0001; // ori
            default:     control_out = 4'b0010;
        endcase
    end
endmodule

// ---------------- Data memory ----------------
module data_mem(clk, reset, memread, memwrite, address, write_data, read_data);
    input clk, reset, memread, memwrite;
    input [31:0] address, write_data;
    output [31:0] read_data;
    reg [31:0] D_Mem [63:0];
    integer k;
    initial for (k = 0; k < 64; k = k + 1) D_Mem[k] = 32'b0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (k = 0; k < 64; k = k + 1) D_Mem[k] <= 32'b0;
        end
        else if (memwrite) D_Mem[address[7:2]] <= write_data;
    end
    assign read_data = memread ? D_Mem[address[7:2]] : 32'b0;
endmodule

//  2:1 mux 
module mux2(a, b, sel, y);
    input [31:0] a, b;
    input sel;
    output [31:0] y;
    assign y = sel ? b : a;
endmodule

// Top level 
module Riscv(clk, reset);
    input clk, reset;

    wire [31:0] pc, pc_next, pc_plus4, branch_target, instr;
    wire [31:0] rd1, rd2, imm, alu_b, alu_out, mem_out, wb_data;
    wire [3:0]  alu_ctl;
    wire [1:0]  aluop;
    wire branch, memread, memtoreg, memwrite, alusrc, regwrite, zero;
    wire pcsrc = branch & zero;

    Program_counter PC (.clk(clk), .reset(reset), .PC_in(pc_next), .PC_out(pc));
    PCplus4 PC4 (.fromPC(pc), .nextopc(pc_plus4));
    Instruction_mem IMEM (.reset(reset), .read_address(pc), .instruction_out(instr));

    control_unit CU (.instruction(instr[6:0]), .branch(branch), .memread(memread),
                     .memtoreg(memtoreg), .aluop(aluop), .memwrite(memwrite),
                     .alusrc(alusrc), .regwrite(regwrite));

    reg_file RF (.clk(clk), .reset(reset), .reg_write(regwrite),
                 .rs1(instr[19:15]), .rs2(instr[24:20]), .rd(instr[11:7]),
                 .write_data(wb_data), .read_data1(rd1), .read_data2(rd2));

    immgen IG (.opcode(instr[6:0]), .instruction(instr), .immext(imm));

    adder32 BADD (.a(pc), .b(imm), .y(branch_target));   // imm already includes the <<1
    mux2 PCMUX (.a(pc_plus4), .b(branch_target), .sel(pcsrc), .y(pc_next));

    mux2 ALUSRC (.a(rd2), .b(imm), .sel(alusrc), .y(alu_b));
    alu_control ACTL (.aluop(aluop), .func7(instr[30]), .func3(instr[14:12]), .control_out(alu_ctl));
    alu_unit ALU (.A(rd1), .B(alu_b), .control_in(alu_ctl), .alu_result(alu_out), .zero(zero));

    data_mem DMEM (.clk(clk), .reset(reset), .memread(memread), .memwrite(memwrite),
                   .address(alu_out), .write_data(rd2), .read_data(mem_out));
    mux2 WBMUX (.a(alu_out), .b(mem_out), .sel(memtoreg), .y(wb_data));
endmodule