// © 2026 Mong00se
// MY CHIPS, PER SID (Fix 81) test bench: chip_slots + chip_bank + the four SID pairs wired as rtl/fpga64_sid_iec.vhd
// wires them (pairs 3 and 4 a clock behind), all the real SID - voices, tables, filter. A fifth pair (index 8, 9) is
// the reference: the core's own chips with My Chips out of it - a 6581 (8) and an 8580 (9), default filter.
// Every SID gets the same register writes.
module tb_top
(
	input         clk, ce_1m,
	input         ioctl_download, ioctl_wr,
	input   [7:0] ioctl_index,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_data,
	input         enable,
	input  [15:0] slot_opt,
	input   [1:0] menu_ver,
	input   [3:0] menu_cfg,
	input  [12:0] fc_off_l, fc_off_r,
	input         we,
	input   [4:0] addr,
	input   [7:0] din,
	output [15:0] f0  [10],      // the F0 each SID's filter took this microsecond
	output  [7:0] osc3[10],
	output [17:0] aud [10],
	output  [7:0] dbg_ver, dbg_on, dbg_bk, dbg_fc,
	output [15:0] dbg_cfg,
	output  [2:0] loaded
);
wire        cwe, cwb;
wire  [1:0] cwt;
wire [11:0] cwi;
wire  [7:0] cwd;
wire        crv_wr;
wire [11:0] crv_addr;
wire [15:0] crv_data;
wire  [7:0] ver, con, cbk, cfc;
wire [15:0] cfg;
chip_slots slots
(
	.clk(clk), .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data), .enable(enable), .slot_opt(slot_opt), .menu_ver(menu_ver), .menu_cfg(menu_cfg),
	.chip_we(cwe), .chip_wbank(cwb), .chip_wtbl(cwt), .chip_widx(cwi), .chip_wdata(cwd),
	.crv_wr(crv_wr), .crv_addr(crv_addr), .crv_data(crv_data),
	.sid_ver(ver), .sid_cfg(cfg), .chip_on(con), .chip_bk(cbk), .chip_fc(cfc), .loaded(loaded)
);
assign dbg_ver = ver; assign dbg_on = con; assign dbg_bk = cbk; assign dbg_fc = cfc; assign dbg_cfg = cfg;

wire [11:0] tacc[5];
wire [31:0] ql[4], qr[4];
chip_bank bank
(
	.clk(clk), .ce_1m(ce_1m), .we(cwe), .wside(cwb), .wtbl(cwt), .widx(cwi), .wdata(cwd),
	.acc0(tacc[0]), .acc1(tacc[1]), .acc2(tacc[2]), .acc3(tacc[3]),
	.ql0(ql[0]), .ql1(ql[1]), .ql2(ql[2]), .ql3(ql[3]), .qr0(qr[0]), .qr1(qr[1]), .qr2(qr[2]), .qr3(qr[3])
);

genvar g;
generate for (g = 0; g < 5; g = g + 1) begin : sp
	wire [17:0] al, ar;
	sid_top #(.PHASE((g == 2 || g == 3) ? 1 : 0)) s
	(
		.reset(1'b0), .clk(clk), .ce_1m(ce_1m),
		.cs(2'b11), .we(we), .addr(addr), .data_in(din), .data_out(),
		.fc_offset_l(g < 4 ? fc_off_l : 13'd0), .pot_x_l(8'd0), .pot_y_l(8'd0), .ext_in_l(18'd0), .audio_l(al),
		.fc_offset_r(g < 4 ? fc_off_r : 13'd0), .pot_x_r(8'd0), .pot_y_r(8'd0), .ext_in_r(18'd0), .audio_r(ar),
		.filter_en(2'b11),
		.mode   (g < 4 ? ver[g*2 +: 2] : 2'b10),
		.cfg    (g < 4 ? cfg[g*4 +: 4] : 4'd0),
		.ld_clk(clk), .ld_addr(crv_addr), .ld_data(crv_data), .ld_wr(crv_wr),
		.tbl_acc(tacc[g]),
		.chip_ql(g < 4 ? ql[g] : 32'd0), .chip_qr(g < 4 ? qr[g] : 32'd0),
		.chip_on(g < 4 ? con[g*2 +: 2] : 2'b00),
		.chip_bk(g < 4 ? cbk[g*2 +: 2] : 2'b00),
		.chip_fc(g < 4 ? cfc[g*2 +: 2] : 2'b00),
		.eq_any(1'b0), .sc_sel(3'd0), .sc_rec(), .sc_aud(), .vmute(6'd0)
	);
	reg [15:0] f0l, f0r;
	always @(posedge clk) begin
		if (s.state == 4'd2)  f0l <= s.F0;     // the clock the filter takes it (sid_filter state 2), left SID
		if (s.state == 4'd10) f0r <= s.F0;     //   ...and the right
	end
	assign f0[g*2] = f0l;            assign f0[g*2+1] = f0r;
	assign osc3[g*2] = s.Misc_Osc3[0]; assign osc3[g*2+1] = s.Misc_Osc3[1];
	assign aud[g*2] = al;            assign aud[g*2+1] = ar;
end endgenerate
endmodule
