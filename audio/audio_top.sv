`default_nettype none
`include "../gba_mmio_defines.vh"
`include "../gba_core_defines.vh"

module gba_audio_top (
	input  logic clk_100,
	input  logic clk_256,
	input  logic gba_clk,
	input  logic reset,
	input  logic SW,
	input  logic [3:0]  FIFO_size_A,
	input  logic [31:0] FIFO_val_A,
	output logic FIFO_re_A,
	output logic FIFO_clr_A,
	input  logic [3:0] FIFO_size_B,
	input  logic [31:0] FIFO_val_B,
	output logic FIFO_re_B,
	output logic FIFO_clr_B,
	output logic AC_ADR0,
	output logic AC_ADR1,
	output logic AC_GPIO0,
	input  logic AC_GPIO1,
	input  logic AC_GPIO2,
	input  logic AC_GPIO3,
	output logic AC_MCLK,
	output logic AC_SCK,
	inout  wire AC_SDA,
	output logic sound_req1,
	output logic sound_req2,
	input logic [31:0] IO_reg_datas [`NUM_IO_REGS-1:0],
	input logic [15:0] internal_TM0CNT_L,
	input logic [15:0] internal_TM1CNT_L,
	input logic dsASqRst, dsBSqRst,

	output logic [23:0] output_wave_l,
	output logic [23:0] output_wave_r,
	
	input  logic [11:0] io_addr,
	input  logic io_write,
	
	input logic [31:0] bus_wdata,
	
	inout logic [31:0] io_reg_rdata
);

    logic clk_100_output, clk_256_output;
    assign clk_100_output = clk_100;
    assign clk_256_output = clk_256;

    //audio codec
    logic        clk_100_buffered;
    //(* mark_debug = "true" *) logic [23:0] hphone_l, hphone_r;
    (* mark_debug = "true" *) logic        hphone_valid;
    (* mark_debug = "true" *) logic        new_sample;
    logic        sample_clk_48k;
    logic [23:0] line_in_r, line_in_l;

    //wave channel
    logic [7:0] NR30, NR31, NR32, NR33, NR34;
    logic [15:0] addr_0x90;
    logic [15:0] addr_0x92;
    logic [15:0] addr_0x94;
    logic [15:0] addr_0x96;
    logic [15:0] addr_0x98;
    logic [15:0] addr_0x9A;
    logic [15:0] addr_0x9C;
    logic [15:0] addr_0x9E;
    logic [23:0] channel_3;

    //square2 channel
    logic [7:0] NR21, NR22, NR23, NR24;
    logic [23:0] channel_2;

    //square1 channel
    logic [7:0] NR10, NR11, NR12, NR13, NR14;
    logic [23:0] channel_1;

    //noise channel
    logic [7:0] NR41, NR42, NR43, NR44;
    logic [23:0] channel_4;

    //mixed channel
    (* mark_debug = "true" *) logic [7:0] NR50, NR51,  NR52;
    logic [23:0] ch4_mixed_l;
    logic [23:0] ch4_mixed_r;
    logic reset_c1;
    logic reset_c2;
    logic reset_c3;
    logic reset_c4;

    //final mixer
    logic [23:0] direct_A, direct_B;
    logic [15:0] SOUND_CNT_H;
    logic timer_numA;
    logic timer_numB;
    //(* mark_debug = "true" *) logic [23:0] output_wave_r;
    //(* mark_debug = "true" *) logic [23:0] output_wave_l;

    assign NR10 = IO_reg_datas[`SOUND1CNT_L_IDX][7:0];
    assign NR11 = IO_reg_datas[`SOUND1CNT_H_IDX][23:16];
    assign NR12 = IO_reg_datas[`SOUND1CNT_H_IDX][31:24];
    assign NR13 = IO_reg_datas[`SOUND1CNT_X_IDX][7:0];
    assign NR14 = IO_reg_datas[`SOUND1CNT_X_IDX][15:8];

    assign NR21 = IO_reg_datas[`SOUND2CNT_L_IDX][7:0];
    assign NR22 = IO_reg_datas[`SOUND2CNT_L_IDX][15:8];
    assign NR23 = IO_reg_datas[`SOUND2CNT_H_IDX][7:0];
    assign NR24 = IO_reg_datas[`SOUND2CNT_H_IDX][15:8];

    assign NR30 = IO_reg_datas[`SOUND3CNT_L_IDX][7:0];
    assign NR31 = IO_reg_datas[`SOUND3CNT_H_IDX][23:16];
    assign NR32 = IO_reg_datas[`SOUND3CNT_H_IDX][31:24];
    assign NR33 = IO_reg_datas[`SOUND3CNT_X_IDX][7:0];
    assign NR34 = IO_reg_datas[`SOUND3CNT_X_IDX][15:8];

    assign addr_0x90 = IO_reg_datas[`WAVE_RAM0_L_IDX][15:0];
    assign addr_0x92 = IO_reg_datas[`WAVE_RAM0_H_IDX][31:16];
    assign addr_0x94 = IO_reg_datas[`WAVE_RAM1_L_IDX][15:0];
    assign addr_0x96 = IO_reg_datas[`WAVE_RAM1_H_IDX][31:16];
    assign addr_0x98 = IO_reg_datas[`WAVE_RAM2_L_IDX][15:0];
    assign addr_0x9A = IO_reg_datas[`WAVE_RAM2_H_IDX][31:16];
    assign addr_0x9C = IO_reg_datas[`WAVE_RAM3_L_IDX][15:0];
    assign addr_0x9E = IO_reg_datas[`WAVE_RAM3_H_IDX][31:16];

    assign NR41 = IO_reg_datas[`SOUND4CNT_L_IDX][7:0];
    assign NR42 = IO_reg_datas[`SOUND4CNT_L_IDX][15:8];
    assign NR43 = IO_reg_datas[`SOUND4CNT_H_IDX][7:0];
    assign NR44 = IO_reg_datas[`SOUND4CNT_H_IDX][15:8];

    assign NR50 = IO_reg_datas[`SOUNDCNT_L_IDX][7:0];
    assign NR51 = IO_reg_datas[`SOUNDCNT_L_IDX][15:8];
    assign NR52 = IO_reg_datas[`SOUNDCNT_X_IDX][7:0];

    assign SOUND_CNT_H = IO_reg_datas[`SOUNDCNT_H_IDX][31:16];

	// Audio regs...
	logic [31:0] SOUND1CNT_L_REG;
	logic [31:0] SOUND1CNT_H_REG;
	logic [31:0] SOUND1CNT_X_REG;
	logic [31:0] SOUND2CNT_L_REG;
	logic [31:0] SOUND2CNT_H_REG;
	logic [31:0] SOUND3CNT_L_REG;
	logic [31:0] SOUND3CNT_H_REG;
	logic [31:0] SOUND3CNT_X_REG;
	logic [31:0] SOUND4CNT_L_REG;
	logic [31:0] SOUND4CNT_H_REG;
	logic [31:0] SOUNDCNT_L_REG;
	logic [31:0] SOUNDCNT_H_REG;
	logic [31:0] SOUNDCNT_X_REG;
	logic [31:0] SOUNDBIAS_REG;
	logic [31:0] WAVE_RAM0_L_REG;
	logic [31:0] WAVE_RAM0_H_REG;
	logic [31:0] WAVE_RAM1_L_REG;
	logic [31:0] WAVE_RAM1_H_REG;
	logic [31:0] WAVE_RAM2_L_REG;
	logic [31:0] WAVE_RAM2_H_REG;
	logic [31:0] WAVE_RAM3_L_REG;
	logic [31:0] WAVE_RAM3_H_REG;
	logic [31:0] FIFO_A_L_REG;
	logic [31:0] FIFO_A_H_REG;
	logic [31:0] FIFO_B_L_REG;
	logic [31:0] FIFO_B_H_REG;
	 
always_ff @(posedge gba_clk or posedge reset)
if (reset) begin

end
else begin
	if (io_write) begin
		case ( io_addr >> 2 )
		`SOUND1CNT_L_IDX: SOUND1CNT_L_REG <= bus_wdata;
		`SOUND1CNT_H_IDX: SOUND1CNT_H_REG <= bus_wdata;
		`SOUND1CNT_X_IDX: SOUND1CNT_X_REG <= bus_wdata;
		`SOUND2CNT_L_IDX: SOUND2CNT_L_REG <= bus_wdata;
		`SOUND2CNT_H_IDX: SOUND2CNT_H_REG <= bus_wdata;
		`SOUND3CNT_L_IDX: SOUND3CNT_L_REG <= bus_wdata;
		`SOUND3CNT_H_IDX: SOUND3CNT_H_REG <= bus_wdata;
		`SOUND3CNT_X_IDX: SOUND3CNT_X_REG <= bus_wdata;
		`SOUND4CNT_L_IDX: SOUND4CNT_L_REG <= bus_wdata;
		`SOUND4CNT_H_IDX: SOUND4CNT_H_REG <= bus_wdata;
		`SOUNDCNT_L_IDX: SOUNDCNT_L_REG <= bus_wdata;
		`SOUNDCNT_H_IDX: SOUNDCNT_H_REG <= bus_wdata;
		`SOUNDCNT_X_IDX: SOUNDCNT_X_REG <= bus_wdata;
		`SOUNDBIAS_IDX: SOUNDBIAS_REG <= bus_wdata;
		`WAVE_RAM0_L_IDX: WAVE_RAM0_L_REG <= bus_wdata;
		`WAVE_RAM0_H_IDX: WAVE_RAM0_H_REG <= bus_wdata;
		`WAVE_RAM1_L_IDX: WAVE_RAM1_L_REG <= bus_wdata;
		`WAVE_RAM1_H_IDX: WAVE_RAM1_H_REG <= bus_wdata;
		`WAVE_RAM2_L_IDX: WAVE_RAM2_L_REG <= bus_wdata;
		`WAVE_RAM2_H_IDX: WAVE_RAM2_H_REG <= bus_wdata;
		`WAVE_RAM3_L_IDX: WAVE_RAM3_L_REG <= bus_wdata;
		`WAVE_RAM3_H_IDX: WAVE_RAM3_H_REG <= bus_wdata;
		`FIFO_A_L: FIFO_A_L_REG <= bus_wdata;
		`FIFO_A_H: FIFO_A_H_REG <= bus_wdata;
		`FIFO_B_L: FIFO_B_L_REG <= bus_wdata;
		`FIFO_B_H: FIFO_B_H_REG <= bus_wdata;
		default:;
		endcase
	end
end


always_comb begin
		case ( io_addr >> 2 )
		`SOUND1CNT_L_IDX: io_reg_rdata = SOUND1CNT_L_REG;
		`SOUND1CNT_H_IDX: io_reg_rdata = SOUND1CNT_H_REG;
		`SOUND1CNT_X_IDX: io_reg_rdata = SOUND1CNT_X_REG;
		`SOUND2CNT_L_IDX: io_reg_rdata = SOUND2CNT_L_REG;
		`SOUND2CNT_H_IDX: io_reg_rdata = SOUND2CNT_H_REG;
		`SOUND3CNT_L_IDX: io_reg_rdata = SOUND3CNT_L_REG;
		`SOUND3CNT_H_IDX: io_reg_rdata = SOUND3CNT_H_REG;
		`SOUND3CNT_X_IDX: io_reg_rdata = SOUND3CNT_X_REG;
		`SOUND4CNT_L_IDX: io_reg_rdata = SOUND4CNT_L_REG;
		`SOUND4CNT_H_IDX: io_reg_rdata = SOUND4CNT_H_REG;
		`SOUNDCNT_L_IDX: io_reg_rdata = SOUNDCNT_L_REG;
		`SOUNDCNT_H_IDX: io_reg_rdata = SOUNDCNT_H_REG;
		`SOUNDCNT_X_IDX: io_reg_rdata = SOUNDCNT_X_REG;
		`SOUNDBIAS_IDX: io_reg_rdata = SOUNDBIAS_REG;
		`WAVE_RAM0_L_IDX: io_reg_rdata = WAVE_RAM0_L_REG;
		`WAVE_RAM0_H_IDX: io_reg_rdata = WAVE_RAM0_H_REG;
		`WAVE_RAM1_L_IDX: io_reg_rdata = WAVE_RAM1_L_REG;
		`WAVE_RAM1_H_IDX: io_reg_rdata = WAVE_RAM1_H_REG;
		`WAVE_RAM2_L_IDX: io_reg_rdata = WAVE_RAM2_L_REG;
		`WAVE_RAM2_H_IDX: io_reg_rdata = WAVE_RAM2_H_REG;
		`WAVE_RAM3_L_IDX: io_reg_rdata = WAVE_RAM3_L_REG;
		`WAVE_RAM3_H_IDX: io_reg_rdata = WAVE_RAM3_H_REG;
		`FIFO_A_L: io_reg_rdata = FIFO_A_L_REG;
		`FIFO_A_H: io_reg_rdata = FIFO_A_H_REG;
		`FIFO_B_L: io_reg_rdata = FIFO_B_L_REG;
		`FIFO_B_H: io_reg_rdata = FIFO_B_H_REG;
		default: io_reg_rdata = 32'hzzzzzzzz;		// MUST be set as High-Z, to prevent contention with the other modules during reads! ElectronAsh.
	endcase
end

	 /*
	audio_top top(
		.clk_100(clk_100_buffered),
		.AC_MCLK(AC_MCLK),
		.AC_ADR0(AC_ADR0),
		.AC_ADR1(AC_ADR1),
		.AC_SCK(AC_SCK),
		.AC_SDA(AC_SDA),

		.AC_GPIO0(AC_GPIO0),
		.AC_GPIO1(AC_GPIO1),
		.AC_GPIO2(AC_GPIO2),
		.AC_GPIO3(AC_GPIO3),

		.hphone_l(hphone_l),
		.hphone_l_valid(hphone_valid),

		.hphone_r(hphone_r),
		.hphone_r_valid_dummy(hphone_valid),

		.line_in_l(line_in_l),
		.line_in_r(line_in_r),
		.new_sample(new_sample),
		.sample_clk_48k(sample_clk_48k)
	);
	*/

    noise n(
        .system_clock(clk_100),
        .clock_256(clk_256_output),
        .reset((reset || reset_c4)),
        .NR41, .NR42, .NR43,
        .NR44, .output_wave(channel_4));

    wave w(
        .system_clock(clk_100),
        .clock_256(clk_256_output),
        .reset((reset || reset_c3)),
        .NR30, .NR31, .NR32,
        .NR33, .NR34,
        .addr_0x90,
        .addr_0x92,
        .addr_0x94,
        .addr_0x96,
        .addr_0x98,
        .addr_0x9A,
        .addr_0x9C,
        .addr_0x9E,
        .output_wave(channel_3));

    square2 sq2(
        .system_clock(clk_100),
        .clock_256(clk_256_output),
        .reset((reset || reset_c2)),
        .NR21, .NR22, .NR23,
        .NR24, .output_wave(channel_2));

    square1 sq1(
        .system_clock(clk_100),
        .clock_256(clk_256_output),
        .reset(reset || ~NR52[7]),
        .NR10, .NR11, .NR12, .NR13,
        .NR14, .output_wave(channel_1));

    ch4_mixer m(.system_clock(clk_100),
        .reset,
        .channel1(channel_1),
        .channel2(channel_2),
        .channel3(channel_3),
        .channel4(channel_4),
        .NR50, .NR51, .NR52,
        .output_wave_left(ch4_mixed_l),
        .output_wave_right(ch4_mixed_r)); //used to reset the system

    /* variables for direct sound*/


    direct_sound dsA(
        .clock(gba_clk),
        .reset(reset),
        .FIFO_size(FIFO_size_A),
        .FIFO_value(FIFO_val_A),
        .FIFO_re(FIFO_re_A),
        .FIFO_clr(FIFO_clr_A),
        .TM0_CNT_L(internal_TM0CNT_L),
        .TM1_CNT_L(internal_TM1CNT_L),
        .timer_num(timer_numA),
        .sequencer_reset (dsASqRst),
        .waveout(direct_A),
        .output_r(SOUND_CNT_H[8]),
        .output_l(SOUND_CNT_H[9]),
        .sound_req(sound_req1));

    direct_sound dsB(
        .clock(gba_clk),
        .reset(reset),
        .FIFO_size(FIFO_size_B),
        .FIFO_value(FIFO_val_B),
        .FIFO_re(FIFO_re_B),
        .FIFO_clr(FIFO_clr_B),
        .TM0_CNT_L(internal_TM0CNT_L),
        .TM1_CNT_L(internal_TM1CNT_L),
        .timer_num(timer_numB),
        .sequencer_reset(dsBSqRst),
        .waveout(direct_B),
        .output_r(SOUND_CNT_H[12]),
        .output_l(SOUND_CNT_H[13]),
        .sound_req(sound_req2));

    ds_mixer dsm(
        .clock(clk_100),
        .reset,
        .direct_A,
        .direct_B,
        .channel4_l(ch4_mixed_l),
        .channel4_r(ch4_mixed_r),
        .sound_cnt_h(SOUND_CNT_H),
        .timer_numA,
        .timer_numB,
        .output_wave_r( output_wave_r ),
        .output_wave_l( output_wave_l )
		);

    power p(
        .clock(clk_100),
        .NR52,
        .reset_channel1(reset_c1),
        .reset_channel2(reset_c2),
        .reset_channel3(reset_c3),
        .reset_channel4(reset_c4));

    (* mark_debug = "true" *) logic [15:0] counter_100;
    always_ff @(posedge clk_100, posedge reset, posedge new_sample) begin
        if (reset || new_sample)
            counter_100 <= 16'b0;
        else
            counter_100 <= counter_100 + 1;
    end
    
	 /*
    always_ff @(posedge clk_100, posedge reset) begin
        if (reset) begin
            hphone_valid <= 0;
            hphone_l <= 0;
            hphone_r <= 0;
        end else begin
            hphone_valid <= 0;
            hphone_l <= 0;
            hphone_r <= 0;

            if (new_sample == 1) begin
                hphone_valid <= 1'b1;
                hphone_r <= {output_wave_r};
                hphone_l <= {output_wave_l};
            end
        end
    end
	 */

	 /*
    BUFG BUFG_inst(
        .O (clk_100_buffered),
        .I (clk_100)
        );*/
		  
	assign clk_100_buffered = clk_100;	// ElectronAsh. Kludge.


endmodule: gba_audio_top

`default_nettype wire

