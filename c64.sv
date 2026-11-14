//============================================================================
//  C64 Top level for MiSTer
//  Copyright (C) 2017-2021 Sorgelig
//
//  Used DE2-35 Top level by Dar (darfpga@aol.fr)
//
//  FPGA64 is Copyrighted 2005-2008 by Peter Wendrich (pwsoft@syntiac.com)
//  http://www.syntiac.com/fpga64.html
//
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================ 

module emu
(
	`include "sys/emu_ports.vh"
);

wire [7:0]  drv_ddram_burstcnt;
wire [28:0] drv_ddram_addr;
wire        drv_ddram_rd;
wire        drv_ddram_we;
wire [63:0] drv_ddram_din;
wire [7:0]  drv_ddram_be;

// OCTOPHONIC: the DDR3 shared by the drives (their track buffers) and OctoVIC (its VRAM)
wire [7:0]  ogx_ddram_burstcnt;
wire [28:0] ogx_ddram_addr;
wire        ogx_ddram_rd;
wire        ogx_ddram_we;
wire [63:0] ogx_ddram_din;
wire [7:0]  ogx_ddram_be;
wire        drv_ddram_busy, drv_ddram_ready, ogx_ddram_busy, ogx_ddram_ready;

assign DDRAM_CLK      = clk_sys;

ddram_arb2 ddram_arb
(
	.clk(clk_sys),
	.reset(~pll_locked),
	.a_addr(drv_ddram_addr), .a_burstcnt(drv_ddram_burstcnt), .a_rd(drv_ddram_rd), .a_we(drv_ddram_we),
	.a_din(drv_ddram_din), .a_be(drv_ddram_be), .a_busy(drv_ddram_busy), .a_ready(drv_ddram_ready),
	.b_addr(ogx_ddram_addr), .b_burstcnt(ogx_ddram_burstcnt), .b_rd(ogx_ddram_rd), .b_we(ogx_ddram_we),
	.b_din(ogx_ddram_din), .b_be(ogx_ddram_be), .b_busy(ogx_ddram_busy), .b_ready(ogx_ddram_ready),
	.addr(DDRAM_ADDR), .burstcnt(DDRAM_BURSTCNT), .rd(DDRAM_RD), .we(DDRAM_WE), .din(DDRAM_DIN), .be(DDRAM_BE),
	.busy(DDRAM_BUSY), .ready(DDRAM_DOUT_READY)
);
`ifdef RGB256
// Build 14: in the RGB companion core port B is shared again - the rewind unit (its journal) and the
// Level 2 remaster unit (the pack's tables)
wire [7:0]  rwd_ddram_burstcnt, rm_ddram_burstcnt;
wire [28:0] rwd_ddram_addr, rm_ddram_addr;
wire        rwd_ddram_rd, rwd_ddram_we, rm_ddram_rd, rm_ddram_we;
wire [63:0] rwd_ddram_din, rm_ddram_din;
wire [7:0]  rwd_ddram_be, rm_ddram_be;
wire        rwd_ddram_busy, rwd_ddram_ready, rm_ddram_busy, rm_ddram_ready;
ddram_arb2 ddram_arb_b
(
	.clk(clk_sys),
	.reset(~pll_locked),
	.a_addr(rwd_ddram_addr), .a_burstcnt(rwd_ddram_burstcnt), .a_rd(rwd_ddram_rd), .a_we(rwd_ddram_we),
	.a_din(rwd_ddram_din), .a_be(rwd_ddram_be), .a_busy(rwd_ddram_busy), .a_ready(rwd_ddram_ready),
	.b_addr(rm_ddram_addr), .b_burstcnt(rm_ddram_burstcnt), .b_rd(rm_ddram_rd), .b_we(rm_ddram_we),
	.b_din(rm_ddram_din), .b_be(rm_ddram_be), .b_busy(rm_ddram_busy), .b_ready(rm_ddram_ready),
	.addr(ogx_ddram_addr), .burstcnt(ogx_ddram_burstcnt), .rd(ogx_ddram_rd), .we(ogx_ddram_we), .din(ogx_ddram_din), .be(ogx_ddram_be),
	.busy(ogx_ddram_busy), .ready(ogx_ddram_ready)
);
`endif
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign LED_DISK   = 0;
assign LED_POWER  = 0;
assign LED_USER   = |drive_led | ioctl_download | ioctl_upload | ezfl_mod | tape_led | ~disk_ready;
reg    close_osd  = 0;
assign BUTTONS    = {1'b0, close_osd};
assign VGA_DISABLE = 0;
assign VGA_SCALER = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

// Status Bit Map:
//              Upper                          Lower
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
//
// 6     7         8         9         10        11        12
// 45678901234567890123456789012345 67890123456789012345678901234567
// XXXXXXXXXXXXXXXXXXXXXXXXX  XXXXX
//                            ^^^^^ 91=Counter Reset, 92=Counter,
//                                  93=Rewind, 94=Fast Forward, 95=Stop

`include "build_id.v"
localparam CONF_STR = {
	"C64;UART9600:2400;",
	"H7S0,D64G64T64D81,Mount #8;",
	"O[76],Mount Write Protected,Off,On;",
	"-;",
	"F1,PRGCRTREU;",
`ifdef RGB256
	// Octophonic64RGB (Fix 60, Build 12): the recolour pack (docs/RGB256.md) and which of its palettes - WIN+F3 cycles them
	"FC4,RGB,Load Recolour Pack;",
	"O[108:105],Recolour,Palette 1,Palette 2,Palette 3,Palette 4,Palette 5,Palette 6,Palette 7,Palette 8,Off;",
	// REWIND (Fix 61, Build 13): hold WIN+F2 (or the pad button set as Rewind) and the game runs backwards
	"O[109],Rewind,On,Off;",
`endif
	"hAdBR[61],Save cartridge;",
	"hAO[62],Autosave,Off,On;",
	"h3-;",
	"h3T[7],Tape Play/Pause;",
	"h3T[95],Tape Stop;",
	"h3T[93],Tape Rewind;",
	"h3T[94],Tape Fast Forward;",
	"h3T[91],Tape Counter Reset;",
	"h3-;",
	"h3O[92],Tape Counter,Off,On;",
	"h3O[11],Tape Sound,Off,On;",
	"h3R[23],Tape Unload;",
	"-;",

	"P1,Audio & Video;", 
 	"P1O[2],Video Standard,PAL,NTSC;",
	"P1O[104],PAL Rate,Exact 50 Hz,Original 50.12 Hz;",
	"P1O[35:34],VIC-II,656x,856x,Early 856x;",
	"P1O[84:82],Palette,Colodore,Ultimate,Pepto-PAL,Vice,Vice6569R1,Vice6569R5,Vice8565R2,Lemon64;",
	"P1O[5:4],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[10:8],Scandoubler Fx,None,HQ2x-320,HQ2x-160,CRT 25%,CRT 50%,CRT 75%;",
	"P1O[102],Split Screens,Off,VGA C64 + HDMI Octo;",
	"P1O[103],Quarter Pixels,On,Off;",
	"d1P1O[32],Vertical Crop,No,Yes;",
	"P1O[31:30],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1O[13],Left SIDs 1357,6581,8580;",
	"P1O[16],Right SIDs 2468,6581,8580;",
	"D4P1O[66:64],Left Filter,Default,Custom 1,Custom 2,Custom 3,Adjustable;",
	"D5P1O[69:67],Right Filter,Default,Custom 1,Custom 2,Custom 3,Adjustable;",
	"D4D8P1O[72:70],Left Fc Offset,0,1,2,3,4,5;",
	"D5D9P1O[75:73],Right Fc Offset,0,1,2,3,4,5;",
	"P1O[22:20],Right SID Port,Same,DE00,D420,D500,DF00;",
	"P1O[98:97],Octophonic,8 SIDs,4 SIDs,Off;",
	"P1O[100:99],OctoSID FX,Off,Chorus,Echo,Chorus+Echo;",
	"P1O[37],8580 Digifix,On,Off;",
	"P1FC7,FLT,Load Custom Filters;",
	"P1-;",
	"P1O[41:40],DigiMax,Disabled,DE00,DF00;",
	"P1O[19:18],Stereo Mix,None,25%,50%,100%;",

	// MY CHIPS (Fix 81, rtl/sid/chip_slots.sv, docs/CHIPS.md): three of Neal's own chips loaded at once, and each
	// SID's pick of them. Every SID line's first choice is what the core did before (1 3 5 7 chip A, 2 4 6 8 chip B)
	"P4,My Chips;",
	"P4O[101],My Chips,On,Off;",
	"P4-;",
	"P4FC2,CHP,Load Chip A;",
	"P4FC3,CHP,Load Chip B;",
	"P4FC6,CHP,Load Chip C (filter only);",
	"P4-;",
	"P4O[111:110],SID 1,Chip A,Chip B,Chip C,Core;",
	"P4O[113:112],SID 2,Chip B,Chip A,Chip C,Core;",
`ifndef RGB256
	"P4O[115:114],SID 3,Chip A,Chip B,Chip C,Core;",
	"P4O[117:116],SID 4,Chip B,Chip A,Chip C,Core;",
	"P4O[119:118],SID 5,Chip A,Chip B,Chip C,Core;",
	"P4O[121:120],SID 6,Chip B,Chip A,Chip C,Core;",
	"P4O[123:122],SID 7,Chip A,Chip B,Chip C,Core;",
	"P4O[125:124],SID 8,Chip B,Chip A,Chip C,Core;",
`endif

	"P2,Hardware;", 
	"P2O[52],GeoRAM,Disabled,4MB;",
	"P2O[54:53],REU,16MB,2MB,512KB,Disabled;",
	"hCP2O[63],REU wrap,None,512KB;",
	"P2-;",
	"P2O[25],External IEC,Disabled,Enabled;",
	"P2O[43],Expansion,Joysticks,RS232;",
	"P2O[51],RS232 mode,UP9600,VIC-1011;",
	"P2O[33],RS232 connection,Internal,External;",
	"P2O[36],Real-Time Clock,Auto,Disabled;",
	"P2O[45],CIA,6526,8521;",
	"P2-;",
	"P2O[27:26],Pot 1/2,Joy 1 Fire 2/3,Mouse,Paddles 1/2;",
	"P2O[29:28],Pot 3/4,Joy 2 Fire 2/3,Mouse,Paddles 3/4;",
	"P2-;",
	"P2O[60:59],Key modifier,L+R Shift,L Shift,R Shift;",
	"P2-;",
	"P2O[1],Release Keys on Reset,Yes,No;",
	"P2O[24],Clear RAM on Reset,Yes,No;",
	"P2O[50],Reset & Run PRG,Yes,No;",
	"P2O[42],Pause When OSD is Open,No,Yes;",
	"P2O[38],Boot EasyFlash,Yes,No;",
	"P2-;",
	"P2FC8,ROM,System ROM C64+C1541 ;",
	"P2FC9,ROM,System ROM C1581     ;",
	"P2FC5,CRT,Boot Cartridge       ;",
	"P2-;",
	"P2O[15:14],System ROM,Octophonic 64 V1.1,Standard C64,Weaver KERNAL 2,Japanese;",

	"P3,Drives;",
	"P3O[58:57],Enable Drive #8,If Mounted,Always,Never;",
	"P3O[44],Parallel port,Enabled,Disabled;",
	"P3O[86:85],Drives OSD,Activity Only,If Mounted,Debug,Off;",
	"P3-;",
	"P3O[80:78],Drive RPM    (G64),300.0,300.1,300.5,301.0,302.0,299.0,299.5,299.9;",
	"P3O[81],Drive Wobble (G64),Off,On;",
	"P3-;",
	"P3R[6],Reset Disk Drives;",

	"-;",
	"O[3],Swap Joysticks,Yes,No;",   // Fix 14: swapped is the default (status bit 3 = 0); "No" = the original ports
	"O[88:87],SNAC Joystick,Disabled,Joy 1,Joy 2;",
	"-;",
	"O[47:46],Turbo mode,C128,Off,Smart;",
	"d6O[49:48],Turbo speed,2x,3x,4x;",
	"-;",
	"R[0],Reset;",
	"R[17],Reset & Detach Cartridge;",
`ifdef RGB256
	"J,Fire 1,Fire 2,Fire 3,Paddle Btn,Mod1,Mod2,Rewind;",
	"jn,A,B,Y,X|P,R,L,Select;",
	"jp,A,B,Y,X|P,R,L,Select;",
`else
	"J,Fire 1,Fire 2,Fire 3,Paddle Btn,Mod1,Mod2;",
	"jn,A,B,Y,X|P,R,L;",
	"jp,A,B,Y,X|P,R,L;",
`endif
	"V,v",`BUILD_DATE
};

wire pll_locked;
wire clk_sys;
wire clk64;
wire clk48;

pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk48),
	.outclk_1(clk64),
	.outclk_2(clk_sys),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(pll_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
wire        cfg_write;
wire  [5:0] cfg_address;
wire [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// OCTOPHONIC Fix 48 (Exact 50 Hz): the PLL mode - PAL, Exact 50 Hz or NTSC - is set in rtl/pal50.sv
// (the old PAL/NTSC block, plus the Exact 50 Hz fractional M). Exact 50 Hz is the default (status[104]=0).
wire ntsc_r, exact_r;
wire close_osd_pll;
// (pll_mode is instantiated below, after the status bits, next to ntsc_req)

reg ntsc_sys1 = 0, ntsc = 0;
reg exact_sys1 = 0, exact = 0, exact_prev = 0;   // Fix 48
reg reset_n;
reg reset_wait = 0;
wire [15:0] sdram_sz;                        // Fix 59: from Main (hps_io)
wire hk_kernal, hk_brk, hk_wipe, hk_spare;   // Fix 58: SHIFT+F1-F4 hot keys (rtl/hotkeys.sv)
wire hk_reset;                               // SHIFT+F1's reset (C64RGB 256: only if Main doesn't switch cores)
`ifdef RGB256
reg         rgb_home = 0;                    // C64RGB 256: SHIFT+F1 held or WIN+F1 - Main is asked for the Octophonic core
reg [127:0] rgb_status_in;                   // C64RGB 256: WIN+F3 sets the OSD's palette line
reg         rgb_status_set = 0;
reg   [1:0] rgb_evt = 0;                     // Build 12: the last remaster key for Main (1 grading, 2 gradient, 3 save)
reg   [2:0] rgb_evt_n = 0;                   // Build 12: counts the remaster keys - Main acts when it changes
wire        rk_home, rk_pal, rk_grade, rk_grad, rk_save;   // Build 12: WIN+F1/F3/F5/F7/F8 (rtl/rgbkeys.sv)
wire        rk_rew;                          // Build 13: WIN+F2 held - rewind
wire        rk_l2, rk_learn;                 // Build 14: WIN+F4 Level 2 on/off, WIN+F6 learn mode on/off
reg         l2_on = 1, learn_on = 0;
always @(posedge clk_sys) begin
	if (rk_l2)    l2_on    <= ~l2_on;
	if (rk_learn) learn_on <= ~learn_on;
end
wire [10:0] rk_key;                          // Build 12: the keyboard without the held-back WIN+F keys
`endif
reg ntsc_prev = 0;

always @(posedge clk_sys) begin
	integer reset_counter;
	reg old_download;
	reg do_erase = 1;

	// Bringing ntsc_r back into clk_sys domain
	ntsc_sys1 <= ntsc_r;
	ntsc <= ntsc_sys1;
	// Detect pal/ntsc switch
	ntsc_prev <= ntsc;
	exact_sys1 <= exact_r;
	exact <= exact_sys1;
	exact_prev <= exact;

	reset_n <= !reset_counter;
	old_download <= ioctl_download;

	if (RESET | status[0] | status[17] | buttons[1] | hk_reset | hk_wipe | !pll_locked | (ntsc_prev != ntsc) | (exact_prev != exact)) begin
		if(RESET | hk_wipe) do_erase <= 1;
		reset_counter <= 100000;
	end
	else if(~old_download & ioctl_download & load_prg & ~status[50]) begin
		do_erase <= 1;
		reset_wait <= 1;
		reset_counter <= 255;
	end
	else if (ioctl_download & (load_crt | load_rom)) begin
		do_erase <= 1;
		reset_counter <= 255;
	end
	else if ((ioctl_download || inj_meminit) & ~reset_wait);
	else if (erasing) force_erase <= 0;
	else if (!reset_counter) begin
		do_erase <= 0;
		if(reset_wait && c64_addr == 'hFFCF) reset_wait <= 0;
	end
	else begin
		reset_counter <= reset_counter - 1;
		if (reset_counter == 100 && (~status[24] | do_erase)) force_erase <= 1;
	end
end

wire [15:0] joyA,joyB,joyC,joyD;
wire [15:0] joy = joyA | joyB | joyC | joyD;

wire [127:0] status;
wire        forced_scandoubler;

wire        ioctl_wr;
wire        ioctl_rd;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;
wire  [7:0] ioctl_din;
wire  [7:0] ioctl_index;
wire        ioctl_download;
wire        ioctl_upload;
wire        tape_ioctl_wait;
wire [31:0] ioctl_file_ext;

wire [31:0] sd_lba[2];
wire  [5:0] sd_blk_cnt[2];
wire  [1:0] sd_rd;
wire  [1:0] sd_wr;
wire  [1:0] sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[2];
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire [31:0] img_size;
wire        img_readonly;

wire [24:0] ps2_mouse;
wire [10:0] ps2_key;
wire  [1:0] buttons;
wire [21:0] gamma_bus;

wire        tape_play;
wire        tape_key_rew;
wire        tape_key_stop;
wire        tape_key_ff;
wire        tape_key_counter_reset;

wire  [7:0] pd1,pd2,pd3,pd4;

wire [64:0] RTC;

// OCTOPHONIC OS: Main talks to the mailbox (rtl/octovic/octo_os.sv) over hps_io's EXT_BUS
wire [35:0] EXT_BUS;
wire        os_ext_act;
wire [15:0] os_ext_dout;
assign EXT_BUS[32]   = os_ext_act;
`ifdef RGB256
// C64RGB 256 (Fix 60): the mailbox's poll word ($6Fxx) also says b1 "this is the C64RGB 256 core" and
// b2 "SHIFT+F1 held: back to the Octophonic core, please" (Main's octophonic-rgb256.patch);
// Build 12: b4-b3 the last remaster key (1 grading, 2 gradient strength, 3 save the pack), b7-b5 a count
// of them - Main acts on each new count
assign EXT_BUS[15:0] = os_ext_dout | ((os_ext_dout[15:8] == 8'h6F) ? {8'd0, rgb_evt_n, rgb_evt, rgb_home, 2'b10} : 16'd0);
`else
assign EXT_BUS[15:0] = os_ext_dout;
`endif

hps_io #(.CONF_STR(CONF_STR), .VDNUM(2), .BLKSZ(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(EXT_BUS),

	.joystick_0(joyA),
	.joystick_1(joyB),
	.joystick_2(joyC),
	.joystick_3(joyD),

	.paddle_0(pd1),
	.paddle_1(pd2),
	.paddle_2(pd3),
	.paddle_3(pd4),

	.status(status),
`ifdef RGB256
	.status_in(rgb_status_in),
	.status_set(rgb_status_set),
`endif
	.status_menumask({~status[54], ezfl_mod || ezfl_save_en, cart_ezfl, ~status[69], ~status[66], status[58], (status[47:46] != 2'd1), status[16], status[13], tap_loaded, 1'b0, |vcrop, status[56]}), .buttons(buttons), .sdram_sz(sdram_sz),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.RTC(RTC),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_file_ext(ioctl_file_ext),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_upload_req(ezfl_save),
	.ioctl_upload_index(ezfl_idx),
	.ioctl_upload(ioctl_upload),
	.ioctl_din(ioctl_din),
	.ioctl_rd(ioctl_rd),
	.ioctl_wait(ioctl_req_wr|ioctl_req_rd|reset_wait|tape_ioctl_wait)
);

wire load_prg   = ioctl_index == 'h01;
wire load_raw   = ioctl_index == 'h0A;    // OCTOPHONIC OS: straight into RAM - no reset, no BASIC pointers
wire load_crt   = ioctl_index == 'h41 || ioctl_index == 5;
wire load_reu   = ioctl_index == 'h81;
wire load_tap   = ioctl_index == 'hC1;
wire load_flt   = ioctl_index == 7;
wire load_rom   = ioctl_index == 8;
wire load_c1581 = ioctl_index == 9;

// OCTOPHONIC: MY CHIPS - Neal's own SID chips, measured off his C64 Reloaded MK2 (chips/, docs/CHIPS.md).
// Fix 81: three chips loaded at once (file indexes 2, 3 and 6: chips A, B and C) and each of the eight SIDs
// plays whichever the My Chips page says - rtl/sid/chip_slots.sv
wire        chip_we;
wire        chip_wside;
wire  [1:0] chip_wtbl;
wire [11:0] chip_widx;
wire  [7:0] chip_wdata;
wire        chip_crv_wr;
wire [11:0] chip_crv_addr;
wire [15:0] chip_crv_data;
wire  [7:0] sid_ver;
wire [15:0] sid_cfg;
wire  [7:0] chip_on, chip_bk, chip_fc;
chip_slots chip_slots
(
	.clk(clk_sys),
	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_index(ioctl_index),
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.enable(~status[101]),
	.slot_opt(status[125:110]),
	.menu_ver({status[16], status[13]}),
	.menu_cfg({status[68:67], status[65:64]}),
	.chip_we(chip_we),
	.chip_wbank(chip_wside),
	.chip_wtbl(chip_wtbl),
	.chip_widx(chip_widx),
	.chip_wdata(chip_wdata),
	.crv_wr(chip_crv_wr),
	.crv_addr(chip_crv_addr),
	.crv_data(chip_crv_data),
	.sid_ver(sid_ver),
	.sid_cfg(sid_cfg),
	.chip_on(chip_on),
	.chip_bk(chip_bk),
	.chip_fc(chip_fc),
	.loaded()
);

wire game;
wire exrom;
wire io_rom;
wire cart_ce;
wire cart_we;
wire nmi;
wire cart_oe;
wire IOF_rd;
wire  [7:0] cart_data;
wire  [7:0] cart_wrdata;
wire [24:0] cart_addr;
wire cart_mem_req;

cartridge cartridge
(
	.clk32(clk_sys),
	.reset_n(reset_n),

	.cart_loading(ioctl_download && load_crt),
	.cart_id(cart_attached ? cart_id : status[52] ? 8'd99 : 8'd255),
	.cart_exrom(cart_exrom),
	.cart_game(cart_game),
	.cart_bank_hi(cart_bank_hi),
	.cart_bank_16k(cart_bank_16k),
	.cart_bank_num(cart_bank_num),
	.cart_bank_addr(ioctl_load_addr[20:13]),
	.cart_bank_wr(cart_hdr_wr),
	.cart_boot(~status[38]),

	.exrom(exrom),
	.game(game),

	.romL(romL),
	.romH(romH),
	.UMAXromH(UMAXromH),
	.IOE(IOE),
	.IOF(IOF),
	.mem_write(ram_we),
	.mem_ce(ram_ce),
	.mem_ce_out(cart_ce),
	.mem_write_out(cart_we),
	.mem_in(sdram_data),
	.mem_out(cart_wrdata),
	.mem_addr(cart_addr),
	.mem_req(cart_mem_req),
	.mem_cycle(io_cycle),
	.IO_rom(io_rom),
	.IO_rd(cart_oe),
	.IO_data(cart_data),
	.addr_in(c64_addr),
	.data_in(c64_data_out),
	.data_out(c64_data_in),

	.freeze_key(freeze_key),
	.mod_key(mod_key),
	.nmi(nmi),
	.nmi_ack(nmi_ack)
);

wire ezfl_save = status[61] | (status[62] & OSD_STATUS & ezfl_mod);
reg  ezfl_mod = 0;
reg  ezfl_idx = 0;
reg  ezfl_save_en = 0;
always @(posedge clk_sys) begin
	reg save_old = 0;
	reg ext_old = 0;

	if(cart_mem_req) ezfl_mod <= 1;
	if(ioctl_download && load_crt) ezfl_mod <= 0;
	if(ioctl_upload) {ezfl_mod, ezfl_save_en} <= 0;
	
	save_old <= ezfl_save;
	if(~save_old & ezfl_save) ezfl_idx <= ~status[61];
	
	ext_old <= ext_crt;
	if(~ext_old & ext_crt) ezfl_save_en <= 1;
end

wire        dma_req;
wire        dma_cycle;
wire [15:0] dma_addr;
wire  [7:0] dma_dout;
wire  [7:0] dma_din;
wire        dma_we;
wire        ext_cycle;

wire [24:0] reu_ram_addr;
wire  [7:0] reu_ram_dout;
wire        reu_ram_we;

wire  [7:0] reu_dout;
wire        reu_irq;

wire        reu_oe  = IOF && reu_cfg;
wire  [1:0] reu_cfg = ~status[54:53];    // OCTOPHONIC: the menu lists 16MB first, so a fresh core has it
wire        reu_wrap = status[63] & reu_cfg[1];   // OCTOPHONIC: no wrap unless asked - a 16MB REU is all one memory, a DMA runs on past each 512K

reu reu
(
	.clk(clk_sys),
	.reset(~reset_n),
	.cfg(reu_cfg),
	.wrap(reu_wrap),

	.dma_req(dma_req),

	.dma_cycle(dma_cycle),
	.dma_addr(dma_addr),
	.dma_dout(dma_dout),
	.dma_din(dma_din),
	.dma_we(dma_we),

	.ram_cycle(ext_cycle),
	.ram_addr(reu_ram_addr),
	.ram_dout(reu_ram_dout),
	.ram_din(sdram_data),
	.ram_we(reu_ram_we),
	
	.cpu_addr(c64_addr),
	.cpu_dout(c64_data_out),
	.cpu_din(reu_dout),
	.cpu_we(ram_we),
	.cpu_cs(IOF),
	
	.irq(reu_irq)
);

reg ext_cycle_d;
always @(posedge clk_sys) ext_cycle_d <= ext_cycle;
wire reu_ram_ce = ~ext_cycle_d & ext_cycle & dma_req;

// rearrange joystick contacts for c64
wire [6:0] joyA_int = joy[8] ? 7'd0 : {joyA[6:4], joyA[0], joyA[1], joyA[2], joyA[3]};
wire [6:0] joyB_int = joy[8] ? 7'd0 : {joyB[6:4], joyB[0], joyB[1], joyB[2], joyB[3]};
wire [6:0] joyC_c64 = joy[8] ? 7'd0 : {joyC[6:4], joyC[0], joyC[1], joyC[2], joyC[3]};
wire [6:0] joyD_c64 = joy[8] ? 7'd0 : {joyD[6:4], joyD[0], joyD[1], joyD[2], joyD[3]};

// swap joysticks if requested
// SNAC DB9 joystick support - C64/Amiga/SMS standard pinout:
//   Pin 1 Up     -> USER_IN[1]  (active low)
//   Pin 2 Down   -> USER_IN[0]  (active low)
//   Pin 3 Left   -> USER_IN[5]  (active low)
//   Pin 4 Right  -> USER_IN[3]  (active low)
//   Pin 5 NC     -> not used
//   Pin 6 Fire A -> USER_IN[2]  (active low, Button 1)
//   Pin 9 Fire B -> USER_IN[6]  (active low, Button 2)
wire [1:0] snac_mode = status[88:87]; // 0=disabled, 1=Joy1, 2=Joy2
wire [6:0] snac_joy  = {1'b0, ~USER_IN[6], ~USER_IN[2],
                        ~USER_IN[3], ~USER_IN[5], ~USER_IN[0], ~USER_IN[1]};
// format: {fire3=0, fireB(Pin9), fireA(Pin6), right(Pin4), left(Pin3), down(Pin2), up(Pin1)}

wire       jswap = ~status[3];     // Fix 14: the default is the swapped ports
wire [6:0] joyA_c64 = (snac_mode == 2'd1) ? snac_joy : (jswap ? joyB_int : joyA_int);
wire [6:0] joyB_c64 = (snac_mode == 2'd2) ? snac_joy : (jswap ? joyA_int : joyB_int);

wire [7:0] paddle_1 = jswap ? pd3 : pd1;
wire [7:0] paddle_2 = jswap ? pd4 : pd2;
wire [7:0] paddle_3 = jswap ? pd1 : pd3;
wire [7:0] paddle_4 = jswap ? pd2 : pd4;

wire       paddle_1_btn = ~joy[8] & (jswap ? joyC[7] : joyA[7]);
wire       paddle_2_btn = ~joy[8] & (jswap ? joyD[7] : joyB[7]);
wire       paddle_3_btn = ~joy[8] & (jswap ? joyA[7] : joyC[7]);
wire       paddle_4_btn = ~joy[8] & (jswap ? joyB[7] : joyD[7]);

wire [1:0] pd12_mode = status[27:26];
wire [1:0] pd34_mode = status[29:28];

reg [24:0] ioctl_load_addr;
reg        ioctl_req_wr;
reg        ioctl_req_rd;

reg  [7:0] cart_id;
reg        cart_bank_hi;
reg        cart_bank_16k;
reg  [7:0] cart_bank_num;
reg        cart_exrom;
reg        cart_game;
reg        cart_attached = 0;
reg        cart_hdr_wr;

reg        force_erase;
reg        erasing;

reg        inj_meminit = 0;

wire       io_cycle;
reg        io_cycle_ce;
reg        io_cycle_we;
reg [24:0] io_cycle_addr;
reg  [7:0] io_cycle_data;

localparam TAP_ADDR = 25'h0400000;
localparam REU_ADDR = 25'h1000000;
localparam CRT_ADDR = 25'h0200000;

wire cart_ezfl = cart_attached && (cart_id == 32 || cart_id ==33);
reg ext_crt = 0;

always @(posedge clk_sys) begin
	reg  [4:0] erase_to;
	reg        old_download;
	reg        erase_cram;
	reg        io_cycleD;
	reg        old_st0 = 0;
	reg        old_meminit;
	reg [15:0] inj_end;
	reg  [7:0] inj_meminit_data;
	reg  [2:0] rd_cyc;
	reg        ioctl_rd_en;
	reg [15:0] cart_blk_len;
	reg  [3:0] cart_hdr_cnt;
	reg  [7:0] cart_id_hi;

	old_download <= ioctl_download;
	io_cycleD <= io_cycle;
	cart_hdr_wr <= 0;
	
	if (~io_cycle & io_cycleD) begin
		io_cycle_ce <= 1;
		io_cycle_we <= 0;
		io_cycle_addr <= tap_play_addr + TAP_ADDR;
		if (ioctl_req_wr) begin
			ioctl_req_wr <= 0;
			io_cycle_we <= 1;
			io_cycle_addr <= ioctl_load_addr;
			ioctl_load_addr <= ioctl_load_addr + 1'b1;
			if (erasing) io_cycle_data <= {8{ioctl_load_addr[6]}};
			else if (inj_meminit) io_cycle_data <= inj_meminit_data;
			else io_cycle_data <= ioctl_data;
		end

		if(ioctl_req_rd) begin
			io_cycle_addr <= ioctl_load_addr;
			ioctl_rd_en <= 1;
		end
	end
	
	if (io_cycle) {io_cycle_ce, io_cycle_we, ioctl_rd_en} <= 0;

	if (ioctl_rd) begin
		if(ioctl_addr == 0) ioctl_load_addr <= CRT_ADDR;
		ioctl_req_rd <= 1;
	end

	rd_cyc <= {rd_cyc[1:0], io_cycle & io_cycle_ce & ioctl_rd_en};
	if(rd_cyc[2]) begin
		ioctl_din <= sdram_data;
		ioctl_req_rd <= 0;
		ioctl_load_addr <= ioctl_load_addr + 1'b1;
	end


	if (ioctl_wr) begin
		if (load_prg | load_raw) begin
			// PRG header
			// Load address low-byte
			if      (ioctl_addr == 0) begin ioctl_load_addr[7:0]  <= ioctl_data; inj_end[7:0]  <= ioctl_data; end
			// Load address high-byte
			else if (ioctl_addr == 1) begin ioctl_load_addr[15:8] <= ioctl_data; inj_end[15:8] <= ioctl_data; end
			else begin ioctl_req_wr <= 1; inj_end <= inj_end + 1'b1; end
		end

		if (load_crt) begin
			if (ioctl_addr == 0) begin
				ioctl_load_addr <= CRT_ADDR;
				cart_blk_len <= 0;
				cart_hdr_cnt <= 0;
			end

			if (ioctl_addr == 8'h16) cart_id_hi <= ioctl_data;
			if (ioctl_addr == 8'h17) cart_id    <= cart_id_hi ? 8'd255 : ioctl_data;
			if (ioctl_addr == 8'h18) cart_exrom <= ioctl_data[0];
			if (ioctl_addr == 8'h19) cart_game  <= ioctl_data[0];

			if (ioctl_addr >= 8'h40) begin
				if (!cart_blk_len || cart_hdr_cnt) begin
					cart_hdr_cnt <= cart_hdr_cnt + 1'b1;
					if (cart_hdr_cnt == 6)  cart_blk_len  <= {ioctl_data, 8'h00};
					if (cart_hdr_cnt == 11) cart_bank_num <= ioctl_data;
					if (cart_hdr_cnt == 12) cart_bank_hi  <= ioctl_data > 8'h80;
					if (cart_hdr_cnt == 14) cart_bank_16k <= ioctl_data > 8'h20;
					if (cart_hdr_cnt == 15) cart_hdr_wr   <= 1;
				end
				else begin
					cart_blk_len <= cart_blk_len - 1'b1;
					ioctl_req_wr <= 1;
				end
			end
		end
		
		if (load_tap) begin
			if (ioctl_addr == 0)  ioctl_load_addr <= TAP_ADDR;
			ioctl_req_wr <= 1;
		end

		if (load_reu) begin
			if (ioctl_addr == 0) ioctl_load_addr <= REU_ADDR;
			ioctl_req_wr <= 1;
		end
	end
	
	if (old_download != ioctl_download && load_crt) begin
		cart_attached <= old_download;
		erase_cram <= 1;
		ext_crt <= ioctl_download && (ioctl_file_ext == ".CRT");
	end 

	// meminit for RAM injection
	if (old_download != ioctl_download && load_prg && !inj_meminit) begin
		inj_meminit <= 1;
		ioctl_load_addr <= 0;
	end

	if (inj_meminit) begin
		if (!ioctl_req_wr) begin
			// check if done
			if (ioctl_load_addr == 'h100) begin
				inj_meminit <= 0;
			end
			else begin
				ioctl_req_wr <= 1;
				
				// Initialize BASIC pointers to simulate the BASIC LOAD command
				case(ioctl_load_addr)
					// TXT (2B-2C)
					// Set these two bytes to $01, $08 just as they would be on reset (the BASIC LOAD command does not alter these)
					'h2B: inj_meminit_data <= 'h01;
					'h2C: inj_meminit_data <= 'h08;

					// SAVE_START (AC-AD)
					// Set these two bytes to zero just as they would be on reset (the BASIC LOAD command does not alter these)
					'hAC, 'hAD: inj_meminit_data <= 'h00;
					
					// VAR (2D-2E), ARY (2F-30), STR (31-32), LOAD_END (AE-AF)
					// Set these just as they would be with the BASIC LOAD command (essentially they are all set to the load end address)
					'h2D, 'h2F, 'h31, 'hAE: inj_meminit_data <= inj_end[7:0];
					'h2E, 'h30, 'h32, 'hAF: inj_meminit_data <= inj_end[15:8];
					
					default: begin
						ioctl_req_wr <= 0;
						
						// advance the address
						ioctl_load_addr <= ioctl_load_addr + 1'b1;
					end
				endcase
			end
		end
	end

	old_meminit <= inj_meminit;
	start_strk  <= old_meminit & ~inj_meminit;
	
	old_st0 <= status[17];
	if (~old_st0 & status[17]) cart_attached <= 0;
	
	if (!erasing && force_erase) begin
		erasing <= 1;
		ioctl_load_addr <= 0;
	end

	if (erasing && !ioctl_req_wr) begin
		erase_to <= erase_to + 1'b1;
		if (&erase_to) begin
			if (ioctl_load_addr < ({erase_cram, 16'hFFFF}))
				ioctl_req_wr <= 1;
			else begin
				erasing <= 0;
				erase_cram <= 0;
			end
		end
	end
end

// Fix 58: hold SHIFT+F1 (KERNAL), F2 (RUN/STOP+RESTORE), F4 (wipe and restart)
wire       hkb_busy, hkb_stb;
wire [9:0] hkb_code;
hotkey_break hotkey_break (.clk(clk_sys), .start(hk_brk), .busy(hkb_busy), .stb(hkb_stb), .code(hkb_code));

`ifdef RGB256
// Build 12: the remaster keys (WIN+F1/F3/F5/F7/F8) - held back from the C64, so no game ever sees them
rgbkeys rgbkeys (.clk(clk_sys), .ps2_key(ps2_key), .key_out(rk_key),
                 .home(rk_home), .pal(rk_pal), .grade(rk_grade), .grad(rk_grad), .save(rk_save), .rew(rk_rew), .l2(rk_l2), .learn(rk_learn));
wire [10:0] kb_in = rk_key;
`else
wire [10:0] kb_in = ps2_key;
`endif

// Fix 74: the SHIFT+F1-F4 hot keys sit in the keyboard stream to the C64 - a held one never reaches the game,
// a tap is sent on as a short real key press (rtl/hotkeys.sv)
wire [10:0] c64_ps2;
hotkeys hotkeys (.clk(clk_sys), .ps2_key(kb_in), .key_out(c64_ps2), .kernal(hk_kernal), .brk(hk_brk), .wipe(hk_wipe), .spare(hk_spare));

reg        start_strk = 0;
reg        reset_keys = 0;
reg [10:0] key = 0;
always @(posedge clk_sys) begin
	reg  [3:0] act = 0;
	reg        joy_finish = 0;
	reg        hkb_was = 0;
	reg [17:0] joy_last = 0;
	reg [17:0] joy_key;
	int        to;

	reset_keys <= 0;

	joy_key =(joy[9:8] == 3) ?
				(joy[0] ? 18'h005 : joy[1] ? 18'h006 : joy[2] ? 18'h004 : joy[3] ? 18'h00C  :
				 joy[4] ? 18'h003 : joy[5] ? 18'h00B : joy[6] ? 18'h083 : joy[7] ? 18'h00A  : 18'h0):
				(joy[9]) ?
				(joy[0] ? 18'h016 : joy[1] ? 18'h01E : joy[2] ? 18'h026 : joy[3] ? 18'h025  :
			    joy[4] ? 18'h02E : joy[5] ? 18'h045 : joy[6] ? 18'h035 : joy[7] ? 18'h031  : 18'h0):
				(joy[0] ? 18'h174 : joy[1] ? 18'h16B : joy[2] ? 18'h172 : joy[3] ? 18'h175  : 
				 joy[4] ? 18'h05A : joy[5] ? 18'h029 : joy[6] ? 18'h076 : joy[7] ? 18'h2276 : 18'h0);
	
	if(~reset_n) {joy_finish, act} <= 0;

	hkb_was <= hkb_busy;
	if(hkb_busy ^ hkb_was) reset_keys <= 1;   // keys let go meanwhile can't stick
	if(hkb_busy) begin              // Fix 58: RUN/STOP+RESTORE being typed
		if(hkb_stb) begin
			key[9:0] <= hkb_code;
			key[10]  <= ~key[10];
		end
	end
	else if(joy[9:8]) begin
		joy_finish <= 1;
		if(!joy[7:0] && joy_last) begin
			joy_last <= 0;
			reset_keys <= 1;
		end
		else if(!joy_last[8:0] && joy_key) begin
			to <= to + 1'd1;
			if(joy_last[17:9] != joy_key[17:9]) begin
				joy_last[17:9] <= joy_key[17:9];
				key <= joy_key[17:9];
				key[9] <= 1;
				key[10] <= ~key[10];
			end
			else if(to > 640000 && joy_last[8:0] != joy_key[8:0]) begin
				joy_last[8:0] <= joy_key[8:0];
				key <= joy_key[8:0];
				key[9] <= 1;
				key[10] <= ~key[10];
			end
		end
		else begin
			to <= 0;
		end
	end
	else if(joy_finish) begin
		joy_last   <= 0;
		key        <= 0;
		key[10]    <= c64_ps2[10];
		joy_finish <= 0;
		reset_keys <= 1;
	end
	else if(act) begin
		to <= to + 1;
		if(to > 1280000) begin
			to <= 0;
			act <= act + 1'd1;
			case(act)
				// PS/2 scan codes
				 1: key <= 'h2d;  // R
				 3: key <= 'h3c;  // U
				 5: key <= 'h31;  // N
				 7: key <= 'h5a;  // <RETURN>
				 9: key <= 'h00;
				10: act <= 0;
			endcase
			key[9]  <= act[0];
			key[10] <= (act >= 9) ? c64_ps2[10] : ~key[10];
		end
	end
	else begin
		to <= 0;
		key <= {c64_ps2[10], c64_ps2[9] & disk_ready, c64_ps2[8:0]};
	end
	if(start_strk & ~status[50]) begin
		act <= 1;
		key <= 0;
	end
end

assign SDRAM_CKE  = 1;

// REWIND (Build 13): the C64's own 64K is read from the rewind unit's copy (m_sel), everything else
// from the SDRAM as before
wire [24:0] sd_addr = io_cycle ? (cart_mem_req ? cart_addr   : io_cycle_addr ) : ext_cycle ? reu_ram_addr : cart_addr;
wire        sd_ce   = io_cycle ? (cart_mem_req ? cart_ce     : io_cycle_ce   ) : ext_cycle ? reu_ram_ce   : cart_ce;
wire        sd_we   = io_cycle ? (cart_mem_req ? cart_we     : io_cycle_we   ) : ext_cycle ? reu_ram_we   : cart_we;
wire  [7:0] sd_din  = io_cycle ? (cart_mem_req ? cart_wrdata : io_cycle_data ) : ext_cycle ? reu_ram_dout : cart_wrdata;
wire  [7:0] sd_dout;
`ifdef RGB256
wire  [7:0] rw_mq;
wire        rw_msel;
wire  [7:0] sdram_data = rw_msel ? rw_mq : sd_dout;
`else
wire  [7:0] sdram_data = sd_dout;
`endif
sdram sdram
(
	.sd_addr(SDRAM_A),
	.sd_data(SDRAM_DQ),
	.sd_ba(SDRAM_BA),
	.sd_cs(SDRAM_nCS),
	.sd_we(SDRAM_nWE),
	.sd_ras(SDRAM_nRAS),
	.sd_cas(SDRAM_nCAS),
	.sd_clk(SDRAM_CLK),
	.sd_dqm({SDRAM_DQMH,SDRAM_DQML}),

	.clk(clk64),
	.init(~pll_locked),
	.refresh(refresh),
	.addr(sd_addr),
	.ce  (sd_ce),
	.we  (sd_we),
	.din (sd_din),
	.dout(sd_dout)
);

wire  [7:0] c64_data_out;
wire  [7:0] c64_data_in;
wire [15:0] c64_addr;
wire        c64_pause;
wire        refresh;
wire        ram_ce;
wire        ram_we;
wire        nmi_ack;
wire        freeze_key;
wire        mod_key;

wire        IOE;
wire        IOF;
wire        romL;
wire        romH;
wire        UMAXromH;

wire [17:0] audio_l,audio_r;
wire  [7:0] r,g,b;
wire  [7:0] vr, vg, vb;                    // the picture to the output (C64RGB 256: recoloured)
wire        vsync_vic;                     // the VIC's own vertical sync

`ifdef RGB256
// ------------------------------------------------------------------ C64RGB 256 (Fix 60, docs/RGB256.md)
wire  [3:0] rgb_index;
wire [28:0] rgb_tag;
wire [23:0] rc_rgb;
wire  [3:0] rc_npal;
wire        rc_loaded;
wire  [3:0] rc_sel = status[108:105];      // 0-7 a palette, 8 (or more) off
rgb256 recolour
(
	.clk(clk_sys),
	.ld_download(ioctl_download && ioctl_index == 8'd4),
	.ld_wr(ioctl_wr),
	.ld_addr(ioctl_addr),
	.ld_data(ioctl_data),
	.index(rm_index),
	.tag(rm_tag),
	.ovr(rm_ovr),
	.ovr_slot(rm_slot),
	.palette(rc_sel[2:0]),
	.npal(rc_npal),
	.rgb(rc_rgb),
	.loaded(rc_loaded)
);
wire rc_on = rc_loaded && !rc_sel[3] && (rc_sel[2:0] < rc_npal[2:0] || rc_npal[3]);

// ------------------------------------------------------------------ LEVEL 2 REMASTER (Build 14: rtl/remaster.sv)
// The VIC's pixels pass through the remaster unit and come out 16 raster lines later (the vertical sync
// with them), as an index and tag for the recolour unit, or as a slot of the pack's palette (a redrawn
// block or sprite). The stock colours are made here from the same late index.
wire  [25:0] l2_pix;
wire [183:0] l2_spr;
wire   [1:0] l2_bank;
wire   [3:0] rm_index;
wire  [28:0] rm_tag;
wire         rm_vsync, rm_ovr, rm_ok;
wire   [7:0] rm_slot;
wire  [15:0] rm_addr, rm_learned;
wire         rm_req, rm_ack;
wire   [7:0] rm_q;
reg          rm_reload = 0, rm_dl_d = 0;
always @(posedge clk_sys) begin
	rm_dl_d   <= ioctl_download && ioctl_index == 8'd4;
	rm_reload <= rm_dl_d && !(ioctl_download && ioctl_index == 8'd4);   // a pack has gone in: Main put the whole file in the DDR3 first
end
remaster remaster
(
	.clk(clk_sys),
	.reset(~pll_locked),
	.on(l2_on & rc_on),
	.learn(learn_on),
	.reload(rm_reload),
	.index(rgb_index), .tag(rgb_tag), .l2_pix(l2_pix), .l2_spr(l2_spr), .bank(l2_bank), .vsync_in(vsync_vic),
	.d_index(rm_index), .d_tag(rm_tag), .d_vsync(rm_vsync), .ovr(rm_ovr), .ovr_slot(rm_slot),
	.x_addr(rm_addr), .x_req(rm_req), .x_ack(rm_ack), .x_q(rm_q),
	.ddr_addr(rm_ddram_addr), .ddr_burstcnt(rm_ddram_burstcnt), .ddr_rd(rm_ddram_rd), .ddr_we(rm_ddram_we),
	.ddr_din(rm_ddram_din), .ddr_be(rm_ddram_be), .ddr_busy(rm_ddram_busy), .ddr_dout(DDRAM_DOUT), .ddr_ready(rm_ddram_ready),
	.l2_ok(rm_ok), .lcount(rm_learned)
);
wire [7:0] sr, sg, sb;
fpga64_rgbcolor stock_colours (.palette(status[84:82]), .index(rm_index), .r(sr), .g(sg), .b(sb));
reg [23:0] stock_d1, stock_d2, stock_d3;      // (in step with the recolour unit's three clocks)
always @(posedge clk_sys) begin stock_d1 <= {sr, sg, sb}; stock_d2 <= stock_d1; stock_d3 <= stock_d2; end
assign {vr, vg, vb} = rc_on ? rc_rgb : (rm_tag[28:27] == 2'd3) ? 24'd0 : stock_d3;

// WIN+F3: the next palette (1, 2, ... the pack's last, Off, 1 ...) - set in the OSD's status, so
// the OSD shows it and it is saved with the core's settings (Build 12: was SHIFT+F3, which the game saw as F4)
always @(posedge clk_sys) begin
	rgb_status_set <= 0;
	if (rk_pal && rc_loaded) begin
		rgb_status_in <= status;
		rgb_status_in[108:105] <= (rc_sel[3] || rc_npal == 0) ? 4'd0 :
		                          ({1'b0, rc_sel[2:0]} + 4'd1 >= rc_npal) ? 4'd8 : rc_sel + 4'd1;
		rgb_status_set <= 1;
	end
end

// SHIFT+F1 held: ask Main for the Octophonic core (the mailbox's poll word, b2). With no Main to answer
// within ~4 s (no Octophonic OS on the card), the KERNAL reset as in the Octophonic core.
reg [26:0] rgb_home_t = 0;
reg        rgb_home_rst = 0;
always @(posedge clk_sys) begin
	rgb_home_rst <= 0;
	if (hk_kernal | rk_home) begin rgb_home <= 1; rgb_home_t <= 0; end
	else if (rgb_home) begin
		rgb_home_t <= rgb_home_t + 1'd1;
		if (&rgb_home_t) begin rgb_home <= 0; rgb_home_rst <= 1; end
	end
end
assign hk_reset = rgb_home_rst;

// Build 12: WIN+F5/F7/F8 - for Main (the poll word): it remakes the pack (grading, gradient strength) or saves it
always @(posedge clk_sys) begin
	if (rk_grade | rk_grad | rk_save) begin
		rgb_evt   <= rk_save ? 2'd3 : rk_grad ? 2'd2 : 2'd1;
		rgb_evt_n <= rgb_evt_n + 1'd1;
	end
end
`else
assign {vr, vg, vb} = {r, g, b};
assign hk_reset = hk_kernal;
`endif
wire [23:0] vic_rgb;                       // SPLIT SCREENS: the VIC's picture alone, in step with r/g/b
wire        split = status[102];
wire        quarter;                       // FINE SCROLL (Fix 42): OctoVIC's quarter pixels reach the output (set below)
assign VGA2_EN = split;                    // SPLIT SCREENS: the VGA output shows the VIC alone

wire        ntsc_req = status[2];

// OCTOPHONIC Fix 48: the PLL mode (see rtl/pal50.sv)
wire exact_req = ~status[104];
pll_mode pll_mode
(
	.clk(CLK_50M),
	.ntsc_req(ntsc_req),
	.exact_req(exact_req),
	.osd_status(OSD_STATUS),
	.cfg_waitrequest(cfg_waitrequest),
	.cfg_write(cfg_write),
	.cfg_address(cfg_address),
	.cfg_data(cfg_data),
	.close_osd(close_osd_pll),
	.ntsc_r(ntsc_r),
	.exact_r(exact_r)
);
always @(posedge CLK_50M) close_osd <= close_osd_pll;

`ifdef RGB256
// ------------------------------------------------------------------ REWIND (Fix 61, Build 13: rtl/rewind.sv)
wire         rw_tick, rw_freeze, rw_ld, rw_io_wr, rw_vic_we, rw_sid_we, rw_col_we;
wire   [8:0] rw_ry;
wire [175:0] rw_cpu_o, rw_cpu_i;
wire [319:0] rw_cia1_o, rw_cia2_o, rw_cia1_i, rw_cia2_i;
wire   [3:0] rw_io_sel, rw_col_old, rw_col_data;
wire   [9:0] rw_io_addr, rw_col_addr;
wire   [7:0] rw_io_data, rw_vic_data, rw_sid_data;
wire   [5:0] rw_vic_addr;
wire   [4:0] rw_sid_addr;
wire   [1:0] rw_sid_cs;
wire         rw_active, rw_err;
wire  [11:0] rw_frames;
// no rewind (and no history kept) across a reset, a file loading or the disk drive at work
// (the drive's own side of the serial bus, not the C64's: a game is free to wiggle its CIA 2 port)
reg          rw_drv_busy = 0;
always @(posedge clk_sys) begin
	reg        clk_d, data_d;
	reg [23:0] to = 0;
	clk_d  <= drive_iec_clk_o;
	data_d <= drive_iec_data_o;
	if ((clk_d != drive_iec_clk_o) || (data_d != drive_iec_data_o) || drive_led[0]) to <= 24'd16000000;   // 0.5 s
	else if (to != 0) to <= to - 1'd1;
	rw_drv_busy <= (to != 0);
end
// A bank-switching cartridge's banks are not saved: each access to its registers ($DExx/$DFxx) drops the
// history, and it starts again half a second after the last one. So a game that copies itself out of
// its cartridge and switches it off (Magic Desk, Ocean ...) rewinds once it is running; one that keeps
// using its banks while it plays does not. A plain 8K or 16K cartridge has no banks. The REU's registers
// are not saved either: no rewind across an REU transfer.
reg          rw_cart_busy = 0;
always @(posedge clk_sys) begin
	reg [23:0] to = 0;
	if (cart_attached && cart_id != 8'd0 && (IOE | IOF)) to <= 24'd16000000;
	else if (to != 0) to <= to - 1'd1;
	rw_cart_busy <= (to != 0);
end
wire         rw_block = ~reset_n | ioctl_download | erasing | inj_meminit | reset_wait | rw_drv_busy | c64_pause | rw_cart_busy | dma_req;
reg          rw_hold = 0;
always @(posedge clk_sys) rw_hold <= rk_rew | joy[10];

rewind rewind
(
	.clk(clk_sys),
	.reset(~pll_locked),
	.enable(~status[109]),
	.hold(rw_hold),
	.block(rw_block),
	.busy_dma(dma_req),

	.tick(rw_tick), .ry(rw_ry), .freeze(rw_freeze),
	.cpu_o(rw_cpu_o), .cia1_o(rw_cia1_o), .cia2_o(rw_cia2_o),
	.cpu_i(rw_cpu_i), .cia1_i(rw_cia1_i), .cia2_i(rw_cia2_i), .ld(rw_ld),
	.io_wr(rw_io_wr), .io_sel(rw_io_sel), .io_addr(rw_io_addr), .io_data(rw_io_data), .col_old(rw_col_old),
	.vic_we(rw_vic_we), .vic_addr(rw_vic_addr), .vic_data(rw_vic_data),
	.sid_we(rw_sid_we), .sid_cs(rw_sid_cs), .sid_addr(rw_sid_addr), .sid_data(rw_sid_data),
	.col_we(rw_col_we), .col_addr(rw_col_addr), .col_data(rw_col_data),

	.m_addr(sd_addr), .m_ce(sd_ce), .m_we(sd_we), .m_din(sd_din), .m_main(~io_cycle & ~ext_cycle),
	.m_q(rw_mq), .m_sel(rw_msel),

	.x_addr(rm_addr), .x_req(rm_req), .x_ack(rm_ack), .x_q(rm_q),
	.ddr_addr(rwd_ddram_addr), .ddr_burstcnt(rwd_ddram_burstcnt), .ddr_rd(rwd_ddram_rd), .ddr_we(rwd_ddram_we),
	.ddr_din(rwd_ddram_din), .ddr_be(rwd_ddram_be), .ddr_busy(rwd_ddram_busy), .ddr_dout(DDRAM_DOUT),
	.ddr_ready(rwd_ddram_ready),

	.active(rw_active), .frames(rw_frames), .err(rw_err)
);

wire [2:0] rw_ovl_color;
rewind_osd rewind_osd
(
	.clk(clk_sys), .ce(ce_sys), .hblank(hblank), .vblank(vblank),
	.on(rw_active), .err(rw_err), .frames(rw_frames), .pixel_color(rw_ovl_color)
);

fpga64_sid_iec #(.REWIND(1)) fpga64
`else
wire [2:0] rw_ovl_color = 3'd0;
wire       rw_active = 1'b0;
fpga64_sid_iec fpga64
`endif
(
	.clk32(clk_sys),
	.reset_n(reset_n),
	.pause(freeze),
	.pause_out(c64_pause),
	.bios(status[15:14]),
	
	.turbo_mode({(status[47:46] == 2'd2) & ~disk_access, status[47:46] == 2'd0}),   // OCTOPHONIC V1.1: C128 (a program turns turbo on at $D030) the default
	.turbo_speed(status[49:48]),

	.ps2_key(key),
	.kbd_reset((~reset_n & ~status[1]) | reset_keys),
	.shift_mod(~status[60:59]),

	.ramAddr(c64_addr),
	.ramDout(c64_data_out),
	.ramDin(c64_data_in),
	.ramCE(ram_ce),
	.ramWE(ram_we),

	.vic_variant(status[35:34]),
	.ntscmode(ntsc),
	.exact50(exact),
	.sysinfo({sdram_sz[15], 1'b0, reu_cfg, 2'b00, sdram_sz[1:0]}),   // Fix 59: the spec page
	.hsync(hsync),
	.vsync(vsync_vic),
	.palette(status[84:82]),
	.r(r),
	.g(g),
	.b(b),
`ifdef RGB256
	.rgb_index(rgb_index),
	.rgb_tag(rgb_tag),
	.l2_pix(l2_pix),
	.l2_spr(l2_spr),
	.l2_bank(l2_bank),
`endif
	.vic_rgb_out(vic_rgb),
	.split(split),
	.quarter(quarter),

	.game(game),
	.exrom(exrom),
	.UMAXromH(UMAXromH),
	.irq_n(1),
	.nmi_n(~nmi),
	.nmi_ack(nmi_ack),
	.freeze_key(freeze_key),
	.tape_play(tape_play),
	.tape_rew(tape_key_rew),
	.tape_stop(tape_key_stop),
	.tape_ff(tape_key_ff),
	.tape_reset_counter(tape_key_counter_reset),
	.mod_key(mod_key),
	.roml(romL),
	.romh(romH),
	.ioe(IOE),
	.iof(IOF),
	.io_rom(io_rom),
	.io_ext(cart_oe | reu_oe | opl_en),
	.io_data(cart_oe ? cart_data : reu_oe ? reu_dout : opl_dout),
	
	.dma_req(dma_req),
	.dma_cycle(dma_cycle),
	.dma_addr(dma_addr),
	.dma_dout(dma_dout),
	.dma_din(dma_din),
	.dma_we(dma_we),
	.irq_ext_n(~reu_irq),

	.cia_mode(status[45]),

	.joya({(pd12_mode && !joy[9:8]) ? joyA_c64[6:5] : 2'b00, joyA_c64[4:0] | {1'b0, pd12_mode[1] & paddle_2_btn, pd12_mode[1] & paddle_1_btn, 2'b00} | {pd12_mode[0] & mouse_btn[0], 3'b000, pd12_mode[0] & mouse_btn[1]}}),
	.joyb({(pd34_mode && !joy[9:8]) ? joyB_c64[6:5] : 2'b00, joyB_c64[4:0] | {1'b0, pd34_mode[1] & paddle_4_btn, pd34_mode[1] & paddle_3_btn, 2'b00} | {pd34_mode[0] & mouse_btn[0], 3'b000, pd34_mode[0] & mouse_btn[1]}}),

	.pot1(pd12_mode[1] ? paddle_1 : pd12_mode[0] ? mouse_x : {8{joyA_c64[5]}}),
	.pot2(pd12_mode[1] ? paddle_2 : pd12_mode[0] ? mouse_y : {8{joyA_c64[6]}}),
	.pot3(pd34_mode[1] ? paddle_3 : pd34_mode[0] ? mouse_x : {8{joyB_c64[5]}}),
	.pot4(pd34_mode[1] ? paddle_4 : pd34_mode[0] ? mouse_y : {8{joyB_c64[6]}}),

	.io_cycle(io_cycle),
	.ext_cycle(ext_cycle),
	.refresh(refresh),

	.sid_ld_clk(clk_sys),
	.sid_ld_addr(sid_ld_addr),
	.sid_ld_data(sid_ld_data),
	.sid_ld_wr(sid_ld_wr),
	.sid_mode(status[22:20]),
	.sid_filter(2'b11),
	.sid_ver(sid_ver),                    // MY CHIPS (Fix 81): each SID its own model
	.sid_cfg(sid_cfg),                    //   ...and its own filter curve (a SID with a chip's curve takes no Fc offset: sid_top)
	.sid_fc_off_l(status[66] ? (13'h600 - {status[72:70],7'd0}) : 13'd0),
	.sid_fc_off_r(status[69] ? (13'h600 - {status[75:73],7'd0}) : 13'd0),
	.chip_we(chip_we),
	.chip_wside(chip_wside),
	.chip_wtbl(chip_wtbl),
	.chip_widx(chip_widx),
	.chip_wdata(chip_wdata),
	.chip_on(chip_on),
	.chip_bk(chip_bk),
	.chip_fc(chip_fc),
	.sid_digifix(~status[37]),
	.sid_quad(~status[98]),               // OCTOPHONIC (8 SIDs, 4 SIDs, Off): SIDs at $D400, $D420, $D500, $D520
	.sid_oct(status[98:97] == 2'b00),
	.sid_fx_osd(status[100:99]),
	.os_io_enable(EXT_BUS[34]),
	.os_io_strobe(EXT_BUS[33]),
	.os_io_din(EXT_BUS[31:16]),
	.os_ext_act(os_ext_act),
	.os_ext_dout(os_ext_dout),

`ifdef RGB256
	.rw_tick(rw_tick), .rw_ry(rw_ry), .rw_freeze(rw_freeze),
	.rw_cpu_o(rw_cpu_o), .rw_cia1_o(rw_cia1_o), .rw_cia2_o(rw_cia2_o),
	.rw_cpu_i(rw_cpu_i), .rw_cia1_i(rw_cia1_i), .rw_cia2_i(rw_cia2_i), .rw_ld(rw_ld),
	.rw_io_wr(rw_io_wr), .rw_io_sel(rw_io_sel), .rw_io_addr(rw_io_addr), .rw_io_data(rw_io_data), .rw_col_old(rw_col_old),
	.rw_vic_we(rw_vic_we), .rw_vic_addr(rw_vic_addr), .rw_vic_data(rw_vic_data),
	.rw_sid_we(rw_sid_we), .rw_sid_cs(rw_sid_cs), .rw_sid_addr(rw_sid_addr), .rw_sid_data(rw_sid_data),
	.rw_col_we(rw_col_we), .rw_col_addr(rw_col_addr), .rw_col_data(rw_col_data),
`else
	.ogx_ddr_addr(ogx_ddram_addr),
	.ogx_ddr_burstcnt(ogx_ddram_burstcnt),
	.ogx_ddr_rd(ogx_ddram_rd),
	.ogx_ddr_we(ogx_ddram_we),
	.ogx_ddr_din(ogx_ddram_din),
	.ogx_ddr_be(ogx_ddram_be),
	.ogx_ddr_busy(ogx_ddram_busy),
	.ogx_ddr_dout(DDRAM_DOUT),
	.ogx_ddr_dout_ready(ogx_ddram_ready),    // and with 8 (the default): $D480, $D4A0, $D580, $D5A0
`endif
	.audio_l(audio_l),
	.audio_r(audio_r),

	.iec_data_o(c64_iec_data),
	.iec_atn_o(c64_iec_atn),
	.iec_clk_o(c64_iec_clk),
	.iec_data_i(drive_iec_data),
	.iec_clk_i(drive_iec_clk),

	.pb_i(pb_i),
	.pb_o(pb_o),
	.pa2_i(pa2_i),
	.pa2_o(pa2_o),
	.pc2_n_o(pc2_n_o),
	.flag2_n_i(flag2_n_i),
	.sp2_i(sp2_i),
	.sp2_o(sp2_o),
	.sp1_i(sp1_i),
	.sp1_o(sp1_o),
	.cnt2_i(cnt2_i),
	.cnt2_o(cnt2_o),
	.cnt1_i(cnt1_i),
	.cnt1_o(cnt1_o),

	.c64rom_addr(ioctl_addr[13:0]),
	.c64rom_data(ioctl_data),
	.c64rom_wr(load_rom && !ioctl_addr[16:14] && ioctl_download && ioctl_wr),

	.cass_write(cass_write),
	.cass_motor(cass_motor),
	.cass_sense(~tape_adc_act & (use_tape ? cass_sense : cass_rtc)),
	.cass_read(tape_adc_act ? ~tape_adc : cass_read)
);

wire [7:0] mouse_x;
wire [7:0] mouse_y;
wire [1:0] mouse_btn;

c1351 mouse
(
	.clk_sys(clk_sys),
	.reset(~reset_n),

	.ps2_mouse(ps2_mouse),
	
	.potX(mouse_x),
	.potY(mouse_y),
	.button(mouse_btn)
);

wire       c64_iec_clk;
wire       c64_iec_data;
wire       c64_iec_atn;

wire       drive_iec_clk  = drive_iec_clk_o  & ext_iec_clk;
wire       drive_iec_data = drive_iec_data_o & ext_iec_data;

wire [7:0] drive_par_i;
wire       drive_stb_i;
wire [7:0] drive_par_o;
wire       drive_stb_o;
wire       drive_iec_clk_o;
wire       drive_iec_data_o;
wire       drive_reset = ~reset_n | status[6] | (load_c1581 & ioctl_download);

wire [1:0] drive_led;
wire [7:0] drive_track[2];
wire [1:0] drive_we;
wire       disk_ready;

reg [1:0] drive_mounted = 0;
reg [1:0] old_img_mounted;

always @(posedge clk_sys) begin 
	old_img_mounted <= img_mounted;
	if(img_mounted[0]) drive_mounted[0] <= |img_size;
	if(img_mounted[1]) drive_mounted[1] <= |img_size;
end

wire mounted_0 = ~old_img_mounted[0] & img_mounted[0];
wire mounted_1 = ~old_img_mounted[1] & img_mounted[1];
wire img_readonly_wp = img_readonly | (mounted_0 & status[76]) | (mounted_1 & status[77]);

// OCTOPHONIC: one drive (#8) - drive 9's 1541 and 1581 taken out to make room for OctoVIC 2
wire [7:0] drv_track[1];
wire [31:0] drv_lba[1];
wire  [5:0] drv_blk_cnt[1];
wire  [7:0] drv_buff_din[1];
assign drive_track[0] = drv_track[0];  assign drive_track[1] = 8'd0;
assign sd_lba[0] = drv_lba[0];         assign sd_lba[1] = 32'd0;
assign sd_blk_cnt[0] = drv_blk_cnt[0]; assign sd_blk_cnt[1] = 6'd0;
assign sd_buff_din[0] = drv_buff_din[0]; assign sd_buff_din[1] = 8'd0;
assign drive_led[1] = 1'b0;
assign drive_we[1] = 1'b0;
assign sd_rd[1] = 1'b0;
assign sd_wr[1] = 1'b0;

iec_drive #(.DRIVES(1)) iec_drive
(
	.clk(clk_sys),
	.reset(drive_reset | ((!status[58:57]) ? ~drive_mounted[0] : status[58])),

	.ce(drive_ce),

	.iec_atn_i(c64_iec_atn),
	.iec_data_i(c64_iec_data & ext_iec_data),
	.iec_clk_i(c64_iec_clk & ext_iec_clk),
	.iec_data_o(drive_iec_data_o),
	.iec_clk_o(drive_iec_clk_o),

	.pause(c64_pause),

	.img_mounted(img_mounted[0]),
	.img_size(img_size),
	.img_readonly(img_readonly_wp),
	.img_type(&ioctl_index[7:6] ? 2'b11 : 2'b01),
	.drive_rpm(status[80:78]),
	.drive_wobble(status[81]),

	.led(drive_led[0]),
	.out_track(drv_track),
	.out_we(drive_we[0]),
	.disk_ready(disk_ready),

	.par_data_i(drive_par_i),
	.par_stb_i(drive_stb_i),
	.par_data_o(drive_par_o),
	.par_stb_o(drive_stb_o),

	.clk_sys(clk_sys),

	.sd_lba(drv_lba),
	.sd_blk_cnt(drv_blk_cnt),
	.sd_rd(sd_rd[0]),
	.sd_wr(sd_wr[0]),
	.sd_ack(sd_ack[0]),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(drv_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.rom_addr(load_rom ? (ioctl_addr[15:0] - 16'h4000) : {1'b1,ioctl_addr[14:0]}),
	.rom_data(ioctl_data),
	.rom_wr(((load_rom && ioctl_addr[16:14]) || load_c1581) && ioctl_download && ioctl_wr),
	.rom_std(status[14]),

	.DDRAM_BUSY(drv_ddram_busy),
	.DDRAM_BURSTCNT(drv_ddram_burstcnt),
	.DDRAM_ADDR(drv_ddram_addr),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(drv_ddram_ready),
	.DDRAM_RD(drv_ddram_rd),
	.DDRAM_WE(drv_ddram_we),
	.DDRAM_DIN(drv_ddram_din),
	.DDRAM_BE(drv_ddram_be)
	);

// OCTOPHONIC Fix 48: the 1541's 16 MHz enable (unchanged - a fixed fraction of clk_sys, so the drive slows
// with the C64 in Exact 50 Hz and the C64:drive ratio stays exactly as before) and the RTC's real-time one.
wire drive_ce, rtc_ce;
drive_rtc_ce drive_rtc_ce
(
	.clk(clk_sys),
	.ntsc(ntsc),
	.exact(exact),
	.drive_ce(drive_ce),
	.rtc_ce(rtc_ce)
);

wire disk_parport = ~status[44];

reg disk_access;
always @(posedge clk_sys) begin
	reg c64_iec_clk_old, drive_iec_clk_old, drive_stb_i_old, drive_stb_o_old;
	integer to = 0;

	c64_iec_clk_old <= c64_iec_clk;
	drive_iec_clk_old <= drive_iec_clk;
	drive_stb_i_old <= drive_stb_i;
	drive_stb_o_old <= drive_stb_o;
	
	if(((c64_iec_clk_old != c64_iec_clk) || (drive_iec_clk_old != drive_iec_clk)) || 
		(disk_parport && ((drive_stb_i_old != drive_stb_i) || (drive_stb_o_old != drive_stb_o))))
	begin
		disk_access <= 1;
		to <= 16000000; // 0.5s
	end
	else if(to) to <= to - 1;
	else disk_access <= 0;
end

wire ext_iec_en   = status[25];
wire ext_iec_clk  = |snac_mode ? 1'b1 : (USER_IN[2] | ~ext_iec_en);
wire ext_iec_data = |snac_mode ? 1'b1 : (USER_IN[4] | ~ext_iec_en);

assign USER_OUT[2] = |snac_mode ? 1'b1 : ((c64_iec_clk & drive_iec_clk_o)  | ~ext_iec_en);
assign USER_OUT[3] = |snac_mode ? 1'b1 : ((reset_n & ~status[6]) | ~ext_iec_en);
assign USER_OUT[4] = |snac_mode ? 1'b1 : ((c64_iec_data & drive_iec_data_o) | ~ext_iec_en);
assign USER_OUT[5] = |snac_mode ? 1'b1 : (c64_iec_atn | ~ext_iec_en);
assign USER_OUT[6] = '1;


wire hsync;
`ifdef RGB256
wire vsync = rm_vsync;                     // Build 14: the picture is 16 lines late (rtl/remaster.sv), its vertical sync too
`else
wire vsync = vsync_vic;
`endif
wire hblank;
wire vblank;
wire hsync_out;
wire vsync_out;

video_sync sync
(
	.clk32(clk_sys),
	.pause(c64_pause),
	.hsync(hsync),
	.vsync(vsync),
	.ntsc(ntsc),
	.wide(wide),
	.hsync_out(hsync_out),
	.vsync_out(vsync_out),
	.hblank(hblank),
	.vblank(vblank)
);

reg hq2x160;
always @(posedge clk_sys) begin
	reg old_vsync;

	old_vsync <= vsync_out;
	if (!old_vsync && vsync_out) begin
		hq2x160 <= (status[10:8] == 2);
	end
end

// FINE SCROLL (Fix 42): OctoVIC's quarter pixels need the picture taken 4 times a C64 pixel (31.5 MHz,
// every other clk64) - on unless the menu says Off, and only without the scandoubler/HQ2x (their line
// buffers are 768 wide) and without a gamma curve (gamma_corr needs 4 clocks a pixel). STATUS b4 says.
reg  quarter_v;
reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [2:0] div;
	reg       lores;

	div <= div + 1'b1;
	if(&div) lores <= ~lores;
	quarter_v <= quarter;
	ce_pix <= quarter_v ? div[0] : ((~lores | ~hq2x160) && !div);
end

wire scandoubler = status[10:8] || forced_scandoubler;
assign quarter = ~status[103] & ~scandoubler & ~gamma_bus[19];

assign CLK_VIDEO = clk64;
assign VGA_SL    = (status[10:8] > 2) ? status[9:8] - 2'd2 : 2'd0;
assign VGA_F1    = 0;

reg [9:0] vcrop;
reg wide;
always @(posedge CLK_VIDEO) begin
	vcrop <= 0;
	wide <= 0;
	if(HDMI_WIDTH >= (HDMI_HEIGHT + HDMI_HEIGHT[11:1]) && !scandoubler) begin
		if(HDMI_HEIGHT == 480)  vcrop <= 240;
		if(HDMI_HEIGHT == 600)  begin vcrop <= 200; wide <= vcrop_en; end
		if(HDMI_HEIGHT == 720)  vcrop <= 240;
		if(HDMI_HEIGHT == 768)  vcrop <= 256; // NTSC mode has 250 visible lines only!
		if(HDMI_HEIGHT == 800)  begin vcrop <= 200; wide <= vcrop_en; end
		if(HDMI_HEIGHT == 1080) vcrop <= 10'd216;
		if(HDMI_HEIGHT == 1200) vcrop <= 240;
	end
	else if(HDMI_WIDTH >= 1440 && !scandoubler) begin
		// 1920x1440 and 2048x1536 are 4:3 resolutions and won't fit in the previous if statement ( width > height * 1.5 )
		if(HDMI_HEIGHT == 1440) vcrop <= 240;
		if(HDMI_HEIGHT == 1536) vcrop <= 256;
	end
end


wire [1:0] ar = status[5:4];
wire vcrop_en = status[32];
wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? (wide ? 12'd340 : 12'd400) : (ar - 1'd1)),
	.ARY((!ar) ? 12'd300 : 12'd0),
	.CROP_SIZE(vcrop_en ? vcrop : 10'd0),
	.CROP_OFF(0),
	.SCALE(status[31:30])
);

wire freeze_sync;
reg freeze;
always @(posedge clk_sys) begin
	reg old_sync;
	
	old_sync <= freeze_sync;
	if(old_sync ^ freeze_sync) freeze <= OSD_STATUS & status[42];
end

assign HDMI_FREEZE = freeze;

// Snoop DDRAM reads and writes for debug overlay
reg [63:0] dbg_ddram_data = 0;
reg [31:0] dbg_ddram_addr = 0;
reg [31:0] dbg_out_addr   = 0;
reg        dbg_wait_data  = 0;
reg        dbg_valid      = 0;
reg  [7:0] dbg_burst_cnt  = 0;

reg [63:0] dbg_wr_data    = 0;
reg [31:0] dbg_wr_addr    = 0;
reg        dbg_wr_valid   = 0;

always @(posedge clk_sys) begin
    reg old_rd, old_we;

    old_rd <= drv_ddram_rd;
    old_we <= drv_ddram_we;

    dbg_valid <= 0;
    if (~old_rd & drv_ddram_rd) begin
		dbg_ddram_addr <= {3'b0, drv_ddram_addr};
        dbg_burst_cnt <= drv_ddram_burstcnt;
        dbg_wait_data <= 1;
		end

		if (drv_ddram_ready && dbg_wait_data) begin
			dbg_ddram_data <= DDRAM_DOUT;
			dbg_out_addr   <= dbg_ddram_addr;
			dbg_valid      <= 1;

			if (dbg_burst_cnt <= 8'd1) begin
				dbg_wait_data  <= 0;
			end else begin
				dbg_burst_cnt  <= dbg_burst_cnt - 8'd1;
				dbg_ddram_addr <= dbg_ddram_addr + 1'd1;
			end
		end

    dbg_wr_valid <= 0;
    if (~old_we & drv_ddram_we) begin
		dbg_wr_addr <= {3'b0, drv_ddram_addr};
        dbg_wr_data <= drv_ddram_din;
        dbg_wr_valid <= 1;
	end
end

// Allow cursor keys to change debug base addr for overlay
// addr stepsize h008 for cursor up & down
// addr stepsize h100 for cursor left & right
// timed autorepeat and debounce

reg [31:0] dbg_base_addr = 32'h06000000;
reg old_ps2_stb;
reg [23:0] repeat_timer;
reg repeat_active;
reg dir_up;
reg dir_down;
reg dir_left;
reg dir_right;

always @(posedge clk_sys) begin
    old_ps2_stb <= ps2_key[10];

    if (old_ps2_stb != ps2_key[10]) begin
        if (ps2_key[9]) begin
            if (ps2_key[8] && ps2_key[7:0] == 8'h75) begin // Up Arrow
                dbg_base_addr <= dbg_base_addr - 8;
                dir_up <= 1; dir_down <= 0; dir_left <= 0; dir_right <= 0;
                repeat_timer <= 24'd15000000; // ~0.3s delay
                repeat_active <= 1;
            end else if (ps2_key[8] && ps2_key[7:0] == 8'h72) begin // Down Arrow
                dbg_base_addr <= dbg_base_addr + 8;
                dir_up <= 0; dir_down <= 1; dir_left <= 0; dir_right <= 0;
                repeat_timer <= 24'd15000000;
                repeat_active <= 1;
            end else if (ps2_key[8] && ps2_key[7:0] == 8'h6B) begin // Left Arrow
                dbg_base_addr <= dbg_base_addr - 32'h100;
                dir_up <= 0; dir_down <= 0; dir_left <= 1; dir_right <= 0;
                repeat_timer <= 24'd15000000;
                repeat_active <= 1;
            end else if (ps2_key[8] && ps2_key[7:0] == 8'h74) begin // Right Arrow
                dbg_base_addr <= dbg_base_addr + 32'h100;
                dir_up <= 0; dir_down <= 0; dir_left <= 0; dir_right <= 1;
                repeat_timer <= 24'd15000000;
                repeat_active <= 1;
            end else begin
                repeat_active <= 0;
            end
        end else begin
            if ((ps2_key[8] && ps2_key[7:0] == 8'h75 && dir_up) ||
                (ps2_key[8] && ps2_key[7:0] == 8'h72 && dir_down) ||
                (ps2_key[8] && ps2_key[7:0] == 8'h6B && dir_left) ||
                (ps2_key[8] && ps2_key[7:0] == 8'h74 && dir_right)) begin
                repeat_active <= 0;
                dir_up <= 0;
                dir_down <= 0;
                dir_left <= 0;
                dir_right <= 0;
            end
        end
    end else if (repeat_active) begin
        if (repeat_timer == 0) begin
            if (dir_up) dbg_base_addr <= dbg_base_addr - 8;
            if (dir_down) dbg_base_addr <= dbg_base_addr + 8;
            if (dir_left) dbg_base_addr <= dbg_base_addr - 32'h100;
            if (dir_right) dbg_base_addr <= dbg_base_addr + 32'h100;
            repeat_timer <= 24'd2000000; // ~0.04s repeat
        end else begin
            repeat_timer <= repeat_timer - 1'd1;
        end
    end
end

// Drive Overlay display:
//  - three modes: on activity (default), if enabled, debug and off
//  - color coded: green for idle (only shows in "if enabled" and "debug" mode)
//                 yellow for (read) activity (via drive led)
//                 red for write activity (covers writes to disk & flushing to sd)
//  - track number: Full tracks and half tracks (e.g. 33.5)
//  - drive number: (#8, #9)
//  - auto adjusts for pal/ntsc
//
// debug mode captures DDRAM reads/writes:
//  - reads displayed on the left (green), writes on the right (yellow)
//  - rolling buffer (top 8 lines) shows the last 8 reads/writes and addresses
//  - base address captures (botoom 8 lines) shows 8 read/writes starting at base address
//  - base address can be changed in real time with cursor keys (left, right, up, down)
//  - captures live read/writes not memory content, so set address before you expect read/writes (!)
//
//
wire [2:0] drv_ovl_color;

reg [1:0] ce_sys_div = 0;
wire ce_sys = (ce_sys_div == 0);
always @(posedge clk_sys) ce_sys_div <= ce_sys_div + 1'd1;

drv_overlay drv_ovl (
	.clk(clk_sys),
	.ce(ce_sys),
	.hblank(hblank),
	.vblank(vblank),

	.drive_osd_mode(status[86:85]),
	.ntsc(ntsc),
	.drive_led(drive_led),
	.drive_mounted(drive_mounted),
	.drive_track_0(drive_track[0]),
	.drive_track_1(drive_track[1]),
	.drive_we(drive_we),

	.valid(dbg_valid),
	.addr(dbg_out_addr),
	.data(dbg_ddram_data),
	.wr_valid(dbg_wr_valid),
	.wr_addr(dbg_wr_addr),
	.wr_data(dbg_wr_data),
	.base_addr(dbg_base_addr),

	.pixel_color(drv_ovl_color)
);

reg [2:0] ovl_color;
always @(posedge CLK_VIDEO) ovl_color <= tape_ovl_color | drv_ovl_color | rw_ovl_color;

video_mixer_split #(.GAMMA(1)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),

	.hq2x(~status[10] & (status[9] ^ status[8])),
	.scandoubler(scandoubler),
	.gamma_bus(gamma_bus),

	.ce_pix(ce_pix),
	.R((ovl_color & 4) ? 8'hFF : ovl_color ? 8'h00 : vr),
	.G((ovl_color & 2) ? 8'hFF : ovl_color ? 8'h00 : vg),
	.B((ovl_color & 1) ? 8'hFF : ovl_color ? 8'h00 : vb),
	.ALT_R((ovl_color & 4) ? 8'hFF : ovl_color ? 8'h00 : vic_rgb[23:16]),
	.ALT_G((ovl_color & 2) ? 8'hFF : ovl_color ? 8'h00 : vic_rgb[15:8]),
	.ALT_B((ovl_color & 1) ? 8'hFF : ovl_color ? 8'h00 : vic_rgb[7:0]),
	.HSync(hsync_out),
	.VSync(vsync_out),
	.HBlank(hblank),
	.VBlank(vblank),

	.HDMI_FREEZE(HDMI_FREEZE),
	.freeze_sync(freeze_sync),

	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA2_R(VGA2_R),
	.VGA2_G(VGA2_G),
	.VGA2_B(VGA2_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(vga_de)
);

// No Sound Expander (OPL2) in any Octophonic core: its logic and block RAM go to the new
// features (Rewind, scope tools, recolour unit). Nothing of ours uses it, and the stock
// C64 core is still on the card for the few old programs that do. The three wires stay
// (tied off) so the IO and audio mixer below are untouched. (c) 2026 Mong00se
wire        opl_en = 1'b0;
wire [15:0] opl_out = 16'd0;
wire  [7:0] opl_dout = 8'd0;

reg ioe_we, iof_we;
always @(posedge clk_sys) begin
	reg old_ioe, old_iof;

	old_ioe <= IOE;
	ioe_we <= ~old_ioe & IOE & ram_we;

	old_iof <= IOF;
	iof_we <= ~old_iof & IOF & ram_we;
end

reg [11:0] sid_ld_addr = 0;
reg [15:0] sid_ld_data = 0;
reg        sid_ld_wr   = 0;
always @(posedge clk_sys) begin
	sid_ld_wr <= 0;
	if(ioctl_wr && load_flt && ioctl_addr < 6144) begin
		if(ioctl_addr[0]) begin
			sid_ld_data[15:8] <= ioctl_data;
			sid_ld_addr <= ioctl_addr[12:1];
			sid_ld_wr <= 1;
		end
		else begin
			sid_ld_data[7:0] <= ioctl_data;
		end
	end
	// OCTOPHONIC: a chip's filter curve ($4000-$47FF of the .CHP) into Custom 1, 2 or 3 (chip A, B, C: chip_slots.sv)
	if(chip_crv_wr) begin
		sid_ld_data <= chip_crv_data;
		sid_ld_addr <= chip_crv_addr;
		sid_ld_wr   <= 1;
	end
end



//DigiMax
reg [8:0] dac_l, dac_r;
always @(posedge clk_sys) begin
	reg [8:0] dac[4];
	reg [3:0] act;

	if(!status[41:40] || ~reset_n) begin
		dac <= '{0,0,0,0};
		act <= 0;
	end
	else if((status[41] ? iof_we : ioe_we) && ~c64_addr[2]) begin
		dac[c64_addr[1:0]] <= c64_data_out;
		if(c64_data_out) act[c64_addr[1:0]] <= 1;
	end

	// guess mono/stereo/4-chan modes
	if(act<2) begin
		dac_l <= dac[0] + dac[0];
		dac_r <= dac[0] + dac[0];
	end
	else if(act<3) begin
		dac_l <= dac[1] + dac[1];
		dac_r <= dac[0] + dac[0];
	end
	else begin
		dac_l <= dac[1] + dac[2];
		dac_r <= dac[0] + dac[3];
	end
end

localparam [3:0] comp_f1 = 4;
localparam [3:0] comp_a1 = 2;
localparam       comp_x1 = ((32767 * (comp_f1 - 1)) / ((comp_f1 * comp_a1) - 1)) + 1; // +1 to make sure it won't overflow
localparam       comp_b1 = comp_x1 * comp_a1;

function [15:0] compr; input [15:0] inp;
	reg [15:0] v, v1;
	begin
		v  = inp[15] ? (~inp) + 1'd1 : inp;
		v1 = (v < comp_x1[15:0]) ? (v * comp_a1) : (((v - comp_x1[15:0])/comp_f1) + comp_b1[15:0]);
		v  = v1;
		compr = inp[15] ? ~(v-1'd1) : v;
	end
endfunction

reg [15:0] alo,aro;
always @(posedge clk_sys) begin
	reg [16:0] alm,arm;
	reg [15:0] cout;
	reg [15:0] cin;
	
	cin  <= opl_out - {{3{opl_out[15]}},opl_out[15:3]};
	cout <= compr(cin);

	// (REWIND: the SIDs at half volume while the game runs backwards)
	alm <= {cout[15],cout} + (rw_active ? {{2{audio_l[17]}},audio_l[17:3]} : {audio_l[17],audio_l[17:2]}) + {2'b0,dac_l,6'd0} + {cass_snd, 9'd0};
	arm <= {cout[15],cout} + (rw_active ? {{2{audio_r[17]}},audio_r[17:3]} : {audio_r[17],audio_r[17:2]}) + {2'b0,dac_r,6'd0} + {cass_snd, 9'd0};
	alo <= ^alm[16:15] ? {alm[16], {15{alm[15]}}} : alm[15:0];
	aro <= ^arm[16:15] ? {arm[16], {15{arm[15]}}} : arm[15:0];
end

assign AUDIO_L = alo;
assign AUDIO_R = aro;
assign AUDIO_S = 1;
assign AUDIO_MIX = status[19:18];

//------------- TAP / C1530 Datassette -------------------

wire       cass_write;
wire       cass_motor;
wire       cass_sense;
wire       cass_read;
wire       cass_run;
wire       cass_finish;
wire       cass_snd = cass_read & ~cass_run & status[11] & ~cass_finish;

wire       tap_loaded;
wire [24:0] tap_play_addr;
wire [24:0] tap_last_addr;

wire [2:0] tape_ovl_color;

// OCTOPHONIC: the tape (C1530) taken out to make room for OctoVIC 2: no tape, no button pressed
assign tape_ioctl_wait = 1'b0;
assign cass_sense = 1'b1;
assign cass_read = 1'b1;
assign cass_run = 1'b0;
assign cass_finish = 1'b0;
assign tap_loaded = 1'b0;
assign tap_play_addr = 25'd0;
assign tap_last_addr = 25'd0;
assign tape_ovl_color = 3'd0;

reg use_tape;
always @(posedge clk_sys) begin
	integer to = 0;

	if(to) to <= to - 1;
	else use_tape <= status[36];

	if(tap_loaded | ~cass_sense) begin
		use_tape <= 1;
		to <= 128000000; //4s
	end
end

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + (cass_sense ? 4'd1 : 4'd8);
wire tape_led = tap_loaded && (act_cnt[26] ? (~(~cass_sense & cass_motor) && act_cnt[25:18] > act_cnt[7:0]) : act_cnt[25:18] <= act_cnt[7:0]);

wire tape_adc, tape_adc_act;
ltc2308_tape #(.CLK_RATE(32000000)) ltc2308_tape
(
  .clk(clk_sys),
  .ADC_BUS(ADC_BUS),
  .dout(tape_adc),
  .active(tape_adc_act)
);

//------------- USER PORT -----------------

wire [7:0] pb_i, pb_o;
wire       pa2_i, pa2_o;
wire       pc2_n_o;
wire       flag2_n_i;
wire       sp2_i, sp2_o, sp1_o, sp1_i;
wire       cnt2_i, cnt2_o, cnt1_o, cnt1_i;

always_comb begin
	pa2_i       = 1;
	flag2_n_i   = 1;
	sp1_i       = 1;
	sp2_i       = 1;
	cnt1_i      = 1;
	cnt2_i      = 1;
	pb_i        = 8'hFF;
	UART_TXD    = 1;
	UART_RTS    = 0;
	UART_DTR    = 0;
	drive_par_i = 8'hFF;
	drive_stb_i = 1;
	USER_OUT[0] = 1;
	USER_OUT[1] = 1;

	if(disk_parport & disk_access) begin
		drive_par_i = pb_o;
		drive_stb_i = pc2_n_o;
		pb_i        = drive_par_o;
		flag2_n_i   = drive_stb_o;
	end
	else if(status[43]) begin
		UART_TXD  = pa2_o & uart_int;
		flag2_n_i = uart_rxd;
		sp2_i     = uart_rxd;
		pb_i[0]   = uart_rxd;
		UART_RTS  = ~pb_o[1] & uart_int;
		UART_DTR  = ~pb_o[2] & uart_int;
		pb_i[4]   = ~uart_dsr;
		pb_i[6]   = ~uart_cts;
		pb_i[7]   = ~uart_dsr;

		USER_OUT[1] = pa2_o | uart_int;

		if(~status[51]) begin
			UART_TXD = pa2_o & sp1_o & uart_int;
			pb_i[7]  = cnt2_o;
			cnt2_i   = pb_o[7];

			USER_OUT[1] = (pa2_o & sp1_o) | uart_int;
		end
	end
	else begin
		pb_i[5:0] = {!joyD_c64[6:4], !joyC_c64[6:4], pb_o[7] ? ~joyC_c64[3:0] : ~joyD_c64[3:0]};
	end
end

wire uart_int = ~status[33];

reg uart_rxd, uart_dsr, uart_cts;
always @(posedge clk_sys) begin
	reg rxd1, rxd2, dsr1, dsr2, cts1, cts2;

	rxd1 <= uart_int ? UART_RXD : USER_IN[0]; rxd2 <= rxd1; if(rxd1 == rxd2) uart_rxd <= rxd2;
	cts1 <= UART_CTS & uart_int; cts2 <= cts1; if(cts1 == cts2) uart_cts <= cts2;
	dsr1 <= UART_DSR & uart_int; dsr2 <= dsr1; if(dsr1 == dsr2) uart_dsr <= dsr2;
end

wire rtcF83_sda;
rtcF83 #(16000000, 0) rtcF83
(
	.clk(clk_sys),
	.ce(rtc_ce),                  // Fix 48: real time in Exact 50 Hz too
	.reset(~reset_n | use_tape),
	.RTC(RTC),
	.scl_i(cass_write),
	.sda_i(cass_motor),
	.sda_o(rtcF83_sda)
);

reg use_rtc = 0;
always @(posedge clk_sys) begin
	reg [20:0] to = 0;

	if(to) to <= to - 1'd1;
	use_rtc <= |to;

	if(cass_write) to <= '1;
end

wire cass_rtc = ~(rtcF83_sda & use_rtc & cass_motor);

endmodule
