// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.
// 
// MiSTer port: Copyright (C) 2017,2018 Sorgelig 

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR
);

assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_USER  = downloading;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[8] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[8] ? 8'd9  : 8'd3;

assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;


`include "build_id.v"
parameter CONF_STR = {
	"GBA;;",
	"-;",
	"F,GBABIN;",
	"-;",
	"-;",
	"-;",
	"O4,Video Region,NTSC,PAL;",
	"O8,Aspect ratio,4:3,16:9;",
	"O9B,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"-;",
	"O6,Swap Joypads,No,Yes;",
	"-;",
	"R0,Reset;",
	"J,A,B,X,Y,Select,Start,L,R;",
	"V,v0.10.",`BUILD_DATE
};

wire [15:0] joystick_0;
wire [15:0] joystick_1;

wire [1:0] buttons;

wire [31:0] status;

wire arm_reset = status[0];

wire [7:0] rom_type = (status[3:2]==0) ? 8'd0 :	// LoROM.
							 (status[3:2]==1) ? 8'd1 :	// HiROM.
							                    8'd5;	// ExHiROM.
													  
//rom_config_byte
//wire [7:0] rom_type = (status[3:2]==0) ? 0 :	// Auto.
//							 (status[3:2]==1) ? 0 :		// LoROM.
//							 (status[3:2]==2) ? 1 :		// HiROM.
//							                    5;		// ExHiROM.

wire PAL = status[4];
wire MOUSE_MODE = status[5];

wire joy_swap = status[6];

wire forced_scandoubler;
wire ps2_kbd_clk, ps2_kbd_data;
wire [10:0] ps2_key;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk16),
	.HPS_BUS(HPS_BUS),
   .conf_str(CONF_STR),

   .buttons(buttons),
   .forced_scandoubler(forced_scandoubler),

   .joystick_0(joystick_0),
   .joystick_1(joystick_1),

   .status(status),

	.ioctl_download(downloading),
	.ioctl_wr(loader_clk),
	.ioctl_dout(loader_input),
	.ioctl_wait(0),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

   .ps2_key(ps2_key),
	
	.ps2_kbd_led_use(0),
	.ps2_kbd_led_status(0)
);



wire clock_locked;
wire clk85;
wire clk16;
wire clk100;
wire clk256;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk85),
	.outclk_1(SDRAM_CLK),
	.outclk_2(clk16),
	.outclk_3(clk100),
	.outclk_4(clk256),
	.locked(clock_locked)
);


// reset after download
reg [7:0] download_reset_cnt;
wire download_reset = download_reset_cnt != 0;
always @(posedge CLK_50M) begin
	if(downloading) download_reset_cnt <= 8'd255;
	else if(download_reset_cnt != 0) download_reset_cnt <= download_reset_cnt - 8'd1;
end

// hold machine in reset until first download starts
reg init_reset;
always @(posedge CLK_50M) begin
	if(!clock_locked) init_reset <= 1'b1;
	else if(downloading) init_reset <= 1'b0;
end

 
wire  [8:0] cycle;
wire  [8:0] scanline;
wire [15:0] sample;
wire  [5:0] color;
wire        joypad_strobe;
wire  [1:0] joypad_clock;
wire [21:0] memory_addr;
wire        memory_read_cpu, memory_read_ppu;

wire        memory_write = 1'b0;

wire  [7:0] memory_din_cpu, memory_din_ppu;
reg   [7:0] joypad_bits, joypad_bits2;
reg   [1:0] last_joypad_clock;

  
// Loader
wire [7:0] loader_input;
wire       loader_clk;
reg [21:0] loader_addr;
wire [7:0] loader_write_data = loader_input;
wire loader_reset = !download_reset; //loader_conf[0];
wire loader_write = loader_clk;
wire [31:0] loader_flags;


reg led_blink;
always @(posedge clk16) begin
	int cnt = 0;
	cnt <= cnt + 1;
	if(cnt == 10000000) begin
		cnt <= 0;
		led_blink <= ~led_blink;
	end;
end

// NES is clocked at every 4th cycle.
reg [1:0] nes_ce;
always @(posedge clk16) nes_ce <= nes_ce + 1'd1;


// loader_write -> clock when data available
reg loader_write_mem;
reg [7:0] loader_write_data_mem;
reg [21:0] loader_addr_mem;

reg loader_write_triggered;

reg [7:0] rom_config_byte;
reg [3:0] rom_size;
reg [3:0] ram_size;

always @(posedge clk16) begin
	if (loader_reset) begin
		loader_addr <= 0;
		rom_size <= 4'hC;
		ram_size <= 4'h0;
	end
	else begin
		if (loader_clk) begin
			loader_addr <= loader_addr + 1'd1;
		end
	end

	if(loader_write) begin
		loader_write_triggered <= 1'b1;
		loader_addr_mem <= loader_addr;
		loader_write_data_mem <= loader_write_data;
		if (   ((rom_type==8'd0) && ({2'b00, loader_addr} == 24'h07FD7))
		    || ((rom_type==8'd1) && ({2'b00, loader_addr} == 24'h0FFD7)))
			rom_size <= loader_write_data[3:0];
		if (   ((rom_type==8'd0) && ({2'b00, loader_addr} == 24'h07FD8))
		    || ((rom_type==8'd1) && ({2'b00, loader_addr} == 24'h0FFD8)))
			ram_size <= loader_write_data[3:0];
	end

	if(nes_ce == 3) begin
		loader_write_mem <= loader_write_triggered;
		if (loader_addr_mem==8'h15) rom_config_byte <= loader_write_data;
		if(loader_write_triggered)
			loader_write_triggered <= 1'b0;
	end
end

/*
wire [21:0] cart_read_addr = (!CART_SRAM_CE_N && !CART_SRAM_OE_N) ? CART_SRAM_ADDR :
																						  CART_SRAM2_ADDR;
*/

assign SDRAM_CKE         = 1'b1;

sdram sdram
(
	// interface to the MT48LC16M16 chip
	.sd_data     	( SDRAM_DQ                 ),
	.sd_addr     	( SDRAM_A                  ),
	.sd_dqm      	( {SDRAM_DQMH, SDRAM_DQML} ),
	.sd_cs       	( SDRAM_nCS                ),
	.sd_ba       	( SDRAM_BA                 ),
	.sd_we       	( SDRAM_nWE                ),
	.sd_ras      	( SDRAM_nRAS               ),
	.sd_cas      	( SDRAM_nCAS               ),

	// system interface
	.clk      		( clk85         				),
	
	.clkref      	( nes_ce[1]         			),
	
	.init         	( !clock_locked     			),

	// cpu/chipset interface
	.addr     		( downloading ? {3'b000, loader_addr_mem} : {3'b000, cart_read_addr} ),
	.we       		( memory_write || loader_write_mem	),
	.din       		( downloading ? loader_write_data_mem : 8'h00 ),

	.oeA         	( !downloading && !reset_snes && !CART_SRAM_CE_N && !CART_SRAM_OE_N ),
	.doutA       	( memory_din_cpu ),
	
	.oeB         	( 1'b0 )
//	.doutB       	( memory_din_ppu  ),
);

wire downloading;


wire [7:0] SW = 8'b00000000;
wire JA1;
wire JA2;
wire JA3;
wire [7:0] LD;

wire AC_ADR0;
wire AC_ADR1;
wire AC_GPIO0;
wire AC_GPIO1;
wire AC_GPIO2;
wire AC_GPIO3;
wire AC_MCLK;
wire AC_SCK;
wire AC_SDA;

wire [4:0] R;
wire [4:0] G;
wire [4:0] B;
wire HSYNC;
wire VSYNC;
wire HBLANK = gba_hblank;	// Kludge!
wire VBLANK = gba_vblank;	// Kludge!

wire [23:0] output_wave_l;
wire [23:0] output_wave_r;

wire gba_hblank;
wire gba_vblank;

assign AUDIO_L = output_wave_l[23:8];
assign AUDIO_R = output_wave_r[23:8];

wire [15:0] gba_buttons = joystick_0;

wire reset_gba = init_reset || buttons[1] || arm_reset || download_reset;

gba_top gba_top_inst
(
	.gba_clk(clk16),		// 16.776 MHz.
	
	.clk_100(clk100),		// ?
	.clk_256(clk256),		// ?
	
	.vga_clk(CLK_50M),	// 50.33 MHz.
	
	.BTND(reset_gba) ,	// input  BTND (active HIGH for Reset).
	
	.SW(SW) ,				// input [7:0] SW
	
	.JA1(JA1) ,				// input  JA1
	.JA2(JA2) ,				// output  JA2
	.JA3(JA3) ,				// output  JA3
	
	.LD(LD) ,				// output [7:0] LD
	
	.VGA_R(R) ,				// output [4:0] VGA_R
	.VGA_G(G) ,				// output [4:0] VGA_G
	.VGA_B(B) ,				// output [4:0] VGA_B
	.VGA_VS(VSYNC) ,		// output  VGA_VS
	.VGA_HS(HSYNC) ,		// output  VGA_HS
	
	.AC_ADR0(AC_ADR0) ,	// output  AC_ADR0
	.AC_ADR1(AC_ADR1) ,	// output  AC_ADR1
	.AC_GPIO0(AC_GPIO0) ,// output  AC_GPIO0
	.AC_MCLK(AC_MCLK) ,	// output  AC_MCLK
	.AC_SCK(AC_SCK) ,		// output  AC_SCK
	.AC_GPIO1(AC_GPIO1) ,// input  AC_GPIO1
	.AC_GPIO2(AC_GPIO2) ,// input  AC_GPIO2
	.AC_GPIO3(AC_GPIO3) ,// input  AC_GPIO3
	.AC_SDA(AC_SDA) ,		// inout  AC_SDA
	
	.output_wave_l( output_wave_l ),	// output [23:0] output_wave_l
	.output_wave_r( output_wave_r ),	// output [23:0] output_wave_r
	
	.hblank( gba_hblank ),	// output hblank
	.vblank( gba_vblank ),	// output vblank
	
	.buttons( gba_buttons )	// input [15:0] buttons
);



assign CLK_VIDEO = CLK_50M;
assign VGA_SL = sl[1:0];

wire [2:0] scale = status[11:9];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

video_mixer #(.LINE_LENGTH(520)) video_mixer
(
	.clk_sys(CLK_VIDEO) ,	// input  clk_sys
	.ce_pix(1'b1) ,			// input  ce_pix
	.ce_pix_out(CE_PIXEL) ,	// output  ce_pix_out
	
	.scanlines(1'b0),
	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale==1),
	.mono(1'b0) ,		// input  mono
	
	.R({R,3'b000}) ,	// input [7:0] R
	.G({G,3'b000}) ,	// input [7:0] G
	.B({B,3'b000}) ,	// input [7:0] B
	
	.HSync(HSYNC) ,	// input  HSync
	.VSync(VSYNC) ,	// input  VSync
	.HBlank(HBLANK) ,	// input  HBlank
	.VBlank(VBLANK) ,	// input  VBlank
	
	.VGA_R(VGA_R) ,	// output [7:0] VGA_R
	.VGA_G(VGA_G) ,	// output [7:0] VGA_G
	.VGA_B(VGA_B) ,	// output [7:0] VGA_B
	.VGA_VS(VGA_VS) ,	// output  VGA_VS
	.VGA_HS(VGA_HS) ,	// output  VGA_HS
	.VGA_DE(VGA_DE) 	// output  VGA_DE
);

						
wire [7:0] kbd_joy0;
wire [7:0] kbd_joy1;
wire [11:0] powerpad;

keyboard keyboard
(
	.clk(clk16),
	.reset(reset_snes),

	.ps2_key(ps2_key),

	.joystick_0(kbd_joy0),
	.joystick_1(kbd_joy1),
	
	.powerpad(powerpad)
);

endmodule
