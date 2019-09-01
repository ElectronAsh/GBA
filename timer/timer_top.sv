`default_nettype none
`include "../gba_mmio_defines.vh"
`include "../gba_core_defines.vh"

module timer_top (
	input logic clock_16,
	input logic reset,
	input logic [31:0] IO_reg_datas [`NUM_IO_REGS-1:0],
	input logic [15:0] TM0CNT_L,
	input logic [15:0] TM1CNT_L,
	input logic [15:0] TM2CNT_L,
	input logic [15:0] TM3CNT_L,
	output logic genIRQ0,
	output logic genIRQ1,
	output logic genIRQ2,
	output logic genIRQ3,
	output logic [15:0] internal_TM0CNT_L,
	output logic [15:0] internal_TM1CNT_L,
	output logic [15:0] internal_TM2CNT_L,
	output logic [15:0] internal_TM3CNT_L,

	input  logic [11:0] io_addr,
	input  logic io_write,
	
	input  logic [31:0] bus_wdata,

	inout logic [31:0] io_reg_rdata
);

    logic [15:0] TM0CNT_H;
    logic [15:0] TM1CNT_H;
    logic [15:0] TM2CNT_H, TM3CNT_H;

    assign TM0CNT_H = IO_reg_datas[`TM0CNT_L_IDX][31:16];
    assign TM1CNT_H = IO_reg_datas[`TM1CNT_L_IDX][31:16];
    assign TM2CNT_H = IO_reg_datas[`TM2CNT_L_IDX][31:16];
    assign TM3CNT_H = IO_reg_datas[`TM3CNT_L_IDX][31:16];

	// Timer regs...
	logic [31:0] TM0CNT_L_REG;
	logic [31:0] TM0CNT_H_REG;
	logic [31:0] TM1CNT_L_REG;
	logic [31:0] TM1CNT_H_REG;
	logic [31:0] TM2CNT_L_REG;
	logic [31:0] TM2CNT_H_REG;
	logic [31:0] TM3CNT_L_REG;
	logic [31:0] TM3CNT_H_REG;
	 
always_ff @(posedge clock_16 or posedge reset)
if (reset) begin

end
else begin
	if (io_write) begin
		case ( io_addr>>2 )
		`TM0CNT_L_IDX: TM0CNT_L_REG <= bus_wdata;
		`TM0CNT_H_IDX: TM0CNT_H_REG <= bus_wdata;
		`TM1CNT_L_IDX: TM1CNT_L_REG <= bus_wdata;
		`TM1CNT_H_IDX: TM1CNT_H_REG <= bus_wdata;
		`TM2CNT_L_IDX: TM2CNT_L_REG <= bus_wdata;
		`TM2CNT_H_IDX: TM2CNT_H_REG <= bus_wdata;
		`TM3CNT_L_IDX: TM3CNT_L_REG <= bus_wdata;
		`TM3CNT_H_IDX: TM3CNT_H_REG <= bus_wdata;
		default:;
		endcase
	end
end
	 
always_comb begin
		case ( io_addr>>2 )
		`TM0CNT_L_IDX: io_reg_rdata = TM0CNT_L_REG;
		`TM0CNT_H_IDX: io_reg_rdata = TM0CNT_H_REG;
		`TM1CNT_L_IDX: io_reg_rdata = TM1CNT_L_REG;
		`TM1CNT_H_IDX: io_reg_rdata = TM1CNT_H_REG;
		`TM2CNT_L_IDX: io_reg_rdata = TM2CNT_L_REG;
		`TM2CNT_H_IDX: io_reg_rdata = TM2CNT_H_REG;
		`TM3CNT_L_IDX: io_reg_rdata = TM3CNT_L_REG;
		`TM3CNT_H_IDX: io_reg_rdata = TM3CNT_H_REG;
		default: io_reg_rdata = 32'hzzzzzzzz;		// MUST be set as High-Z, to prevent contention with the other modules during reads! ElectronAsh.
	endcase
end
	 
    timer timer0(
        .clock_16,
        .reset,
        .TMxCNT_L(TM0CNT_L),
        .internal_TMxCNT_L(internal_TM0CNT_L),
        .TMxCNT_H(TM0CNT_H),
        .genIRQ(genIRQ0),
        .prev_timer(16'hFFFF));

     timer timer1(
        .clock_16,
        .reset,
        .TMxCNT_L(TM1CNT_L),
        .internal_TMxCNT_L(internal_TM1CNT_L),
        .TMxCNT_H(TM1CNT_H),
        .genIRQ(genIRQ1),
        .prev_timer(TM0CNT_L));

     timer timer2(
        .clock_16,
        .reset,
        .TMxCNT_L(TM2CNT_L),
        .internal_TMxCNT_L(internal_TM2CNT_L),
        .TMxCNT_H(TM2CNT_H),
        .genIRQ(genIRQ2),
        .prev_timer(TM1CNT_L));

     timer timer3(
        .clock_16,
        .reset,
        .TMxCNT_L(TM3CNT_L),
        .internal_TMxCNT_L(internal_TM3CNT_L),
        .TMxCNT_H(TM3CNT_H),
        .genIRQ(genIRQ3),
        .prev_timer(TM2CNT_L));

endmodule: timer_top

`default_nettype wire

