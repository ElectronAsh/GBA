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

	//Base video clock. Usually equals to clk_sys.
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

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[8] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[8] ? 8'd9  : 8'd3;

//assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
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
	"J,A,B,Select,Start,L,R;",
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

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire  [7:0] ioctl_index;
reg         ioctl_wait;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
   .conf_str(CONF_STR),

   .buttons(buttons),
   .forced_scandoubler(forced_scandoubler),

   .joystick_0(joystick_0),
   .joystick_1(joystick_1),

   .status(status),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

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
wire clk_ram;
wire clk16;
wire clk100;
wire clk256;

wire clk_sys = clk16;

wire clk33;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_ram),
	.outclk_1(SDRAM_CLK),
	.outclk_2(clk16),
	.outclk_3(clk100),
	.outclk_4(clk256),
	.outclk_5(clk33),
	.locked(clock_locked)
);




// reset after download
/*
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
 

//wire [21:0] memory_addr;
//wire        memory_read_cpu, memory_read_ppu;
wire        memory_write = 1'b0;
//wire  [7:0] memory_din_cpu, memory_din_ppu;


wire [15:0] SDRAM_DOUT;

// Loader
wire [7:0] loader_input;
wire       loader_clk;
reg [24:0] loader_addr;
wire [7:0] loader_write_data = loader_input;
wire loader_reset = !download_reset; //loader_conf[0];
wire loader_write = loader_clk;
wire [31:0] loader_flags;


reg led_blink;
always @(posedge clk_sys) begin
	int cnt = 0;
	cnt <= cnt + 1;
	if(cnt == 10000000) begin
		cnt <= 0;
		led_blink <= ~led_blink;
	end;
end

// NES is clocked at every 4th cycle.
reg [1:0] nes_ce;
always @(posedge clk_sys) nes_ce <= nes_ce + 1'd1;


// loader_write -> clock when data available
reg loader_write_mem;
reg [15:0] loader_write_data_mem;
reg [24:0] loader_addr_mem;

reg loader_write_triggered;

reg [3:0] rom_size;
reg [3:0] ram_size;

always @(posedge clk_sys) begin
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
		loader_addr_mem <= loader_addr;
		if (!loader_addr[0]) ? loader_write_data_mem[15:8] <= loader_write_data;
		else begin
			loader_write_data_mem[7:0] <= loader_write_data;
			loader_write_triggered <= 1'b1;
		end
	end

	if(nes_ce == 3) begin
		loader_write_mem <= loader_write_triggered;
		if(loader_write_triggered)
			loader_write_triggered <= 1'b0;
	end
end


wire [21:0] cart_read_addr = (!CART_SRAM_CE_N && !CART_SRAM_OE_N) ? CART_SRAM_ADDR :
																						  CART_SRAM2_ADDR;
*/


sdram sdram
(
	// interface to the MT48LC16M16 chip
	.SDRAM_DQ		( SDRAM_DQ                 ),
	.SDRAM_A			( SDRAM_A                  ),
	.SDRAM_DQML		( {SDRAM_DQMH, SDRAM_DQML} ),
	.SDRAM_nCS		( SDRAM_nCS                ),
	.SDRAM_BA		( SDRAM_BA                 ),
	.SDRAM_nWE		( SDRAM_nWE                ),
	.SDRAM_nRAS		( SDRAM_nRAS               ),
	.SDRAM_nCAS		( SDRAM_nCAS               ),
	.SDRAM_CKE		( SDRAM_CKE                ),
	
	// system interface
	.clk      		( clk_ram ),
	.init         	( !clock_locked ),

	// cpu/chipset interface
	.addr     		( sdram_addr ),
	
	.we       		( sdram_we ),
	.wtbt				( sdram_wtbt ),
	.din       		( sdram_din ),

	.rd         	( sdram_rd ),
	.dout       	( sdram_dout ),
	
	.ready			( sdram_ready )
);

(*keep*) wire [1:0] sdram_wtbt = 2'b11;
(*keep*) wire sdram_we = ioctl_download & ioctl_wr;
(*keep*) wire [15:0] sdram_din = ioctl_dout;

(*keep*) wire sdram_rd = sdram_rd_reg;
(*keep*) wire [15:0] sdram_dout;

(*keep*) wire sdram_ready;


reg [31:0] gba_cart_data;

assign GBA_CART_DI = gba_cart_data;

reg GBA_CPU_PAUSE;

reg sdram_rd_reg;
(*keep*) reg [23:0] sdram_word_addr;

(*keep*) wire [24:0] sdram_addr = (ioctl_download) ? ioctl_addr : {sdram_word_addr,1'b0};

reg [3:0] cart_rd_state;

always @(posedge clk_sys or posedge GBA_RESET)
if (GBA_RESET) begin
	cart_rd_state <= 4'd0;
	sdram_rd_reg <= 1'b0;
	GBA_CPU_PAUSE <= 1'b0;
end
else begin
	sdram_rd_reg <= 1'b0;

	case (cart_rd_state)
	0: begin
		if (GBA_CART_RD) begin
			sdram_word_addr <= GBA_CART_ADDR[25:1];
			GBA_CPU_PAUSE <= 1'b1;
			if (sdram_ready) begin
				sdram_rd_reg <= 1'b1;
				cart_rd_state <= cart_rd_state + 1;
			end
		end
	end
	
	1: begin
		gba_cart_data[31:16] <= sdram_dout;
		sdram_word_addr <= GBA_CART_ADDR[25:1] + 1;
		if (sdram_ready) begin
			sdram_rd_reg <= 1'b1;
			cart_rd_state <= cart_rd_state + 1;
		end
	end
	
	2: begin
		gba_cart_data[15:0] <= sdram_dout;
		GBA_CPU_PAUSE <= 1'b0;
		cart_rd_state <= 4'd0;
	end
	
	default:;
	endcase
end




///////////////////////////////////////////////////
/*
wire [22:0] rom_addr = GBA_CART_ADDR;
wire [31:0] rom_data;
wire rom_rd = GBA_CART_RD;
assign GBA_CART_DI = rom_data;
wire rom_rdack;

ddram ddram
(
	.*,
	
   .wraddr(ioctl_addr),
   .din({ioctl_dout[7:0],ioctl_dout[15:8]}),
   .we_req(rom_wr),
   .we_ack(rom_wrack),

   .rdaddr(rom_addr),
   .dout(rom_data),
   .rd_req(rom_rd),
   .rd_ack(rom_rdack)
);

reg  rom_wr;
wire rom_wrack;


always @(posedge clk_sys) begin
	reg old_download, old_reset;
	old_download <= ioctl_download;
	old_reset <= reset;

	if(~old_reset && reset) ioctl_wait <= 0;
	if(~old_download && ioctl_download) rom_wr <= 0;
	else begin
		if(ioctl_wr) begin
			//ioctl_wait <= 1;
			rom_wr <= ~rom_wr;
		end else if(ioctl_wait && (rom_wr == rom_wrack)) begin
			ioctl_wait <= 0;
		end
	end
end
*/


/*
wire        romwr_ack;
reg  [23:0] romwr_a;
wire [15:0] romwr_d = ioctl_dout;

reg  rom_wr = 0;
wire sd_wrack, dd_wrack;

always @(posedge clk_sys) begin
	reg old_download, old_reset;

	old_download <= ioctl_download;
	old_reset <= reset;

	if(~old_reset && reset) ioctl_wait <= 0;
	if(~old_download && ioctl_download) begin	// Rising edge of ioctl_download sets up the transfer.
		romwr_a <= 0;
	end
	else begin
		if(ioctl_wr) begin
			ioctl_wait <= 1;		// Always asserts ioctl_wait, so we can check for dd_wrack or sd_wrack.
			rom_wr <= 1'b1;
		//end else if(ioctl_wait (rom_wr == sd_wrack)) begin
		end else if(ioctl_wait && !DDRAM_BUSY) begin
			ioctl_wait <= 0;
			rom_wr <= 1'b0;
			romwr_a <= romwr_a + 2'd2;
		end
	end
end


wire [7:0] download_be;


always @(*) begin
	case (romwr_a[2:1])
		// Swap the 16-bit WORD order.
		// (The HPS swaps the bytes of each 16-bit word already, so this effectively does a 32-bit byteswap of the Cart ROM.) ElectronAsh.
		0: download_be = 8'b00110000;
		1: download_be = 8'b11000000;
		2: download_be = 8'b00000011;
		3: download_be = 8'b00001100;
	default:;
	endcase
end

wire [3:0] data_ben = 4'b1111;
wire [7:0] DDRAM_BE_WRITES = (ioctl_download) ? download_be :
										(!GBA_CART_ADDR[2]) ? {data_ben, 4'b0000} : {4'b0000, data_ben};

assign DDRAM_CLK = clk_sys;
assign DDRAM_ADDR = (ioctl_download) ? {8'b00110100, romwr_a[23:3]} :		// Allow the GBA Cart ROM to be loaded into DDR at 0x34000000 (Byte addr). 0x06800000 (64-bit Word addr).
													{6'b001101,   GBA_CART_ADDR[25:3]};	// Else, map GBA Cart ROM reads to DDR at 0x34000000 (Byte addr). 0x06800000 (64-bit Word addr).


assign DDRAM_DIN = (ioctl_download) ? {ioctl_dout,ioctl_dout,ioctl_dout,ioctl_dout} : {sd_data_i, sd_data_i};
assign DDRAM_BE  = (ioctl_download) ? DDRAM_BE_WRITES : 8'hFF;	// DDR controller requires BE (Byte Enable) bits to be HIGH during READS! (AFAIK, ElectronAsh.)
assign DDRAM_RD  = (ioctl_download) ? 1'b0 : (GBA_CART_RD | DDRAM_RD_REG);
assign DDRAM_WE  = (ioctl_download) ? rom_wr : 1'b0;				// Main RAM access for GBA is from BRAM atm, so just setting to 1'b0 here.
assign DDRAM_BURSTCNT = 1;


assign GBA_CART_DI = (!GBA_CART_ADDR[2]) ? DDRAM_DOUT[63:32] : DDRAM_DOUT[31:0];	// Route data FROM DDR TO the core.

wire [31:0] sd_data_i = 32'hDEADBEEF;	// Write data FROM the core TO RAM. (not used for GBA atm).
//assign sd_waitrequest = DDRAM_BUSY;
//assign sd_valid = DDRAM_DOUT_READY;


reg GBA_CPU_PAUSE;
reg DDRAM_RD_REG;

reg [2:0] CART_RD_STATE;

always @(posedge clk_sys or posedge GBA_RESET)
if (GBA_RESET) begin
	CART_RD_STATE <= 3'd0;
	GBA_CPU_PAUSE <= 1'b0;
	DDRAM_RD_REG <= 1'b0;
end
else begin
	case (CART_RD_STATE)
	0: begin
		if (GBA_CART_RD) begin
			GBA_CPU_PAUSE <= 1'b1;
			DDRAM_RD_REG <= 1'b1;
			CART_RD_STATE <= CART_RD_STATE + 1;
		end
	end
	
	1: begin
		if (!DDRAM_BUSY) DDRAM_RD_REG <= 1'b0;
		
		if (DDRAM_DOUT_READY) begin
			GBA_CPU_PAUSE <= 1'b0;
			CART_RD_STATE <= 3'd0;
		end
	end
	
	default:;
	endcase
end
*/


wire [2:0] mapper_a;
wire [5:0] mapper_d;
wire       mapper_we;

reg  [5:0] map[8] = '{0,1,2,3,4,5,6,7};
reg        use_map = 0;

always @(posedge clk_sys) begin
	if(reset) begin
		map <= '{0,1,2,3,4,5,6,7};
		use_map <= 0;
	end
	else if (mapper_we && mapper_a) begin
		map[mapper_a] <= mapper_d;
		use_map <= 1;
	end
end

reg  [1:0] region_req;
reg        region_set = 0;

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state, old_download = 0;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		casex(code)
			'h005: begin region_req <= 0; region_set <= pressed; end // F1
			'h006: begin region_req <= 1; region_set <= pressed; end // F2
			'h004: begin region_req <= 2; region_set <= pressed; end // F3
		endcase
	end

	old_download <= ioctl_download;
	if(status[8] & (old_download ^ ioctl_download) & |ioctl_index) begin
		region_set <= ioctl_download;
		region_req <= ioctl_index[7:6];
	end
end


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

wire [4:0] GBA_R;
wire [4:0] GBA_G;
wire [4:0] GBA_B;
wire GBA_HS;
wire GBA_VS;
wire GBA_DE;
wire GBA_HBLANK;
wire GBA_VBLANK;


wire [23:0] output_wave_l;
wire [23:0] output_wave_r;

assign AUDIO_L = output_wave_l[23:8];
assign AUDIO_R = output_wave_r[23:8];

wire [31:0] GBA_CART_ADDR;
wire [31:0] GBA_CART_DI;
wire [31:0] GBA_CART_DO;
wire GBA_CART_RD;
wire GBA_CART_WR;


// joystick_0 / joystick_1 (from HPS IO, for GBA)...
//
// Bits 4 upwards are dependant on the "J" list in the CONF_STR, it seems.
// Looks like Right, Left, Down, Up get assigned to the lower bits regardless. ElectronAsh.
//
// [15] = 
// [14] = 
// [13] = 
// [12] = 
// [11] = 
// [10] = 
// [9]  = R
// [8]  = L
// [7]  = Start
// [6]  = Select
// [5]  = B
// [4]  = A
// [3]  = UP
// [2]  = DOWN
// [1]  = LEFT
// [0]  = RIGHT
//
//
// GBA button mapping...
//
// gba_buttons[0] = // A
// gba_buttons[1] = // B
// gba_buttons[2] = // Select
// gba_buttons[3] = // Start
// gba_buttons[4] = // Right
// gba_buttons[5] = // Left
// gba_buttons[6] = // Down
// gba_buttons[7] = // Up
// gba_buttons[8] = // R
// gba_buttons[9] = // L
// gba_buttons[15:10] = 6'h3F; // (set these 6 bits HIGH).
//
wire [15:0] gba_buttons = {6'b111111,joystick_0[8],joystick_0[9],joystick_0[3],joystick_0[2],joystick_0[1],joystick_0[0],joystick_0[7],joystick_0[6],joystick_0[5],joystick_0[4]};

reg [6:0] GBA_CLK_DIV;

always @(posedge clk_sys or posedge reset) 
if (reset) GBA_CLK_DIV <= 0;
else GBA_CLK_DIV <= GBA_CLK_DIV + 1'b1;


wire reset = RESET | status[0] | buttons[1] | arm_reset;

wire GBA_RESET = reset | ioctl_download;

gba_top gba_top_inst
(
	.gba_clk(clk_sys),		// 16.776 MHz.
	
	//.clk_100(GBA_CLK_DIV[6]),		// 131,072 Hz, I think?
	//.clk_256(GBA_CLK_DIV[5]),		// 262,144 Hz, I think?
	
	.clk_100(clk100),
	.clk_256(clk256),
	
	.vga_clk(CLK_50M),	// 50.33 MHz.
	
	.BTND(GBA_RESET) ,	// input  BTND (active HIGH for Reset).
	
	.SW(SW) ,				// input [7:0] SW
	
	.JA1(JA1) ,				// input  JA1
	.JA2(JA2) ,				// output  JA2
	.JA3(JA3) ,				// output  JA3
	
	.LD(LD) ,				// output [7:0] LD
	
	.VGA_R(GBA_R) ,		// output [4:0] VGA_R
	.VGA_G(GBA_G) ,		// output [4:0] VGA_G
	.VGA_B(GBA_B) ,		// output [4:0] VGA_B
	.VGA_VS(GBA_VS) ,		// output  VGA_VS
	.VGA_HS(GBA_HS) ,		// output  VGA_HS
	.VGA_DE(GBA_DE) ,		// output  VGA_DE
	
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
	
	.hblank( GBA_HBLANK ),	// output hblank
	.vblank( GBA_VBLANK ),	// output vblank
	
	.buttons( gba_buttons ),	// input [15:0] buttons
	
	.CART_ADDR( GBA_CART_ADDR ),	// output [31:0] CART_ADDR
	.CART_DI( GBA_CART_DI ),		// input [31:0] CART_DI
	.CART_DO( GBA_CART_DO ),		// output [31:0] CART_DO
	.CART_RD( GBA_CART_RD ),		// output CART_RD
	.CART_WR( GBA_CART_WR ),		// output CART_WR
	
	.CPU_PAUSE( GBA_CPU_PAUSE )
);


wire [4:0] R = (GBA_DE) ? GBA_R : 5'b00000;
wire [4:0] G = (GBA_DE) ? GBA_G : 5'b00000;
wire [4:0] B = (GBA_DE) ? GBA_B : 5'b00000;

//wire [4:0] R = GBA_R;
//wire [4:0] G = GBA_G;
//wire [4:0] B = GBA_B;


assign CLK_VIDEO = clk_sys;

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
	
	.HSync(GBA_HS) ,	// input  HSync
	.VSync(GBA_VS) ,	// input  VSync
	.HBlank(GBA_HBLANK) ,	// input  HBlank
	.VBlank(GBA_VBLANK) ,	// input  VBlank
	
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
	.clk(clk_sys),
	.reset(reset),

	.ps2_key(ps2_key),

	.joystick_0(kbd_joy0),
	.joystick_1(kbd_joy1),
	
	.powerpad(powerpad)
);

endmodule
