// REWIND simulation: the C64 (GHDL's Verilog of rtl/fpga64_sid_iec.vhd, REWIND = 1), the real CIAs, the
// rewind unit, the DDR3 arbiter and models of the SDRAM and the DDR3 - wired as c64.sv wires them.
//                                                                              (c) 2026 Mong00se
module tb_top #(parameter AW = 20)
(
	input          clk,
	input          reset_n,
	input          enable,
	input          hold,
	input          block,
	input    [6:0] joyA,
	input    [6:0] joyB,
	// a cartridge (the real game run, tb cart): the .CRT's header and each of its CHIP packets, as c64.sv gives them
	input          cart_on,
	input    [7:0] cart_id,
	input          cart_exrom,
	input          cart_game,
	input          cart_bank_hi,
	input          cart_bank_16k,
	input    [7:0] cart_bank_num,
	input    [7:0] cart_bank_addr,
	input          cart_bank_wr,
	input          cart_loading,
	output         blocked,
	input    [1:0] bios,
	input    [7:0] ddr_lat,
	input          ddr_stall,
	output         hblank,
	output         vblank,
	output   [3:0] index,
	output         pix_en,
	output   [2:0] osd,
	output         freeze,
	output         ld,
	output         active,
	output         err,
	output  [11:0] frames,
	output         seq_on,
	output         tick,
	output   [8:0] ry,
	output [175:0] cpu_o,
	output [319:0] cia1_o,
	output [319:0] cia2_o,
	output   [8:0] fifo_cnt,
	output         sid_wr,          // the SIDs are written (the stub below)
	output  [15:0] c64_addr,
	output         ram_we,
	// Build 14: the Level 2 remaster unit and the recolour unit behind the VIC, as in c64.sv
	input          rm_on,
	input          rm_learn,
	input          rm_reload,
	input          ld_download,
	input          ld_wr,
	input   [24:0] ld_addr,
	input    [7:0] ld_data,
	input    [2:0] palette,
	output  [28:0] v_tag,           // the VIC's own outputs (index is above)
	output  [25:0] v_l2pix,
	output [183:0] v_l2spr,
	output   [1:0] v_bank,
	output  [23:0] o_rgb,           // the picture after both units (16 lines late)
	output  [28:0] o_tag,
	output         o_vsync,
	output         rm_ok,
	output  [15:0] rm_lcount
);

wire  [7:0] c64_data_out;
wire        ram_ce;
wire        io_cycle, ext_cycle, refresh;

// ---- the cartridge port and the SDRAM (4 MB of it: the C64's 64K, a cartridge from $200000), as in c64.sv
wire        game, exrom, io_rom, cart_oe, cart_ce, cart_we, cart_mem_req, nmi, nmi_ack;
wire        romL, romH, UMAXromH, IOE, IOF;
wire  [7:0] cart_data, cart_wrdata, c64_data_in;
wire [24:0] cart_addr;
wire  [7:0] sdram_data;
cartridge cartridge
(
	.clk32(clk), .reset_n(reset_n),
	.cart_loading(cart_loading), .cart_id(cart_on ? cart_id : 8'd255), .cart_exrom(cart_exrom), .cart_game(cart_game),
	.cart_bank_hi(cart_bank_hi), .cart_bank_16k(cart_bank_16k), .cart_bank_num(cart_bank_num),
	.cart_bank_addr(cart_bank_addr), .cart_bank_wr(cart_bank_wr), .cart_boot(1'b1),
	.exrom(exrom), .game(game),
	.romL(romL), .romH(romH), .UMAXromH(UMAXromH), .IOE(IOE), .IOF(IOF),
	.mem_write(ram_we), .mem_ce(ram_ce), .mem_ce_out(cart_ce), .mem_write_out(cart_we),
	.mem_in(sdram_data), .mem_out(cart_wrdata), .mem_addr(cart_addr), .mem_req(cart_mem_req), .mem_cycle(io_cycle),
	.IO_rom(io_rom), .IO_rd(cart_oe), .IO_data(cart_data),
	.addr_in(c64_addr), .data_in(c64_data_out), .data_out(c64_data_in),
	.freeze_key(1'b0), .mod_key(1'b0), .nmi(nmi), .nmi_ack(nmi_ack)
);
wire [24:0] sd_addr = cart_addr;
wire        sd_ce   = io_cycle ? (cart_mem_req & cart_ce) : ext_cycle ? 1'b0 : cart_ce;
wire        sd_we   = cart_we;
wire  [7:0] sd_din  = cart_wrdata;
reg   [7:0] sdram [0:(1 << 22) - 1];
reg   [7:0] sd_dout = 0;
reg         ce_d = 0;
reg   [1:0] sd_cnt = 0;
reg  [21:0] sd_a;
always @(posedge clk) begin
	ce_d <= sd_ce;
	if (sd_ce & ~ce_d) begin
		if (sd_we) sdram[sd_addr[21:0]] <= sd_din;
		sd_a   <= sd_addr[21:0];
		sd_cnt <= 2'd2;                                // (the byte is there 3 clocks after the access starts, as the real SDRAM's)
	end
	if (sd_cnt != 0) begin
		sd_cnt <= sd_cnt - 1'd1;
		if (sd_cnt == 2'd1) sd_dout <= sdram[sd_a];
	end
end
wire  [7:0] rw_mq;
wire        rw_msel;
assign      sdram_data = rw_msel ? rw_mq : sd_dout;

// c64.sv's rule for a bank-switching cartridge: its registers touched -> no history for half a second
// (here: 4 frames, to keep the run short)
reg         cart_busy = 0;
reg  [21:0] cart_to = 0;
always @(posedge clk) begin
	if (cart_on && cart_id != 8'd0 && (IOE | IOF)) cart_to <= 22'd2500000;
	else if (cart_to != 0) cart_to <= cart_to - 1'd1;
	cart_busy <= (cart_to != 0);
end
assign blocked = block | ~reset_n | cart_busy;

wire         rw_freeze, rw_ld, rw_io_wr, rw_vic_we, rw_sid_we, rw_col_we;
wire [175:0] rw_cpu_i;
wire [319:0] rw_cia1_i, rw_cia2_i;
wire   [3:0] rw_io_sel, rw_col_old, rw_col_data;
wire   [9:0] rw_io_addr, rw_col_addr;
wire   [7:0] rw_io_data, rw_vic_data, rw_sid_data;
wire   [5:0] rw_vic_addr;
wire   [4:0] rw_sid_addr;
wire   [1:0] rw_sid_cs;
wire         hs, vs;

fpga64_sid_iec c64
(
	.clk32(clk), .reset_n(reset_n), .bios(bios), .pause(1'b0),
	.ps2_key(11'd0), .kbd_reset(~reset_n), .shift_mod(2'b00),
	.ramAddr(c64_addr), .ramDout(c64_data_out), .ramDin(c64_data_in), .ramCE(ram_ce), .ramWE(ram_we),
	.io_cycle(io_cycle), .ext_cycle(ext_cycle), .refresh(refresh),
	.cia_mode(1'b0), .turbo_mode(2'b00), .turbo_speed(2'b00),
	.vic_variant(2'b00), .ntscMode(1'b0), .sysinfo(8'd0), .exact50(1'b1), .palette(3'd0), .split(1'b0), .quarter(1'b0),
	.hsync(hs), .vsync(vs), .rgb_index(index), .rgb_pix_en(pix_en), .rgb_tag(v_tag), .l2_pix(v_l2pix), .l2_spr(v_l2spr), .l2_bank(v_bank),
	.game(game), .exrom(exrom), .io_rom(io_rom), .io_ext(cart_oe), .io_data(cart_data), .irq_n(1'b1), .nmi_n(~nmi), .nmi_ack(nmi_ack),
	.romL(romL), .romH(romH), .UMAXromH(UMAXromH), .IOE(IOE), .IOF(IOF),
	.dma_req(1'b0), .dma_addr(16'd0), .dma_dout(8'd0), .dma_we(1'b0), .irq_ext_n(1'b1),
	.joyA(joyA), .joyB(joyB), .pot1(8'd0), .pot2(8'd0), .pot3(8'd0), .pot4(8'd0),
	.sid_filter(2'b11), .sid_ver(8'd0), .sid_mode(3'd0), .sid_cfg(16'd0), .sid_fc_off_l(13'd0), .sid_fc_off_r(13'd0),
	.sid_ld_clk(clk), .sid_ld_addr(12'd0), .sid_ld_data(16'd0), .sid_ld_wr(1'b0),
	.chip_we(1'b0), .chip_wside(1'b0), .chip_wtbl(2'd0), .chip_widx(12'd0), .chip_wdata(8'd0), .chip_on(8'd0), .chip_bk(8'd0), .chip_fc(8'd0),
	.sid_digifix(1'b1), .sid_quad(1'b1), .sid_oct(1'b1), .sid_fx_osd(2'b00),
	.os_io_enable(1'b0), .os_io_strobe(1'b0), .os_io_din(16'd0),
	.ogx_ddr_busy(1'b1), .ogx_ddr_dout(64'd0), .ogx_ddr_dout_ready(1'b0),
	.pb_i(8'hFF), .pa2_i(1'b1), .flag2_n_i(1'b1), .sp2_i(1'b1), .sp1_i(1'b1), .cnt2_i(1'b1), .cnt1_i(1'b1),
	.iec_data_i(1'b1), .iec_clk_i(1'b1),
	.c64rom_addr(14'd0), .c64rom_data(8'd0), .c64rom_wr(1'b0),
	.cass_sense(1'b1), .cass_read(1'b1),
	.rw_tick(tick), .rw_ry(ry), .rw_freeze(rw_freeze),
	.rw_cpu_o(cpu_o), .rw_cia1_o(cia1_o), .rw_cia2_o(cia2_o),
	.rw_cpu_i(rw_cpu_i), .rw_cia1_i(rw_cia1_i), .rw_cia2_i(rw_cia2_i), .rw_ld(rw_ld),
	.rw_io_wr(rw_io_wr), .rw_io_sel(rw_io_sel), .rw_io_addr(rw_io_addr), .rw_io_data(rw_io_data), .rw_col_old(rw_col_old),
	.rw_vic_we(rw_vic_we), .rw_vic_addr(rw_vic_addr), .rw_vic_data(rw_vic_data),
	.rw_sid_we(rw_sid_we), .rw_sid_cs(rw_sid_cs), .rw_sid_addr(rw_sid_addr), .rw_sid_data(rw_sid_data),
	.rw_col_we(rw_col_we), .rw_col_addr(rw_col_addr), .rw_col_data(rw_col_data)
);
assign hblank = hs;
assign vblank = vs;
assign freeze = rw_freeze;
assign ld     = rw_ld;

wire [28:0] b_addr, d_addr;
wire  [7:0] b_burstcnt, b_be, d_burstcnt, d_be;
wire [63:0] b_din, d_din, d_dout;
wire        b_rd, b_we, b_busy, b_ready, d_rd, d_we, d_busy, d_ready;

rewind #(.AW(AW)) rw
(
	.clk(clk), .reset(1'b0), .enable(enable), .hold(hold), .block(blocked), .busy_dma(1'b0),
	.tick(tick), .ry(ry), .freeze(rw_freeze),
	.cpu_o(cpu_o), .cia1_o(cia1_o), .cia2_o(cia2_o),
	.cpu_i(rw_cpu_i), .cia1_i(rw_cia1_i), .cia2_i(rw_cia2_i), .ld(rw_ld),
	.io_wr(rw_io_wr), .io_sel(rw_io_sel), .io_addr(rw_io_addr), .io_data(rw_io_data), .col_old(rw_col_old),
	.vic_we(rw_vic_we), .vic_addr(rw_vic_addr), .vic_data(rw_vic_data),
	.sid_we(rw_sid_we), .sid_cs(rw_sid_cs), .sid_addr(rw_sid_addr), .sid_data(rw_sid_data),
	.col_we(rw_col_we), .col_addr(rw_col_addr), .col_data(rw_col_data),
	.m_addr(sd_addr), .m_ce(sd_ce), .m_we(sd_we), .m_din(sd_din), .m_main(~io_cycle & ~ext_cycle),
	.m_q(rw_mq), .m_sel(rw_msel),
	.x_addr(rm_addr), .x_req(rm_req), .x_ack(rm_ack), .x_q(rm_q),
	.ddr_addr(w_addr), .ddr_burstcnt(w_burstcnt), .ddr_rd(w_rd), .ddr_we(w_we), .ddr_din(w_din), .ddr_be(w_be),
	.ddr_busy(w_busy), .ddr_dout(d_dout), .ddr_ready(w_ready),
	.active(active), .frames(frames), .err(err)
);
// Build 14: the remaster unit shares port B with the rewind unit, and feeds the recolour unit
wire [28:0] w_addr, m_addr;
wire  [7:0] w_burstcnt, w_be, m_burstcnt, m_be;
wire [63:0] w_din, m_din;
wire        w_rd, w_we, w_busy, w_ready, m_rd, m_we, m_busy, m_ready;
wire [15:0] rm_addr;
wire        rm_req, rm_ack;
wire  [7:0] rm_q;
wire  [3:0] rm_index;
wire        rm_ovr;
wire  [7:0] rm_slot;
wire  [3:0] rc_npal;
wire        rc_loaded;
ddram_arb2 arb_b
(
	.clk(clk), .reset(~reset_n),
	.a_addr(w_addr), .a_burstcnt(w_burstcnt), .a_rd(w_rd), .a_we(w_we), .a_din(w_din), .a_be(w_be), .a_busy(w_busy), .a_ready(w_ready),
	.b_addr(m_addr), .b_burstcnt(m_burstcnt), .b_rd(m_rd), .b_we(m_we), .b_din(m_din), .b_be(m_be), .b_busy(m_busy), .b_ready(m_ready),
	.addr(b_addr), .burstcnt(b_burstcnt), .rd(b_rd), .we(b_we), .din(b_din), .be(b_be), .busy(b_busy), .ready(b_ready)
);
remaster remaster
(
	.clk(clk), .reset(~reset_n), .on(rm_on & rc_loaded), .learn(rm_learn), .reload(rm_reload),
	.index(index), .tag(v_tag), .l2_pix(v_l2pix), .l2_spr(v_l2spr), .bank(v_bank), .vsync_in(vs),
	.d_index(rm_index), .d_tag(o_tag), .d_vsync(o_vsync), .ovr(rm_ovr), .ovr_slot(rm_slot),
	.x_addr(rm_addr), .x_req(rm_req), .x_ack(rm_ack), .x_q(rm_q),
	.ddr_addr(m_addr), .ddr_burstcnt(m_burstcnt), .ddr_rd(m_rd), .ddr_we(m_we), .ddr_din(m_din), .ddr_be(m_be),
	.ddr_busy(m_busy), .ddr_dout(d_dout), .ddr_ready(m_ready),
	.l2_ok(rm_ok), .lcount(rm_lcount)
);
rgb256 recolour
(
	.clk(clk), .ld_download(ld_download), .ld_wr(ld_wr), .ld_addr(ld_addr), .ld_data(ld_data),
	.index(rm_index), .tag(o_tag), .ovr(rm_ovr), .ovr_slot(rm_slot),
	.palette(palette), .npal(rc_npal), .rgb(o_rgb), .loaded(rc_loaded)
);
assign seq_on   = rw.seq_on;
assign fifo_cnt = rw.f_cnt;

ddram_arb2 arb
(
	.clk(clk), .reset(~reset_n),
	.a_addr(29'd0), .a_burstcnt(8'd0), .a_rd(1'b0), .a_we(1'b0), .a_din(64'd0), .a_be(8'd0), .a_busy(), .a_ready(),
	.b_addr(b_addr), .b_burstcnt(b_burstcnt), .b_rd(b_rd), .b_we(b_we), .b_din(b_din), .b_be(b_be), .b_busy(b_busy), .b_ready(b_ready),
	.addr(d_addr), .burstcnt(d_burstcnt), .rd(d_rd), .we(d_we), .din(d_din), .be(d_be), .busy(d_busy), .ready(d_ready)
);

// ---- the DDR3: a memory behind an Avalon port - held off at random (ddr_stall), reads ddr_lat clocks late
reg  [63:0] ddr [0:(1 << AW) - 1];
reg  [63:0] ddrp [0:(1 << 19) - 1];          // Build 14: the pack (word $06800000 on, 4 MB here)
reg  [63:0] ddrl [0:(1 << 15) - 1];          //           the learn log (word $06C00000 on)
wire        d_ring  = (d_addr >= 29'h07000000);
wire        d_log   = !d_ring && (d_addr >= 29'h06C00000);
wire        r_ring  = (r_addr >= 29'h07000000);
wire        r_log   = !r_ring && (r_addr >= 29'h06C00000);
reg  [63:0] ddr_q;
reg         ddr_v = 0;
reg   [8:0] r_wait = 0;
reg   [7:0] r_left = 0;
reg  [28:0] r_addr;
assign d_busy  = ddr_stall | (r_left != 0);
assign d_dout  = ddr_q;
assign d_ready = ddr_v;
always @(posedge clk) begin
	ddr_v <= 0;
	if (d_we & ~d_busy) begin
		if (d_addr < 29'h06800000 || (d_ring && d_addr[28:AW] != (29'h07000000 >> AW))) $display("DDR_BAD_ADDR write %h", d_addr);
		if (d_ring) ddr[d_addr[AW-1:0]] <= d_din;
		else if (d_log) ddrl[d_addr[14:0]] <= d_din;
		else ddrp[d_addr[18:0]] <= d_din;
	end
	if (d_rd & ~d_busy) begin
		if (d_addr < 29'h06800000 || (d_ring && d_addr[28:AW] != (29'h07000000 >> AW))) $display("DDR_BAD_ADDR read %h", d_addr);
		r_addr <= d_addr; r_left <= d_burstcnt; r_wait <= {1'b0, ddr_lat} + 9'd1;
	end
	if (r_left != 0) begin
		if (r_wait != 0) r_wait <= r_wait - 1'd1;
		else if (!ddr_stall) begin
			ddr_q  <= r_ring ? ddr[r_addr[AW-1:0]] : r_log ? ddrl[r_addr[14:0]] : ddrp[r_addr[18:0]];
			ddr_v  <= 1;
			r_addr <= r_addr + 1'd1;
			r_left <= r_left - 1'd1;
		end
	end
end

rewind_osd rosd (.clk(clk), .ce(pix_en), .hblank(hblank), .vblank(vblank), .on(active), .err(err), .frames(frames), .pixel_color(osd));

assign sid_wr = c64.sid.wr_any;

// ---- the ROMs, and the C64's memory as it starts (both copies)
initial begin
	$readmemh("rom.hex", c64.buslogic.kernel_c64.ram);
	$readmemh("chargen.hex", c64.buslogic.chargen.ram);
	$readmemh("ram.hex", sdram, 0, 65535);
	$readmemh("ram.hex", rw.ram.m);
end

endmodule

// the SIDs: only their registers (what the rewind unit writes back is checked, not the sound)
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
	input   [1:0] chip_on, chip_bk, chip_fc,
	input         eq_any
);
reg [7:0] regs [0:63] /* verilator public_flat_rd */;
reg       wr_any = 0;
always @(posedge clk) begin
	wr_any <= we & (|cs);
	if (we & cs[0]) regs[{1'b0, addr}] <= data_in;
	if (we & cs[1]) regs[{1'b1, addr}] <= data_in;
end
assign data_out = 8'd0;
assign audio_l  = {2'b00, regs[1], regs[0]};      // (something that follows the frequency register)
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
