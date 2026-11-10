// =====================================================================================================
//  EXACT 50 Hz (Fix 48) - (c) 2026 Mong00se
//
//  A PAL C64 makes 312 lines x 63 cycles = 19656 cycles a frame. At the real crystal (985,248 Hz) that is
//  50.1246 frames a second, so a capture card locked to exactly 50.000 fps repeats a frame and then drops
//  one every ~8 s. "Exact 50 Hz" (the Octophonic default) runs the WHOLE machine - clk_sys (32 x the C64
//  cycle), clk64 (the video/SDRAM clock) and clk48 (the OPL) - 0.249% slower, so one frame is exactly
//  1/50.000 s: the C64 cycle becomes 982,800 Hz, clk_sys 31,449,600 Hz.
//
//  It is done the same way the core already switches PAL/NTSC: the PLL's fractional M (register 7) is
//  rewritten through the PLL reconfiguration block. Nothing inside the C64 changes - every chip, the 1541
//  (its 16 MHz enable is a fixed fraction of clk_sys), the tape, the REU, the cartridges and the CIA timers
//  keep their cycle-exact relationship; they all just run 0.249% slower in real time.
//
//  The PLL: VCO = 50 MHz x (11 + K/2^32), clk_sys = VCO / 18.
//      PAL   K = 1503512573  ->  clk_sys 31,527,955 Hz  ->  50.124572 Hz frames   (as compiled; no reconfig)
//      EXACT K = 1382360994  ->  clk_sys 31,449,600 Hz  ->  50.000000 Hz frames   (error 4e-7 ppm)
//      NTSC  K = 3357876127  ->  clk_sys 32,727,268 Hz                             (as before)
//
//  Things that are REAL TIME, not part of the C64, keep real time in Exact mode:
//      - the CIA TOD 50 Hz input (on a real C64 it comes from the mains, not the crystal): cia_tod_clk.vhd
//      - the cartridge-port real-time clock (rtcF83): rtc_ce below
// =====================================================================================================

// -----------------------------------------------------------------------------------------------------
// The PLL mode: PAL, Exact 50 Hz PAL or NTSC. Runs on CLK_50M (the PLL's own reconfig clock).
// Same behaviour as the old inline PAL/NTSC block: when the mode changes, close the OSD (so a pause-in-OSD
// doesn't leave a blank screen over the reset), wait 150 ms, then write K and start the reconfig.
// The PLL comes up as compiled (PAL), so with Exact on (the default) it is written once at start-up.
// -----------------------------------------------------------------------------------------------------
module pll_mode
(
	input             clk,            // CLK_50M
	input             ntsc_req,       // the menu: NTSC
	input             exact_req,      // the menu: Exact 50 Hz (PAL only)
	input             osd_status,

	input             cfg_waitrequest,
	output reg        cfg_write = 0,
	output reg  [5:0] cfg_address = 0,
	output reg [31:0] cfg_data = 0,

	output reg        close_osd = 0,
	output reg        ntsc_r = 0,     // the mode the PLL is in (or going to)
	output reg        exact_r = 0
);

localparam [31:0] K_PAL   = 32'd1503512573;
localparam [31:0] K_EXACT = 32'd1382360994;
localparam [31:0] K_NTSC  = 32'd3357876127;

reg ntscd = 0, ntscd2 = 0, exactd = 0, exactd2 = 0;
reg [2:0] state = 0;
reg [23:0] delay = 0;
reg osd_s1 = 0, osd_s2 = 0;

wire exact_want = exactd2 & ~ntscd2;      // Exact only means anything on PAL

always @(posedge clk) begin
	osd_s1 <= osd_status;
	osd_s2 <= osd_s1;

	ntscd   <= ntsc_req;  ntscd2  <= ntscd;
	exactd  <= exact_req; exactd2 <= exactd;

	cfg_write <= 0;
	close_osd <= 0;

	if(ntscd2 != ntsc_r || exact_want != exact_r) begin
		if(osd_s2 && delay < 24'd2500000) begin        // 50 ms pulse to close the OSD
			close_osd <= 1;
			delay <= delay + 1'd1;
		end else if (delay < 24'd7500000) begin         // 150 ms total delay
			delay <= delay + 1'd1;
		end else if (!state) begin
			state   <= 1;
			ntsc_r  <= ntscd2;
			exact_r <= exact_want;
			delay   <= 0;
		end
	end else begin
		delay <= 0;
	end

	if(!cfg_waitrequest) begin
		if(state) state <= state + 1'd1;
		case(state)
			1: begin                                     // mode register: waitrequest mode
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			5: begin                                     // M counter fractional value K
					cfg_address <= 7;
					cfg_data <= ntsc_r ? K_NTSC : exact_r ? K_EXACT : K_PAL;
					cfg_write <= 1;
				end
			7: begin                                     // start
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

endmodule

// -----------------------------------------------------------------------------------------------------
// The 1541's 16 MHz enable, and the cartridge RTC's real-time 16 MHz enable. clk_sys domain.
// drive_ce is the old inline generator, unchanged: a fixed fraction (16,000,000 / 31,527,954) of clk_sys,
// so in Exact mode the drive slows down by exactly the same 0.249% as the C64 - every fast loader sees the
// very same C64:drive cycle ratio as before, bit for bit.
// rtc_ce divides by the TRUE clk_sys rate of the mode, so the RTC keeps real time in Exact mode.
// -----------------------------------------------------------------------------------------------------
module drive_rtc_ce
(
	input      clk,                 // clk_sys
	input      ntsc,
	input      exact,
	output reg drive_ce = 0,
	output reg rtc_ce = 0
);

always @(posedge clk) begin
	int sum = 0;
	int msum;

	msum <= ntsc ? 32727264 : 31527954;

	drive_ce <= 0;
	sum = sum + 16000000;
	if(sum >= msum) begin
		sum = sum - msum;
		drive_ce <= 1;
	end
end

reg [25:0] rsum = 0;               // < rmod, so rsum + 16M < 49M fits 26 bits
reg [25:0] rmod = 26'd31527954;
always @(posedge clk) begin
	rmod <= ntsc ? 26'd32727264 : exact ? 26'd31449600 : 26'd31527954;

	rtc_ce <= 0;
	if(rsum + 26'd16000000 >= rmod) begin
		rsum   <= rsum + 26'd16000000 - rmod;
		rtc_ce <= 1;
	end
	else rsum <= rsum + 26'd16000000;
end

endmodule
