`include "cpu_define.v"
`include "../memory/bus_define.v"
`include "alu_define.v"

// cpu status
`define STATUS_LEN 4
`define STATUS_INIT           `STATUS_LEN'h0
`define STATUS_FETCHING_INSTR `STATUS_LEN'h1
`define STATUS_DECODING_INSTR `STATUS_LEN'h2
`define STATUS_SET_FLAG       `STATUS_LEN'h3
`define STATUS_MEM_READ       `STATUS_LEN'h5
`define STATUS_MEM_READING    `STATUS_LEN'h6
`define STATUS_ALU            `STATUS_LEN'h7
`define STATUS_ALU_2          `STATUS_LEN'h13
`define STATUS_ALUING         `STATUS_LEN'h8
`define STATUS_REG_WRITE      `STATUS_LEN'h9
`define STATUS_REG_WRITE_POST `STATUS_LEN'h4
`define STATUS_MEM_WRITE      `STATUS_LEN'h10
`define STATUS_MEM_WRITING    `STATUS_LEN'h11
`define STATUS_BRANCH         `STATUS_LEN'h12

module cpu(
	input clk,
    input clr_n,
    output reg cpu_clk,
    //SDRAM ports
    output [12:0] ADDR,
	output [1:0]  BA,
	inout  [15:0] DQ,
	output        CKE, CLK,
	output        CS_N, RAS_N, CAS_N, WE_N,
	output [1:0]  DMASK
);

//=======================================================
//  REG/WIRE declarations
//=======================================================

// gregs
reg  gregs_wen;
wire [`CPU_GREGIDX_WIDTH-1:0] gregs_rs1_idx;
wire [`CPU_GREGIDX_WIDTH-1:0] gregs_rs2_idx;
wire [`CPU_GREGIDX_WIDTH-1:0] gregs_rd_idx;
wire [`CPU_XLEN-1:0] gregs_rs1_dat;
wire [`CPU_XLEN-1:0] gregs_rs2_dat;
reg  [`CPU_XLEN-1:0] gregs_rd_dat;

// alu
reg  [`CPU_XLEN-1:0] alu_src_A;
reg  [`CPU_XLEN-1:0] alu_src_B;
reg  [3:0] alu_select;
wire [63:0] alu_dest;
wire [3:0] alu_flags;
reg  alu_rst;
wire alu_ready;

// bus
reg  [25:0] bus_address;
wire [31:0] bus_rdata;
reg  [1:0]  bus_wlen;
reg  [31:0] bus_wdata;
reg  bus_en_n;
wire bus_ready;

// decoder
reg  [`CPU_INSTR_LENGTH-1 : 0] decoder_instr;
wire [`CPU_GREGIDX_WIDTH-1 : 0] decoder_rs1_idx;
wire [`CPU_GREGIDX_WIDTH-1 : 0] decoder_rs2_idx;
wire [`CPU_GREGIDX_WIDTH-1 : 0] decoder_rs3_idx;
wire [`CPU_GREGIDX_WIDTH-1 : 0] decoder_rd_idx;
wire [`CPU_XLEN-1 : 0] decoder_imm;
wire [`FUNCT_WIDTH-1 : 0] decoder_funct;
wire [`OPCODE_WIDTH-1 : 0] decoder_opcode;
wire [`CPU_INSTR_DECODE_INFO_WIDTH-1 : 0] decoder_dec_instr_info;
wire decoder_instr_valid;
wire decoder_fp_rm;
wire decoder_fp_width;
wire decoder_fp_fmt;
// gRegs idx always be the decoding result
assign gregs_rs1_idx = decoder_rs1_idx;
assign gregs_rs2_idx = decoder_rs2_idx;
assign gregs_rd_idx  = decoder_rd_idx;

// PC
reg [31:0] pc;
reg [31:0] pc_nxt;
// flags
reg flag_alu;
reg flag_reg_write;
reg flag_mem_read;
reg flag_mem_write;
reg flag_branch;
// status
reg [`STATUS_LEN-1 : 0] status;

//=======================================================
//  Structural coding
//=======================================================

// gregs
cpu_gregs gregs(
    .clk(clk),
    .rd_wen(gregs_wen),
    .rs1_idx(gregs_rs1_idx),
    .rs2_idx(gregs_rs2_idx),
    .rd_idx(gregs_rd_idx),
    .rs1_dat(gregs_rs1_dat),
    .rs2_dat(gregs_rs2_dat),
    .rd_dat(gregs_rd_dat)
);

// alu
cpu_alu alu(
    .clk(clk),
    .src_A(alu_src_A),
    .src_B(alu_src_B),
    .select(alu_select),
    .dest(alu_dest),
    .flags(alu_flags),
    .RST(alu_rst),
    .READY(alu_ready)
);

// bus
cpu_bus bus(
    .clk(clk),
    .address(bus_address),
    .wdata(bus_wdata),
    .WLEN(bus_wlen),
    .rdata(bus_rdata),
    .EN_N(bus_en_n),
    .READY(bus_ready),

    .ADDR(ADDR),
    .BA(BA),
    .DQ(DQ),
    .CKE(CKE),
    .CLK(CLK),
    .CS_N(CS_N),
    .RAS_N(RAS_N),
    .CAS_N(CAS_N),
    .WE_N(WE_N),
    .DMASK(DMASK)
);

// decoder
cpu_instr_decoder decoder(
    .instr(decoder_instr),
    .rs1_idx(decoder_rs1_idx),
    .rs2_idx(decoder_rs2_idx),
    .rs3_idx(decoder_rs3_idx),
    .rd_idx(decoder_rd_idx),
    .imm(decoder_imm),
    .funct(decoder_funct),
    .opcode(decoder_opcode),
    .dec_instr_info(decoder_dec_instr_info),
    .instr_valid(decoder_instr_valid),
    .fp_rm(decoder_fp_rm),
    .fp_width(decoder_fp_width),
    .fp_fmt(decoder_fp_fmt)
);

// main logic
always @(posedge clk) begin
    if (!clr_n) begin
        pc     <= 0;
        status <= `STATUS_INIT;
        gregs_wen <= 0;
        alu_rst <= 0;
        cpu_clk <= 0;
    end else begin
        case(status)
            `STATUS_INIT: begin
                status <= `STATUS_FETCHING_INSTR;
                flag_alu   <= 0;
                flag_reg_write  <= 0;
                flag_mem_read   <= 0;
                flag_mem_write  <= 0;
                flag_branch     <= 0;
                cpu_clk <= 0;
            end
            `STATUS_FETCHING_INSTR: begin
                cpu_clk <= 1;
                bus_address <= pc;
                bus_wlen    <= `BUS_READ_32;
                bus_en_n      <= `BUS_RUN;
                status <= `STATUS_DECODING_INSTR;
            end
            `STATUS_DECODING_INSTR: begin
                if (bus_ready == `BUS_STOP) begin
                    decoder_instr <= bus_rdata;
                    status <= `STATUS_SET_FLAG;
                end else begin
                    status <= `STATUS_DECODING_INSTR;
                end
            end
            `STATUS_SET_FLAG: begin
                if (decoder_instr_valid) begin
                    case (decoder_dec_instr_info[`CPU_INSTR_INFO_WIDTH+`CPU_INSTR_OPR_INFO_WIDTH-1 : `CPU_INSTR_OPR_INFO_WIDTH])
                        `CPU_INSTR_GRP_LUI: begin
                            flag_reg_write <= 1;
                            gregs_rd_dat   <= decoder_imm;
                            status <= `STATUS_REG_WRITE;
                        end
                        `CPU_INSTR_GRP_AUIPC: begin
                            flag_reg_write <= 1;
                            flag_branch    <= 1;
                            gregs_rd_dat   <= decoder_imm + pc;
                            pc_nxt         <= decoder_imm + pc;
                            status <= `STATUS_REG_WRITE;
                        end
                        `CPU_INSTR_GRP_JAL:    begin
                            flag_reg_write <= 1;
                            flag_branch    <= 1;
                            gregs_rd_dat   <= pc + 4;
                            pc_nxt         <= decoder_imm + pc;
                            status <= `STATUS_REG_WRITE;
                        end
                        `CPU_INSTR_GRP_JALR:   begin
                            flag_reg_write <= 1;
                            flag_branch    <= 1;
                            gregs_rd_dat   <= pc + 4;
                            pc_nxt         <= (decoder_imm + gregs_rs1_dat) & {{31{1'b1}}, 1'b0};
                            status <= `STATUS_REG_WRITE;
                        end
                        `CPU_INSTR_GRP_BCC:    begin
                            pc_nxt <= (decoder_imm + gregs_rs1_dat) & {{31{1'b1}}, 1'b0};
                            case (decoder_funct[2:0])
                                3'b000:  flag_branch <= (gregs_rs1_dat == gregs_rs2_dat);
                                3'b001:  flag_branch <= (gregs_rs1_dat != gregs_rs2_dat);
                                3'b100:  flag_branch <= (gregs_rs1_dat[31] >  gregs_rs2_dat[31]) ||
                                                        ((gregs_rs1_dat[31] == gregs_rs2_dat[31]) &&
                                                         (gregs_rs1_dat     <  gregs_rs2_dat));
                                3'b101:  flag_branch <= (gregs_rs1_dat[31] <= gregs_rs2_dat[31]) &&
                                                        ((gregs_rs1_dat[31] != gregs_rs2_dat[31]) ||
                                                         (gregs_rs1_dat     >= gregs_rs2_dat));
                                3'b110: flag_branch <= (gregs_rs1_dat <  gregs_rs2_dat);
                                3'b111: flag_branch <= (gregs_rs1_dat >= gregs_rs2_dat);
                                default:  flag_branch <= 0;
                            endcase
                            status <= `STATUS_BRANCH;
                        end
                        `CPU_INSTR_GRP_LOAD:   begin
                            flag_mem_read  <= 1;
                            flag_reg_write <= 1;
                            bus_address    <= gregs_rs1_dat + decoder_imm;
                            bus_wlen       <= `BUS_READ_32;
                            status <= `STATUS_MEM_READ;
                        end
                        `CPU_INSTR_GRP_STORE:  begin
                            flag_mem_write <= 1;
                            bus_address    <= gregs_rs1_dat + decoder_imm;
                            case (decoder_funct[2:0])
                                3'b000: bus_wlen <= `BUS_WRITE_8;
                                3'b001: bus_wlen <= `BUS_WRITE_16;
                                3'b010: bus_wlen <= `BUS_WRITE_32;
                            endcase
                            status <= `STATUS_MEM_WRITE;
                        end
                        `CPU_INSTR_GRP_ALUI:   begin
                            flag_alu   <= (decoder_funct[2:0] == 3'b010 || decoder_funct[2:0] == 3'b011) ? 0 : 1;
                            flag_reg_write <= 1;
                            alu_src_A  <= gregs_rs1_dat;
                            alu_src_B  <= (decoder_funct[2:0] == 3'b001 || decoder_funct[2:0] == 3'b101) ? {27'd0, decoder_imm[4:0]} : decoder_imm;
                            case (decoder_funct[2:0])
                                3'b000: alu_select <= `ALU_ADD;
                                3'b010: gregs_rd_dat <= (gregs_rs1_dat[31] >  decoder_imm[31]) ||
                                                       ((gregs_rs1_dat[31] == decoder_imm[31]) &&
                                                        (gregs_rs1_dat     <  decoder_imm));
                                3'b011: gregs_rd_dat <= (gregs_rs1_dat < decoder_imm);
                                3'b100: alu_select <= `ALU_XOR;
                                3'b110: alu_select <= `ALU_OR;
                                3'b111: alu_select <= `ALU_AND;
                                3'b001: alu_select <= `ALU_SLL;
                                3'b101: alu_select <= decoder_imm[10] == 0 ? `ALU_SRL : `ALU_SRA;
                            endcase
                            status <= `STATUS_ALU;
                        end
                        `CPU_INSTR_GRP_ALU:    begin
                            flag_alu <= (decoder_funct[2:0] == 3'b010 || decoder_funct[2:0] == 3'b011) ? 0 : 1;
                            flag_reg_write <= 1;
                            alu_src_A <= gregs_rs1_dat;
                            alu_src_B <= (decoder_funct[2:0] == 3'b001 || decoder_funct[2:0] == 3'b101) ? {27'd0, gregs_rs2_dat[4:0]} : gregs_rs2_dat;
                            case (decoder_funct[2:0])
                                3'b000: alu_select <= (decoder_funct[8] == 0) ? `ALU_ADD : `ALU_SUB;
                                3'b010: gregs_rd_dat <= (gregs_rs1_dat[31] >  gregs_rs2_dat[31]) ||
                                                       ((gregs_rs1_dat[31] == gregs_rs2_dat[31]) &&
                                                        (gregs_rs1_dat     <  gregs_rs2_dat));
                                3'b011: gregs_rd_dat <= (gregs_rs1_dat < gregs_rs2_dat);
                                3'b100: alu_select <= `ALU_XOR;
                                3'b110: alu_select <= `ALU_OR;
                                3'b111: alu_select <= `ALU_AND;
                                3'b001: alu_select <= `ALU_SLL;
                                3'b101: alu_select <= (decoder_funct[8] == 0) ? `ALU_SRL : `ALU_SRA;
                            endcase
                            status <= `STATUS_ALU;
                        end
                        `CPU_INSTR_GRP_FENCE:  begin
                            //TODO
                        end
                        `CPU_INSTR_GRP_E_CSR:  begin
                            //TODO
                        end
                        `CPU_INSTR_GRP_MULDIV: begin
                            //TODO()
                        end
                    endcase
                end else begin
                    status <= `STATUS_SET_FLAG;
                end
            end

            `STATUS_MEM_READ:   begin
                if (flag_mem_read) begin
                    bus_en_n = `BUS_RUN;
                    status = `STATUS_MEM_READING;
                end else begin
                    status <= `STATUS_ALU;
                end
            end
            `STATUS_MEM_READING:    begin
                if (flag_mem_read) begin
                    if (bus_ready == `BUS_STOP) begin
                        case (decoder_funct[2:0])
                            3'b000:  gregs_rd_dat <= (bus_rdata[7] == 0) ?
                                            {{24{1'b0}}, bus_rdata[7:0]} :
                                            {{24{1'b1}}, bus_rdata[7:0]};
                            3'b001:  gregs_rd_dat <= (bus_rdata[15] == 0) ?
                                            {{16{1'b0}}, bus_rdata[15:0]} :
                                            {{16{1'b1}}, bus_rdata[15:0]};
                            3'b010:  gregs_rd_dat <= bus_rdata;
                            3'b100: gregs_rd_dat <= {{24{1'b0}}, bus_rdata[7:0]};
                            3'b101: gregs_rd_dat <= {{16{1'b0}}, bus_rdata[15:0]};
                        endcase
                        status <= `STATUS_REG_WRITE;
                    end else begin
                        status <= `STATUS_MEM_READING;
                    end
                end else begin
                    status <= `STATUS_ALU;
                end
            end
            `STATUS_ALU:    begin
                if (flag_alu == 1) begin
                    alu_rst = 1;
                    status = `STATUS_ALU_2;
                end else begin
                    status <= `STATUS_REG_WRITE;
                end
            end
            `STATUS_ALU_2:  begin
                if (flag_alu == 1) begin
                    alu_rst = 0;
                    status = `STATUS_ALUING;
                end else begin
                    status <= `STATUS_REG_WRITE;
                end
            end
            `STATUS_ALUING: begin
                if (flag_alu == 1) begin
                    if (alu_ready == 1) begin
                        gregs_rd_dat <= alu_dest[31:0];
                        status <= `STATUS_REG_WRITE;
                    end else begin
                        status <= `STATUS_ALUING;
                    end
                end else begin
                    status <= `STATUS_REG_WRITE;
                end
            end
            `STATUS_REG_WRITE:  begin
                if (flag_reg_write) begin
                    gregs_wen <= 1;
                end
                status <= `STATUS_REG_WRITE_POST;
            end
            `STATUS_REG_WRITE_POST:   begin
                gregs_wen <= 0;
                status <= `STATUS_BRANCH;
            end
            `STATUS_MEM_WRITE:  begin
                if (flag_mem_write) begin
                    bus_en_n = `BUS_RUN;
                    status = `STATUS_MEM_WRITING;
                end else begin
                    status <= `STATUS_BRANCH;
                end
            end
            `STATUS_MEM_WRITING:    begin
                if (flag_mem_write) begin
                    if (bus_ready == `BUS_STOP) begin
                        status <= `STATUS_BRANCH;
                    end else begin
                        status <= `STATUS_MEM_WRITING;
                    end
                end else begin
                    status <= `STATUS_BRANCH;
                end
            end
            `STATUS_BRANCH: begin
                if (flag_branch) begin
                    pc <= pc_nxt;
                end else begin
                    pc <= pc + 4;
                end
                status <= `STATUS_INIT;
            end
            default: begin
                status = `STATUS_INIT;
            end
        endcase
    end
end


endmodule