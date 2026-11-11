// Fix 48 checks: the PLL mode block, the drive/RTC enables in three modes, and the C1530 tape player.
// One clock drives everything; each check in tb.cpp uses its own part. (c) 2026 Mong00se
module top
(
	input         clk,
	// pll_mode
	input         ntsc_req,
	input         exact_req,
	input         osd_status,
	output        cfg_write,
	output  [5:0] cfg_address,
	output [31:0] cfg_data,
	output        close_osd,
	output        ntsc_r,
	output        exact_r,
	// drive / rtc enables: [0] Original PAL, [1] Exact 50 Hz, [2] NTSC
	output  [2:0] drive_ce,
	output  [2:0] rtc_ce,
	// tape
	input         restart_tape,
	input   [7:0] tap_in,
	input         tap_wr,
	output        tap_full,
	output        tap_err,
	output        cass_read,
	input         cass_motor
);

pll_mode pm(.clk(clk), .ntsc_req(ntsc_req), .exact_req(exact_req), .osd_status(osd_status),
	.cfg_waitrequest(1'b0), .cfg_write(cfg_write), .cfg_address(cfg_address), .cfg_data(cfg_data),
	.close_osd(close_osd), .ntsc_r(ntsc_r), .exact_r(exact_r));

drive_rtc_ce d0(.clk(clk), .ntsc(1'b0), .exact(1'b0), .drive_ce(drive_ce[0]), .rtc_ce(rtc_ce[0]));
drive_rtc_ce d1(.clk(clk), .ntsc(1'b0), .exact(1'b1), .drive_ce(drive_ce[1]), .rtc_ce(rtc_ce[1]));
drive_rtc_ce d2(.clk(clk), .ntsc(1'b1), .exact(1'b0), .drive_ce(drive_ce[2]), .rtc_ce(rtc_ce[2]));

c1530 tape(.clk32(clk), .restart_tape(restart_tape), .wav_mode(1'b0), .tap_version(2'd1),
	.host_tap_in(tap_in), .host_tap_wrreq(tap_wr), .tap_fifo_wrfull(tap_full), .tap_fifo_error(tap_err),
	.cass_sense(1'b0), .cass_read(cass_read), .cass_write(1'b1), .cass_motor(cass_motor), .cass_run());

endmodule
