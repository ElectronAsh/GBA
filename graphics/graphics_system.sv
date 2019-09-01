`include "../gba_core_defines.vh"
`include "../gba_mmio_defines.vh"
`default_nettype none

module graphics_system (
	output  logic [31:0] gfx_vram_A_addr, gfx_vram_B_addr, gfx_vram_C_addr,
	output  logic [31:0] gfx_oam_addr, gfx_palette_bg_addr, gfx_palette_obj_addr,
	output  logic [31:0] gfx_vram_A_addr2,

	input  logic [31:0] gfx_vram_A_data, gfx_vram_B_data, gfx_vram_C_data,
	input  logic [31:0] gfx_oam_data, gfx_palette_bg_data, gfx_palette_obj_data,
	input  logic [31:0] gfx_vram_A_data2,

	input  logic [31:0] IO_reg_datas [`NUM_IO_REGS-1:0],
	input  logic        graphics_clock, vga_clock,
	input  logic        reset,

	output logic [7:0] vcount,
	output logic [8:0] hcount,
	output logic [4:0] VGA_R, VGA_G, VGA_B,
	output logic        VGA_HS,
	output logic        VGA_VS,
	
	input  logic [11:0] io_addr,
	input  logic io_write,
	
	input logic [31:0] bus_wdata,
	
	inout logic [31:0] io_reg_rdata
);

	//module instantiations
	logic wen, toggle;
	logic [14:0] graphics_color, vga_color;
	logic [16:0] graphics_addr, vga_addr;
	logic [14:0] buffer0_dout, buffer1_dout;
	logic [16:0] buffer0_address, buffer1_address;
	logic [14:0] buffer0_din, buffer1_din;
	logic buffer0_ce, buffer1_ce;
	logic buffer0_we, buffer1_we;


	// Graphics regs...
	logic [31:0] DISPCNT_REG;
	logic [31:0] DISPSTAT_REG;
	logic [31:0] VCOUNT_REG;
	logic [31:0] BG0CNT_REG;
	logic [31:0] BG1CNT_REG;
	logic [31:0] BG2CNT_REG;
	logic [31:0] BG3CNT_REG;

	logic [31:0] BG0HOFS_REG;
	logic [31:0] BG0VOFS_REG;
	logic [31:0] BG1HOFS_REG;
	logic [31:0] BG1VOFS_REG;
	logic [31:0] BG2HOFS_REG;
	logic [31:0] BG2VOFS_REG;
	logic [31:0] BG3HOFS_REG;
	logic [31:0] BG3VOFS_REG;

	logic [31:0] BG2PA_REG;
	logic [31:0] BG2PB_REG;
	logic [31:0] BG2PC_REG;
	logic [31:0] BG2PD_REG;
	logic [31:0] BG2X_L_REG;
	logic [31:0] BG2X_H_REG;
	logic [31:0] BG2Y_L_REG;
	logic [31:0] BG2Y_H_REG;

	logic [31:0] BG3PA_REG;
	logic [31:0] BG3PB_REG;
	logic [31:0] BG3PC_REG;
	logic [31:0] BG3PD_REG;
	logic [31:0] BG3X_L_REG;
	logic [31:0] BG3X_H_REG;
	logic [31:0] BG3Y_L_REG;
	logic [31:0] BG3Y_H_REG;

	logic [31:0] WIN0H_REG;
	logic [31:0] WIN1H_REG;
	logic [31:0] WIN0V_REG;
	logic [31:0] WIN1V_REG;
	logic [31:0] WININ_REG;
	logic [31:0] WINOUT_REG;
	logic [31:0] MOSAIC_REG;

	logic [31:0] BLDCNT_REG;
	logic [31:0] BLDALPHA_REG;
	logic [31:0] BLDY_REG;
	 
always_ff @(posedge graphics_clock or posedge reset)
if (reset) begin

end
else begin
	if (io_write) begin
		case ( io_addr >> 2 )
		`DISPCNT_IDX: DISPCNT_REG <= bus_wdata;
		`VCOUNT_IDX: VCOUNT_REG <= bus_wdata;
		`BG0CNT_IDX: BG0CNT_REG <= bus_wdata;
		`BG1CNT_IDX: BG1CNT_REG <= bus_wdata;
		`BG2CNT_IDX: BG2CNT_REG <= bus_wdata;
		`BG3CNT_IDX: BG3CNT_REG <= bus_wdata;

		`BG0HOFS_IDX: BG0HOFS_REG <= bus_wdata;
		`BG0VOFS_IDX: BG0VOFS_REG <= bus_wdata;
		`BG1HOFS_IDX: BG1HOFS_REG <= bus_wdata;
		`BG1VOFS_IDX: BG1VOFS_REG <= bus_wdata;
		`BG2HOFS_IDX: BG2HOFS_REG <= bus_wdata;
		`BG2VOFS_IDX: BG2VOFS_REG <= bus_wdata;
		`BG3HOFS_IDX: BG3HOFS_REG <= bus_wdata;
		`BG3VOFS_IDX: BG3VOFS_REG <= bus_wdata;

		`BG2PA_IDX: BG2PA_REG <= bus_wdata;
		`BG2PB_IDX: BG2PB_REG <= bus_wdata;
		`BG2PC_IDX: BG2PC_REG <= bus_wdata;
		`BG2PD_IDX: BG2PD_REG <= bus_wdata;
		`BG2X_L_IDX: BG2X_L_REG <= bus_wdata;
		`BG2X_H_IDX: BG2X_H_REG <= bus_wdata;
		`BG2Y_L_IDX: BG2Y_L_REG <= bus_wdata;
		`BG2Y_H_IDX: BG2Y_H_REG <= bus_wdata;

		`BG3PA_IDX: BG3PA_REG <= bus_wdata;
		`BG3PB_IDX: BG3PB_REG <= bus_wdata;
		`BG3PC_IDX: BG3PC_REG <= bus_wdata;
		`BG3PD_IDX: BG3PD_REG <= bus_wdata;
		`BG3X_L_IDX: BG3X_L_REG <= bus_wdata;
		`BG3X_H_IDX: BG3X_H_REG <= bus_wdata;
		`BG3Y_L_IDX: BG3Y_L_REG <= bus_wdata;
		`BG3Y_H_IDX: BG3Y_H_REG <= bus_wdata;

		`WIN0H_IDX: WIN0H_REG <= bus_wdata;
		`WIN1H_IDX: WIN1H_REG <= bus_wdata;
		`WIN0V_IDX: WIN0V_REG <= bus_wdata;
		`WIN1V_IDX: WIN1V_REG <= bus_wdata;
		`WININ_IDX: WININ_REG <= bus_wdata;
		`WINOUT_IDX: WINOUT_REG <= bus_wdata;
		`MOSAIC_IDX: MOSAIC_REG <= bus_wdata;

		`BLDCNT_IDX: BLDCNT_REG <= bus_wdata;
		`BLDALPHA_IDX: BLDALPHA_REG <= bus_wdata;
		`BLDY_IDX: BLDY_REG <= bus_wdata;
		default:;
		endcase
	end
end

always_comb begin
		case ( io_addr >> 2 )
		`DISPCNT_IDX: io_reg_rdata = DISPCNT_REG;

		`VCOUNT_IDX: io_reg_rdata = VCOUNT_REG;
       //`VCOUNT_IDX: io_reg_rdata = {vcount,  13'b0000000000000, vcount_match, hblank, vblank};

		`BG0CNT_IDX: io_reg_rdata = BG0CNT_REG;
		`BG1CNT_IDX: io_reg_rdata = BG1CNT_REG;
		`BG2CNT_IDX: io_reg_rdata = BG2CNT_REG;
		`BG3CNT_IDX: io_reg_rdata = BG3CNT_REG;

		`BG0HOFS_IDX: io_reg_rdata = BG0HOFS_REG;
		`BG0VOFS_IDX: io_reg_rdata = BG0VOFS_REG;
		`BG1HOFS_IDX: io_reg_rdata = BG1HOFS_REG;
		`BG1VOFS_IDX: io_reg_rdata = BG1VOFS_REG;
		`BG2HOFS_IDX: io_reg_rdata = BG2HOFS_REG;
		`BG2VOFS_IDX: io_reg_rdata = BG2VOFS_REG;
		`BG3HOFS_IDX: io_reg_rdata = BG3HOFS_REG;
		`BG3VOFS_IDX: io_reg_rdata = BG3VOFS_REG;

		`BG2PA_IDX: io_reg_rdata = BG2PA_REG;
		`BG2PB_IDX: io_reg_rdata = BG2PB_REG;
		`BG2PC_IDX: io_reg_rdata = BG2PC_REG;
		`BG2PD_IDX: io_reg_rdata = BG2PD_REG;
		`BG2X_L_IDX: io_reg_rdata = BG2X_L_REG;
		`BG2X_H_IDX: io_reg_rdata = BG2X_H_REG;
		`BG2Y_L_IDX: io_reg_rdata = BG2Y_L_REG;
		`BG2Y_H_IDX: io_reg_rdata = BG2Y_H_REG;

		`BG3PA_IDX: io_reg_rdata = BG3PA_REG;
		`BG3PB_IDX: io_reg_rdata = BG3PB_REG;
		`BG3PC_IDX: io_reg_rdata = BG3PC_REG;
		`BG3PD_IDX: io_reg_rdata = BG3PD_REG;
		`BG3X_L_IDX: io_reg_rdata = BG3X_L_REG;
		`BG3X_H_IDX: io_reg_rdata = BG3X_H_REG;
		`BG3Y_L_IDX: io_reg_rdata = BG3Y_L_REG;
		`BG3Y_H_IDX: io_reg_rdata = BG3Y_H_REG;

		`WIN0H_IDX: io_reg_rdata = WIN0H_REG;
		`WIN1H_IDX: io_reg_rdata = WIN1H_REG;
		`WIN0V_IDX: io_reg_rdata = WIN0V_REG;
		`WIN1V_IDX: io_reg_rdata = WIN1V_REG;
		`WININ_IDX: io_reg_rdata = WININ_REG;
		`WINOUT_IDX: io_reg_rdata = WINOUT_REG;
		`MOSAIC_IDX: io_reg_rdata = MOSAIC_REG;

		`BLDCNT_IDX: io_reg_rdata = BLDCNT_REG;
		`BLDALPHA_IDX: io_reg_rdata = BLDALPHA_REG;
		`BLDY_IDX: io_reg_rdata = BLDY_REG;
		default: io_reg_rdata = 32'hzzzzzzzz;		// MUST be set as High-Z, to prevent contention with the other modules during reads! ElectronAsh.
	endcase
end

    //dbl_buffer buffers
	/*
	dbl_buffer_bram0 buf0 (
		.clka(vga_clock),
		.addra(buffer0_address),
		.dina(buffer0_din),
		.douta(buffer0_dout),
		.ena(buffer0_ce),
		.wea(buffer0_we)
	);
									
    dbl_buffer_bram1 buf1 (
		.clka(vga_clock),
		.addra(buffer1_address),
		.dina(buffer1_din),
		.douta(buffer1_dout),
		.ena(buffer1_ce),
		.wea(buffer1_we)
	);*/
	
	buf0	buf0 (
		.clock ( vga_clock ),
		.address ( buffer0_address ),
		.data ( buffer0_din ),
		.wren ( buffer0_ce && buffer0_we ),
		.q ( buffer0_dout )
	);

	buf0	buf1 (
		.clock ( vga_clock ),
		.address ( buffer1_address ),
		.data ( buffer1_din ),
		.wren ( buffer1_ce && buffer1_we ),
		.q ( buffer1_dout )
	);

    //interface between graphics and dbl_buffer
    dblbuffer_driver driver(.toggle, .wen, .graphics_clock, .vcount, .hcount,
                            .graphics_addr, .clk(vga_clock), .rst_b(~reset));

/*
	double_buffer video_buf
	(
		.ap_clk(vga_clock) ,					// input  ap_clk
		.ap_rst_n(~reset) ,					// input  ap_rst_n
		.graphics_addr(graphics_addr) ,	// input [16:0] graphics_addr
		.graphics_color(graphics_color) ,// input [14:0] graphics_color
		.toggle(toggle) ,						// input  toggle
		.vga_addr(vga_addr) ,				// input [16:0] vga_addr
		.vga_color(vga_color) ,				// output [14:0] vga_color
		.wen(wen) ,								// input [0:0] wen
		.buffer0_address(buffer0_address) ,	// output [16:0] buffer0_address
		.buffer0_din(buffer0_din) ,		// output [14:0] buffer0_din
		.buffer0_dout(buffer0_dout) ,		// input [14:0] buffer0_dout
		.buffer0_ce(buffer0_ce) ,			// output  buffer0_ce
		.buffer0_we(buffer0_we) ,			// output  buffer0_we
		.buffer1_address(buffer1_address) ,	// output [16:0] buffer1_address
		.buffer1_din(buffer1_din) ,		// output [14:0] buffer1_din
		.buffer1_dout(buffer1_dout) ,		// input [14:0] buffer1_dout
		.buffer1_ce(buffer1_ce) ,			// output  buffer1_ce
		.buffer1_we(buffer1_we) 			// output  buffer1_we
	);
*/
	 
	//vga
	//vga_top video(.clock(vga_clock), .reset(reset), .data(vga_color), .addr(vga_addr), .VGA_R, .VGA_G, .VGA_B, .VGA_HS, .VGA_VS);
	vga_top video(.clock(vga_clock), .reset(reset), .data(vga_color), .addr(vga_addr), .VGA_HS, .VGA_VS);	// TESTING !!

	assign VGA_R = graphics_color[4:0];
	assign VGA_G = graphics_color[9:5];
	assign VGA_B = graphics_color[14:10];
	
	
	//graphics
	graphics_top gfx(
		.clock(graphics_clock),	// input logic
		.reset(reset),				// input logic
		.gfx_vram_A_data,			// input logic [31:0]
		.gfx_vram_B_data,			// input logic [31:0]
		.gfx_vram_C_data,			// input logic [31:0]
		.gfx_oam_data,				// input logic [31:0]
		.gfx_palette_bg_data,	// input logic [31:0]
		.gfx_palette_obj_data,	// input logic [31:0]
		.gfx_vram_A_data2,		// input logic [31:0]
		
		.gfx_vram_A_addr,			// output logic [31:0]
		.gfx_vram_B_addr,			// output logic [31:0]
		.gfx_vram_C_addr,			// output logic [31:0]
		.gfx_oam_addr,				// output logic [31:0]
		.gfx_palette_bg_addr,	// output logic [31:0]
		.gfx_palette_obj_addr,	// output logic [31:0]
		.gfx_vram_A_addr2,		// output logic [31:0]
		.registers(IO_reg_datas),		// output logic [31:0] (array?)
		.output_color(graphics_color)	// output logic [15:0]
	);

endmodule: graphics_system

module dblbuffer_driver(
	input logic clk,
	input logic rst_b,

	input logic graphics_clock,

	output logic toggle,
	output logic wen,
	output logic [16:0] graphics_addr,
	output logic [7:0] vcount,
	output logic [8:0] hcount
);

    assign vcount = row;
    assign hcount = col;

    dbdriver_counter #(20, 842687) toggler(.clk, .rst_b, .en(1'b1), .clear(1'b0), .last(toggle), .Q());

    logic [18:0] timer;
    logic [7:0] row;
    logic [8:0] col;

    logic step_row;
    logic next_frame;
    logic step;
    assign step = timer[1] & timer[0];
    dbdriver_counter #(19, 280895) sync(.clk(graphics_clock), .en(1'b1), .clear(1'b0), .rst_b, .last(next_frame), .Q(timer));
    dbdriver_counter #(16, 38399) addrs(.clk(graphics_clock), .en(wen & step), .clear(next_frame & step), .rst_b, .last(), .Q(graphics_addr));

    dbdriver_counter #(8, 227) rows(.clk(graphics_clock), .en(step_row & step), .clear(next_frame & step), .rst_b, .last(), .Q(row));
    dbdriver_counter #(9, 307) cols(.clk(graphics_clock), .en(step), .clear(next_frame & step), .rst_b, .last(step_row), .Q(col));

    assign wen = row < 8'd160 && col < 9'd240;

endmodule

module dbdriver_counter
    #(
    parameter WIDTH=18,
    parameter MAX = 210671
    )
    (
    input logic clk,
    input logic rst_b,
    input logic en,
    input logic clear,
    output logic [WIDTH-1:0] Q,
    output logic last
    );

    assign last = Q == MAX;

    logic [WIDTH-1:0] next;

    always_comb begin
        if(clear) begin
            next = 0;
        end
        else if(~en) begin
            next = Q;
        end
        else if(last) begin
            next = 0;
        end
        else begin
            next = Q + 1;
        end
    end

    always_ff @(posedge clk, negedge rst_b) begin
        if(~rst_b) begin
            Q <= 0;
        end
        else begin
            Q <= next;
        end
    end
endmodule

`default_nettype wire
