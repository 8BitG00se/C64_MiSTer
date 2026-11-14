// (c) 2026 Mong00se
// FAST LOAD (Fix 49) simulation: the whole machine a LOAD goes through - the C64 (GHDL's Verilog of
// rtl/fpga64_sid_iec.vhd: the 6510, the VIC-II, the bus logic with the fast loader's ROM bank, the real
// CIAs), the 1541 (rtl/iec_drive/c1541_multi.sv: its 6502, its VIAs, the disk turning in
// c1541_direct_gcr, the track buffer filled from a G64 image in a model of the DDR3) and, between them,
// the serial bus and the parallel port wired as c64.sv wires them (the same disk_access rule).
module tb_top
(
	input         clk,
	input         reset_n,
	input         fl_en,           // the menu: Fast loader On
	input         parport,         // the menu: Parallel port Enabled
	input         img_mount,       // a disk goes into drive 8
	output [15:0] c64_addr,
	output        ram_we,
	output        fl_bank,         // the fast loader's ROM bank is in
	output        fast_ok,         // drive 8 can take the fast loader
	output        disk_access,
	output        led,
	output  [6:0] track,
	output        atn, clk_line, data_line,
	output        stb_c64, stb_drv, // the two strobes: PC2 to the drive, CA2 to the C64
	output  [7:0] par_c64, par_drv,
	output        vblank
);

wire  [7:0] c64_data_out;
wire        ram_ce;
wire        io_cycle, ext_cycle, refresh;

// ---- the cartridge port (nothing in it) and the SDRAM's 64K, as in c64.sv
wire        game, exrom, io_rom, cart_oe, cart_ce, cart_we, cart_mem_req, nmi, nmi_ack;
wire        romL, romH, UMAXromH, IOE, IOF;
wire  [7:0] cart_data, cart_wrdata, c64_data_in;
wire [24:0] cart_addr;
cartridge cartridge
(
	.clk32(clk), .reset_n(reset_n),
	.cart_loading(1'b0), .cart_id(8'd255), .cart_exrom(1'b1), .cart_game(1'b1),
	.cart_bank_hi(1'b0), .cart_bank_16k(1'b0), .cart_bank_num(8'd0),
	.cart_bank_addr(8'd0), .cart_bank_wr(1'b0), .cart_boot(1'b1),
	.exrom(exrom), .game(game),
	.romL(romL), .romH(romH), .UMAXromH(UMAXromH), .IOE(IOE), .IOF(IOF),
	.mem_write(ram_we), .mem_ce(ram_ce), .mem_ce_out(cart_ce), .mem_write_out(cart_we),
	.mem_in(sd_dout), .mem_out(cart_wrdata), .mem_addr(cart_addr), .mem_req(cart_mem_req), .mem_cycle(io_cycle),
	.IO_rom(io_rom), .IO_rd(cart_oe), .IO_data(cart_data),
	.addr_in(c64_addr), .data_in(c64_data_out), .data_out(c64_data_in),
	.freeze_key(1'b0), .mod_key(1'b0), .nmi(nmi), .nmi_ack(nmi_ack)
);
wire        sd_ce = io_cycle ? (cart_mem_req & cart_ce) : ext_cycle ? 1'b0 : cart_ce;
reg   [7:0] sdram [0:65535];
reg   [7:0] sd_dout = 0;
reg         ce_d = 0;
reg   [1:0] sd_cnt = 0;
reg  [15:0] sd_a;
always @(posedge clk) begin
	ce_d <= sd_ce;
	if (sd_ce & ~ce_d) begin
		if (cart_we) sdram[cart_addr[15:0]] <= cart_wrdata;
		sd_a   <= cart_addr[15:0];
		sd_cnt <= 2'd2;                                // (the byte is there 3 clocks after the access starts, as the real SDRAM's)
	end
	if (sd_cnt != 0) begin
		sd_cnt <= sd_cnt - 1'd1;
		if (sd_cnt == 2'd1) sd_dout <= sdram[sd_a];
	end
end

// ---- the C64
wire  [7:0] pb_o;
reg   [7:0] pb_i;
wire        pc2_n_o;
reg         flag2_n_i;
wire        c64_iec_clk, c64_iec_data, c64_iec_atn;
wire        drive_iec_clk_o, drive_iec_data_o;
wire        hs, vs;
wire        drive_fast_ok;
wire        fl_busy;
fpga64_sid_iec c64
(
	.clk32(clk), .reset_n(reset_n), .bios(2'b00), .pause(1'b0),
	.ps2_key(11'd0), .kbd_reset(~reset_n), .shift_mod(2'b00),
	.ramAddr(c64_addr), .ramDout(c64_data_out), .ramDin(c64_data_in), .ramCE(ram_ce), .ramWE(ram_we),
	.io_cycle(io_cycle), .ext_cycle(ext_cycle), .refresh(refresh),
	.cia_mode(1'b0), .turbo_mode({1'b0, 1'b1}), .turbo_speed(2'b00),     // (c64.sv's default: turbo when a program asks at $D030)
	.vic_variant(2'b00), .ntscMode(1'b0), .sysinfo(8'd0), .exact50(1'b1), .palette(3'd0), .split(1'b0), .quarter(1'b0),
	.fl_en(fl_en & parport), .fl_ok({1'b0, drive_fast_ok}), .fl_busy(fl_busy),   // (as c64.sv)
	.hsync(hs), .vsync(vs),
	.game(game), .exrom(exrom), .io_rom(io_rom), .io_ext(cart_oe), .io_data(cart_data), .irq_n(1'b1), .nmi_n(~nmi), .nmi_ack(nmi_ack),
	.romL(romL), .romH(romH), .UMAXromH(UMAXromH), .IOE(IOE), .IOF(IOF),
	.dma_req(1'b0), .dma_addr(16'd0), .dma_dout(8'd0), .dma_we(1'b0), .irq_ext_n(1'b1),
	.joyA(7'd0), .joyB(7'd0), .pot1(8'd0), .pot2(8'd0), .pot3(8'd0), .pot4(8'd0),
	.sid_filter(2'b11), .sid_ver(2'b00), .sid_mode(3'd0), .sid_cfg(4'd0), .sid_fc_off_l(13'd0), .sid_fc_off_r(13'd0),
	.sid_ld_clk(clk), .sid_ld_addr(12'd0), .sid_ld_data(16'd0), .sid_ld_wr(1'b0),
	.chip_we(1'b0), .chip_wside(1'b0), .chip_wtbl(2'd0), .chip_widx(12'd0), .chip_wdata(8'd0), .chip_on(2'b00),
	.sid_digifix(1'b1), .sid_quad(1'b1), .sid_oct(1'b1), .sid_fx_osd(2'b00),
	.os_io_enable(1'b0), .os_io_strobe(1'b0), .os_io_din(16'd0),
	.ogx_ddr_busy(1'b1), .ogx_ddr_dout(64'd0), .ogx_ddr_dout_ready(1'b0),
	.pb_i(pb_i), .pb_o(pb_o), .pa2_i(1'b1), .pc2_n_o(pc2_n_o), .flag2_n_i(flag2_n_i),
	.sp2_i(1'b1), .sp1_i(1'b1), .cnt2_i(1'b1), .cnt1_i(1'b1),
	.iec_data_o(c64_iec_data), .iec_atn_o(c64_iec_atn), .iec_clk_o(c64_iec_clk),
	.iec_data_i(drive_iec_data_o), .iec_clk_i(drive_iec_clk_o),
	.c64rom_addr(14'd0), .c64rom_data(8'd0), .c64rom_wr(1'b0),
	.cass_sense(1'b1), .cass_read(1'b1),
	.rw_freeze(1'b0), .rw_cpu_i(176'd0), .rw_cia1_i(320'd0), .rw_cia2_i(320'd0), .rw_ld(1'b0),
	.rw_vic_we(1'b0), .rw_vic_addr(6'd0), .rw_vic_data(8'd0),
	.rw_sid_we(1'b0), .rw_sid_cs(2'd0), .rw_sid_addr(5'd0), .rw_sid_data(8'd0),
	.rw_col_we(1'b0), .rw_col_addr(10'd0), .rw_col_data(4'd0)
);
assign vblank    = vs;
assign fl_bank   = c64.fl_bank;
assign fast_ok   = drive_fast_ok;
assign atn       = c64_iec_atn;
assign clk_line  = c64_iec_clk & drive_iec_clk_o;
assign data_line = c64_iec_data & drive_iec_data_o;

// ---- the 1541, as c64.sv has it (drive 8 only, a .d64/.g64: the direct GCR drive)
wire drive_ce, rtc_ce;
drive_rtc_ce drive_rtc_ce (.clk(clk), .ntsc(1'b0), .exact(1'b1), .drive_ce(drive_ce), .rtc_ce(rtc_ce));

reg  drive_mounted = 0;
always @(posedge clk) if (img_mount) drive_mounted <= 1;

wire  [7:0] drive_par_o;
reg   [7:0] drive_par_i;
wire        drive_stb_o;
reg         drive_stb_i;
wire  [6:0] drv_track [1];
wire [31:0] drv_lba [1];
wire  [5:0] drv_blk_cnt [1];
wire  [7:0] drv_buff_din [1];
wire        drv_led, drv_we, disk_ready, drv_sd_rd, drv_sd_wr;
wire [28:0] ddr_addr;
wire  [7:0] ddr_burstcnt, ddr_be;
wire [63:0] ddr_din;
wire        ddr_rd, ddr_we;
reg  [63:0] ddr_q;
reg         ddr_v = 0;
c1541_multi #(.PARPORT(1), .DUALROM(1), .DRIVES(1)) drv
(
	.clk(clk), .reset(~reset_n | ~drive_mounted), .ce(drive_ce),
	.pause(1'b0), .gcr_mode(1'b1),
	.img_mounted(img_mount), .img_readonly(1'b0), .img_size(32'd174848), .drive_rpm(3'd0), .drive_wobble(1'b0),
	.led(drv_led), .out_track(drv_track), .out_we(drv_we), .disk_ready(disk_ready),
	.iec_atn_i(c64_iec_atn), .iec_data_i(c64_iec_data), .iec_clk_i(c64_iec_clk),
	.iec_data_o(drive_iec_data_o), .iec_clk_o(drive_iec_clk_o),
	.par_data_i(drive_par_i), .par_stb_i(drive_stb_i), .par_data_o(drive_par_o), .par_stb_o(drive_stb_o),
	.clk_sys(clk),
	.sd_lba(drv_lba), .sd_blk_cnt(drv_blk_cnt), .sd_rd(drv_sd_rd), .sd_wr(drv_sd_wr), .sd_ack(1'b0),
	.sd_buff_addr(14'd0), .sd_buff_dout(8'd0), .sd_buff_din(drv_buff_din), .sd_buff_wr(1'b0),
	.rom_addr(15'd0), .rom_data(8'd0), .rom_wr(1'b0), .rom_std(1'b0),          // (System ROM: Octophonic 64 V1.1, nothing loaded)
	.fast_ok(drive_fast_ok),
	.DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(ddr_burstcnt), .DDRAM_ADDR(ddr_addr), .DDRAM_DOUT(ddr_q), .DDRAM_DOUT_READY(ddr_v),
	.DDRAM_RD(ddr_rd), .DDRAM_WE(ddr_we), .DDRAM_DIN(ddr_din), .DDRAM_BE(ddr_be)
);
assign led   = drv_led;
assign track = drv_track[0];

// the DDR3: the disk as Main puts it there (a G64 image from byte $30000000 = word $06000000); a read's
// words come a few clocks later, one a clock
reg  [63:0] ddr [0:65535];
reg  [28:0] r_addr;
reg   [7:0] r_left = 0;
reg   [3:0] r_wait = 0;
always @(posedge clk) begin
	ddr_v <= 0;
	if (ddr_rd) begin
		if (ddr_addr < 29'h06000000 || ddr_addr >= 29'h06010000) $display("DDR_BAD_ADDR read %h", ddr_addr);
		r_addr <= ddr_addr; r_left <= ddr_burstcnt; r_wait <= 4'd6;
	end
	if (ddr_we) $display("DDR_WRITE %h (the disk was written to)", ddr_addr);
	if (r_left != 0) begin
		if (r_wait != 0) r_wait <= r_wait - 1'd1;
		else begin
			ddr_q  <= ddr[r_addr[15:0]];
			ddr_v  <= 1;
			r_addr <= r_addr + 1'd1;
			r_left <= r_left - 1'd1;
		end
	end
end

// ---- c64.sv's rule for the user port: the drive's parallel port has it while there is disk traffic, and
// while the drive is talking the fast way
reg disk_access_r = 0;
always @(posedge clk) begin
	reg c64_iec_clk_old, drive_iec_clk_old, drive_stb_i_old, drive_stb_o_old;
	integer to = 0;

	c64_iec_clk_old <= c64_iec_clk;
	drive_iec_clk_old <= drive_iec_clk_o;
	drive_stb_i_old <= drive_stb_i;
	drive_stb_o_old <= drive_stb_o;

	if(((c64_iec_clk_old != c64_iec_clk) || (drive_iec_clk_old != drive_iec_clk_o)) ||
		(parport && ((drive_stb_i_old != drive_stb_i) || (drive_stb_o_old != drive_stb_o))))
	begin
		disk_access_r <= 1;
		to <= 16000000; // 0.5s
	end
	else if(to) to <= to - 1;
	else disk_access_r <= 0;
end
assign disk_access = disk_access_r;

always_comb begin
	flag2_n_i   = 1;
	pb_i        = 8'hFF;
	drive_par_i = 8'hFF;
	drive_stb_i = 1;
	if (parport & (disk_access_r | fl_busy)) begin
		drive_par_i = pb_o;
		drive_stb_i = pc2_n_o;
		pb_i        = drive_par_o;
		flag2_n_i   = drive_stb_o;
	end
	else pb_i[5:0] = 6'b111111;                        // (the joystick adapter, nothing pressed)
end
assign stb_c64 = drive_stb_i;
assign stb_drv = drive_stb_o;
assign par_c64 = drive_par_i;
assign par_drv = drive_par_o;

// ---- the ROMs, the C64's memory, the disk
initial begin
	$readmemh("octo.hex", c64.buslogic.kernel_c64.ram);
	$readmemh("std.hex", c64.buslogic.kernel_c64std.ram);
	$readmemh("fastload.hex", c64.buslogic.fastload.ram);
	$readmemh("chargen.hex", c64.buslogic.chargen.ram);
	$readmemh("zero.hex", sdram);
	$readmemh("c1541.hex", drv.romstd.ram);
	$readmemh("fastdrive.hex", drv.drives[0].c1541_drv.c1541_logic.fastload.ram);
	$readmemh("g64.hex", ddr);
end

endmodule

// the drive's 6502: the C64 netlist's T65 (the same rtl/t65), under the name c1541_logic.sv calls it by
module T65
(
	input  [1:0]  mode,
	input         res_n, enable, clk, rdy, abort_n, irq_n, nmi_n, so_n,
	output        r_w_n,
	output [23:0] A,
	input  [7:0]  DI,
	output [7:0]  DO
);
t65 cpu (.mode(mode), .bcd_en(1'b1), .res_n(res_n), .enable(enable), .clk(clk), .rdy(rdy), .abort_n(abort_n),
         .irq_n(irq_n), .nmi_n(nmi_n), .so_n(so_n), .di(DI), .st_i(160'd0), .st_ld(1'b0),
         .r_w_n(r_w_n), .a(A), .\do (DO));
endmodule

// the SIDs: not part of this test
module sid_top #(parameter PHASE = 0)
(
	input         reset,
	input         clk,
	input         ce_1m,
	input   [1:0] cs,
	input         we,
	input   [4:0] addr,
	input   [7:0] data_in,
	output  [7:0] data_out,
	input   [7:0] pot_x_l, pot_y_l, pot_x_r, pot_y_r,
	output [17:0] audio_l, audio_r,
	input  [17:0] ext_in_l, ext_in_r,
	input  [12:0] fc_offset_l, fc_offset_r,
	input   [1:0] filter_en,
	input   [1:0] mode,
	input   [3:0] cfg,
	input         ld_clk,
	input  [11:0] ld_addr,
	input  [15:0] ld_data,
	input         ld_wr,
	output [11:0] tbl_acc,
	input  [31:0] chip_ql, chip_qr,
	input   [1:0] chip_on,
	input         eq_any,
	input   [2:0] sc_sel,
	output [39:0] sc_rec,
	output [15:0] sc_aud,
	input   [5:0] vmute
);
assign sc_rec   = 40'd0;
assign sc_aud   = 16'd0;
assign data_out = 8'd0;
assign audio_l  = 18'd0;
assign audio_r  = 18'd0;
assign tbl_acc  = 12'd0;
endmodule

module chip_bank
(
	input         clk, ce_1m, we, wside,
	input   [1:0] wtbl,
	input  [11:0] widx,
	input   [7:0] wdata,
	input  [11:0] acc0, acc1, acc2, acc3,
	output [31:0] ql0, ql1, ql2, ql3,
	output [31:0] qr0, qr1, qr2, qr3
);
assign {ql0, ql1, ql2, ql3, qr0, qr1, qr2, qr3} = 256'd0;
endmodule
