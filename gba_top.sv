/* gba_top.sv
 *
 *  Top module for the Game Boy Advance.
 *
 *  Team N64
 */

`include "gba_core_defines.vh"
`include "gba_mmio_defines.vh"
`default_nettype none

module gba_top (
	input  logic  CLK_50M,

	input logic gba_clk,
	input logic clk_100,
	input logic clk_256,
	input logic vga_clk,

	input  logic  BTND,

	input  logic [7:0] SW,

	input  logic JA1,
	output logic JA2, JA3,

	output logic [7:0] LD,

	output logic [4:0] VGA_R, VGA_G, VGA_B,
	output logic VGA_VS, VGA_HS, VGA_DE,

	output logic AC_ADR0, AC_ADR1, AC_GPIO0, AC_MCLK, AC_SCK,
	input  logic AC_GPIO1, AC_GPIO2, AC_GPIO3,
	inout  wire  AC_SDA,

	output logic [23:0] output_wave_l,
	output logic [23:0] output_wave_r,

	output logic hblank,
	output logic vblank,
	
	input logic [15:0] buttons,
	
	output logic [31:0] CART_ADDR,
	input  logic [31:0] CART_DI,
	output logic [31:0] CART_DO,	// For writes to Backup SRAM etc.
	
	output logic CART_RD,
	output logic CART_WR,
	
	input logic CPU_PAUSE	
);


reg [31:0] cart_addr_reg;
reg cart_rd_reg;
reg cart_wr_reg;

always @(posedge gba_clk) begin
	cart_rd_reg <= 1'b0;
	cart_wr_reg <= 1'b0;

	if (bus_game_cs && !bus_write) begin
		cart_addr_reg <= bus_addr;
		cart_rd_reg <= 1'b1;
	end
	
	if (bus_game_cs && bus_write) begin
		cart_addr_reg <= bus_addr;
		cart_wr_reg <= 1'b1;
	end
end


	assign CART_ADDR = cart_addr_reg;
	assign CART_DO = bus_wdata;
	assign CART_WR = cart_wr_reg;
	assign CART_RD = cart_rd_reg;
	assign bus_game_rdata = CART_DI;

	
	// 16.776 MHz clock for GBA/memory system
	//logic gba_clk, clk_100, clk_256, vga_clk;

	//clk_wiz_0 clk0 (.clk_in1(GCLK),.gba_clk, .clk_100, .clk_256, .vga_clk);
	 

	// Buttons register output
	//logic [15:0] buttons;

	// CPU
	logic  [4:0] mode;
	(* mark_debug = "true" *) logic        nIRQ;
	logic        abort;
	logic        cpu_preemptable;

	// Interrupt signals
	logic [15:0] reg_IF, reg_IE, reg_ACK;
	logic        timer0, timer1, timer2, timer3;

	// DMA
	(* mark_debug = "true" *) logic        dmaActive;
	logic        dma0, dma1, dma2, dma3;
	logic  [3:0] disable_dma;
	logic        sound_req1, sound_req2;

	// Timer
	(* mark_debug = "true" *) logic [15:0] internal_TM0CNT_L;
	logic [15:0] internal_TM1CNT_L;
	logic [15:0] internal_TM2CNT_L;
	logic [15:0] internal_TM3CNT_L;
	logic [15:0] TM0CNT_L, TM1CNT_L, TM2CNT_L, TM3CNT_L;

	// Memory signals
	(* mark_debug = "true" *) logic [31:0] bus_addr, bus_wdata, bus_rdata;
	(* mark_debug = "true" *) logic  [1:0] bus_size;
	(* mark_debug = "true" *) logic        bus_pause, bus_write;

	// Cart bus...
	logic [31:0] bus_game_addr;
	logic [31:0] bus_game_rdata;
	logic bus_game_cs;

	logic [31:0] gfx_vram_A_addr, gfx_vram_B_addr, gfx_vram_C_addr;
	logic [31:0] gfx_vram_A_addr2, gfx_palette_bg_addr;
	logic [31:0] gfx_oam_addr, gfx_palette_obj_addr;
	logic [31:0] gfx_vram_A_data, gfx_vram_B_data, gfx_vram_C_data;
	logic [31:0] gfx_vram_A_data2, gfx_palette_bg_data;
	logic [31:0] gfx_oam_data, gfx_palette_obj_data;

	logic        FIFO_re_A, FIFO_re_B, FIFO_clr_A, FIFO_clr_B;
	logic [31:0] FIFO_val_A, FIFO_val_B;
	logic  [3:0] FIFO_size_A, FIFO_size_B;

	//logic  vblank, hblank;
	logic vcount_match;
	assign vblank = (vcount >= 8'd160);
	assign hblank = (hcount >= 9'd240);

	assign VGA_VS = vcount>=196 && vcount<200;
	assign VGA_HS = hcount>=280 && hcount<290;
	assign VGA_DE = !(vblank | hblank);
	
	//wire my_vblank = (vcount>0 && vcount<6);
	//wire my_hblank = (hcount>8 && hcount<234);
	//assign VGA_DE = !(my_vblank | my_hblank);


	assign vcount_match = (vcount == IO_reg_datas[`DISPSTAT_IDX][15:8]);

	logic [31:0] IO_reg_datas [`NUM_IO_REGS-1:0];

	logic        dsASqRst, dsBSqRst;

	// Graphics
	logic [7:0] vcount;
	logic [8:0] hcount;

	assign abort = 1'b0;
 
	// ElectronAsh.
	wire io_write;
	wire [31:0] int_reg_dout;
	wire [31:0] gfx_reg_dout;
	wire [31:0] dma_reg_dout;
	wire [31:0] timer_reg_dout;
	wire [31:0] aud_reg_dout;
	
	wire [31:0] io_reg_rdata;

    // CPU
	cpu_top cpu (
		.clock(gba_clk), .reset(BTND), .nIRQ, .pause(bus_pause | CPU_PAUSE),
		.abort, .mode, .preemptable(cpu_preemptable),
		.dmaActive, .rdata(bus_rdata), .addr(bus_addr),
		.wdata(bus_wdata), .size(bus_size), .write(bus_write)
	);

    // BRAM memory controller
	mem_top mem (
		.clock(gba_clk), .reset(BTND), .bus_addr, .bus_wdata, .bus_rdata,
		.bus_size, .bus_pause, .bus_write, .dmaActive,

		.gfx_vram_A_addr, .gfx_vram_B_addr, .gfx_vram_C_addr,
		.gfx_palette_obj_addr, .gfx_palette_bg_addr,
		.gfx_vram_A_addr2, .gfx_oam_addr,

		.gfx_vram_A_data, .gfx_vram_B_data, .gfx_vram_C_data,
		.gfx_palette_obj_data, .gfx_palette_bg_data,
		.gfx_vram_A_data2, .gfx_oam_data,

		.IO_reg_datas,

		.buttons, .vcount(vcount),
		.reg_IF, .int_acks(reg_ACK),
		.internal_TM0CNT_L, .internal_TM1CNT_L, .internal_TM2CNT_L,
		.internal_TM3CNT_L,
		.TM0CNT_L, .TM1CNT_L, .TM2CNT_L, .TM3CNT_L, .dsASqRst, .dsBSqRst,

		.FIFO_re_A, .FIFO_re_B, .FIFO_clr_A, .FIFO_clr_B, .FIFO_val_A,
		.FIFO_val_B, .FIFO_size_A, .FIFO_size_B,
		.vblank, .hblank, .vcount_match,
		
		.bus_game_addr( bus_game_addr ),		// output [31:0] bus_game_addr
		.bus_game_rdata( bus_game_rdata ),	// input [31:0] bus_game_rdata
		
		.bus_game_cs( bus_game_cs ),			// output bus_game_cs
		
		.io_write( io_write ),					// output io_write
		
		.io_reg_rdata( io_reg_rdata ),		// input [31:0] io_reg_rdata (from all of the other sub-modules).
		
		.bus_addr_lat1( bus_addr_lat1 )		// output [31:0] bus_addr_lat1
	);
	wire [31:0] bus_addr_lat1;

	interrupt_controller intc (
		.clock(gba_clk), .reset(BTND), .cpu_mode(mode), .nIRQ,
		.ime(IO_reg_datas[`IME_IDX][0]), .reg_IF, .reg_ACK,
		.reg_IE(IO_reg_datas[`IE_IDX][15:0]),
		.vcount, .hcount, .set_vcount(IO_reg_datas[`DISPSTAT_IDX][15:8]),
		.timer0, .timer1,
		.timer2, .timer3, .serial(1'b0), .keypad(1'b0),
		.game_pak(1'b0), .dma0, .dma1, .dma2, .dma3,
		
		.io_addr(bus_addr_lat1[11:0]),		// input [11:0] io_addr
		.io_write(io_write),				// input io_write
		
		.bus_wdata( bus_wdata ),		// input [31:0] bus_wdata
		.io_reg_rdata( io_reg_rdata )	// inout [31:0] io_reg_rdata
	);
	
	graphics_system gfx (
		.gfx_vram_A_addr, .gfx_vram_B_addr, .gfx_vram_C_addr,
		.gfx_oam_addr, .gfx_palette_bg_addr,
		.gfx_palette_obj_addr, .gfx_vram_A_addr2,

		.gfx_vram_A_data, .gfx_vram_B_data, .gfx_vram_C_data,
		.gfx_oam_data, .gfx_palette_bg_data,
		.gfx_palette_obj_data, .gfx_vram_A_data2,

		.IO_reg_datas, .graphics_clock(gba_clk),
		.vga_clock(vga_clk),
		.reset(BTND), .vcount, .hcount,
		.VGA_R, .VGA_G, .VGA_B,/*, .VGA_HS, .VGA_VS*/
		
		.io_addr(bus_addr_lat1[11:0]),		// input [11:0] io_addr
		.io_write(io_write),				// input io_write
		
		.bus_wdata( bus_wdata ),		// input [31:0] bus_wdata
		.io_reg_rdata( io_reg_rdata )	// inout [31:0] io_reg_rdata
	);

	dma_top dma (
		.clk(gba_clk),
		.rst_b(~BTND),
		.registers(IO_reg_datas),
		.addr(bus_addr),
		.rdata(bus_rdata),
		.wdata(bus_wdata),
		.size(bus_size),
		.wen(bus_write),
		.active(dmaActive),
		.disable_dma(),
		.irq0(dma0),
		.irq1(dma1),
		.irq2(dma2),
		.irq3(dma3),
		.mem_wait(bus_pause),
		.sound_req1(sound_req1),
		.sound_req2(sound_req2),
		.vcount(vcount),
		.hcount({7'd0, hcount}),
		.cpu_preemptable(cpu_preemptable),
		
		.io_addr(bus_addr_lat1[11:0]),		// input [11:0] io_addr
		.io_write(io_write),				// input io_write
		//.bus_wdata( bus_wdata ),		// input [31:0] bus_wdata. (not needed, as the DMA module already has this input)
		
		.io_reg_rdata( io_reg_rdata )	// inout [31:0] io_reg_rdata
	);

	timer_top timers (
		.clock_16(gba_clk), .reset(BTND), .IO_reg_datas,
		.internal_TM0CNT_L, .internal_TM1CNT_L, .internal_TM2CNT_L,
		.internal_TM3CNT_L,
		.TM0CNT_L, .TM1CNT_L, .TM2CNT_L, .TM3CNT_L,
		.genIRQ0(timer0), .genIRQ1(timer1), .genIRQ2(timer2),
		.genIRQ3(timer3),
		
		.io_addr(bus_addr_lat1[11:0]),		// input [11:0] io_addr
		.io_write(io_write),				// input io_write
		.bus_wdata( bus_wdata ),		// input [31:0] bus_wdata
		
		.io_reg_rdata( io_reg_rdata )	// inout [31:0] io_reg_rdata
	);

	gba_audio_top audio (
		.clk_100(clk_100), .clk_256, .gba_clk, .reset(BTND), .AC_ADR0, .AC_ADR1,
		.AC_GPIO0, .AC_GPIO1, .AC_GPIO2, .AC_GPIO3, .AC_MCLK, .AC_SCK,
		.AC_SDA, .IO_reg_datas, .sound_req1, .sound_req2,
		.internal_TM0CNT_L, .internal_TM1CNT_L,
		.dsASqRst, .dsBSqRst, .SW(SW[0]),
		
		.output_wave_l( output_wave_l ),
		.output_wave_r( output_wave_r ),

		.FIFO_re_A, .FIFO_re_B, .FIFO_clr_A, .FIFO_clr_B, .FIFO_val_A,
		.FIFO_val_B, .FIFO_size_A, .FIFO_size_B,
		
		.io_addr(bus_addr_lat1[11:0]),		// input [11:0] io_addr
		.io_write(io_write),				// input io_write
		.bus_wdata( bus_wdata ),		// input [31:0] bus_wdata
		
		.io_reg_rdata( io_reg_rdata )	// inout [31:0] io_reg_rdata
	);
	

	/*
    // Interface for SNES controller
    controller cont (.clock(CLK_50M), .reset(BTND), .data_latch(JA2),
                     .data_clock(JA3), .serial_data(JA1), .buttons);
	*/

	/*
    // Controller for debug output on LEDs
    led_controller led (.led_reg0(IO_reg_datas[`LED_REG0_IDX]),
                        .led_reg1(IO_reg_datas[`LED_REG1_IDX]),
                        .led_reg2(IO_reg_datas[`LED_REG2_IDX]),
                        .led_reg3(IO_reg_datas[`LED_REG3_IDX]),
                        .buttons, .LD, .SW);
	*/

endmodule: gba_top

// LED controller for mapping debug output
/*
module led_controller (
    input  logic [7:0] SW,
    input  logic [31:0] led_reg0, led_reg1, led_reg2, led_reg3,
    input  logic [15:0] buttons,
    output logic [7:0] LD);

    always_comb begin
        case (SW)
            8'h0: LD = led_reg0[7:0];
            8'h1: LD = led_reg0[15:8];
            8'h2: LD = led_reg0[23:16];
            8'h3: LD = led_reg0[31:24];
            8'h4: LD = led_reg1[7:0];
            8'h5: LD = led_reg1[15:8];
            8'h6: LD = led_reg1[23:16];
            8'h7: LD = led_reg1[31:24];
            8'h8: LD = led_reg2[7:0];
            8'h9: LD = led_reg2[15:8];
            8'hA: LD = led_reg2[23:16];
            8'hB: LD = led_reg2[31:24];
            8'hC: LD = led_reg3[7:0];
            8'hD: LD = led_reg3[15:8];
            8'hE: LD = led_reg3[23:16];
            8'hF: LD = led_reg3[31:24];
            default: LD = (SW[7]) ? ~buttons[15:8] : ~buttons[7:0];
        endcase
    end
endmodule: led_controller
*/

`default_nettype wire
