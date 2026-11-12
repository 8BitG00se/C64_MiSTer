// LEVEL 2 REMASTER - the unit's testbench top: rtl/remaster.sv in front of rtl/rgb256.sv, as in c64.sv.
// The C64's RAM and the DDR3 are the C++ side's (tb.cpp).                          (c) 2026 Mong00se
module tb_rm
(
	input         clk,
	input         reset,
	input         on, learn, reload,
	input         ld_download, ld_wr,
	input  [24:0] ld_addr,
	input   [7:0] ld_data,
	input   [3:0] index,
	input  [28:0] tag,
	input  [25:0] l2_pix,
	input [183:0] l2_spr,
	input   [1:0] bank,
	input         vsync_in,
	input   [2:0] palette,
	output [23:0] rgb,
	output  [1:0] d_kind,
	output  [3:0] dbg_index,
	output [28:0] dbg_tag,
	output        dbg_ovr,
	output  [7:0] dbg_slot,
	output        d_vsync,
	output        loaded, l2_ok,
	output [15:0] lcount,
	output [15:0] x_addr,
	output        x_req,
	input         x_ack,
	input   [7:0] x_q,
	output [28:0] ddr_addr,
	output  [7:0] ddr_burstcnt,
	output        ddr_rd, ddr_we,
	output [63:0] ddr_din,
	input         ddr_busy,
	input  [63:0] ddr_dout,
	input         ddr_ready
);
wire  [3:0] d_index;
wire [28:0] d_tag;
wire        ovr;
wire  [7:0] ovr_slot;
wire  [7:0] ddr_be;
wire  [3:0] npal;
assign d_kind = d_tag[28:27];
assign dbg_index = d_index;
assign dbg_tag = d_tag;
assign dbg_ovr = ovr;
assign dbg_slot = ovr_slot;
remaster remaster
(
	.clk(clk), .reset(reset), .on(on), .learn(learn), .reload(reload),
	.index(index), .tag(tag), .l2_pix(l2_pix), .l2_spr(l2_spr), .bank(bank), .vsync_in(vsync_in),
	.d_index(d_index), .d_tag(d_tag), .d_vsync(d_vsync), .ovr(ovr), .ovr_slot(ovr_slot),
	.x_addr(x_addr), .x_req(x_req), .x_ack(x_ack), .x_q(x_q),
	.ddr_addr(ddr_addr), .ddr_burstcnt(ddr_burstcnt), .ddr_rd(ddr_rd), .ddr_we(ddr_we), .ddr_din(ddr_din), .ddr_be(ddr_be),
	.ddr_busy(ddr_busy), .ddr_dout(ddr_dout), .ddr_ready(ddr_ready),
	.l2_ok(l2_ok), .lcount(lcount)
);
rgb256 recolour
(
	.clk(clk), .ld_download(ld_download), .ld_wr(ld_wr), .ld_addr(ld_addr), .ld_data(ld_data),
	.index(d_index), .tag(d_tag), .ovr(ovr), .ovr_slot(ovr_slot),
	.palette(palette), .npal(npal), .rgb(rgb), .loaded(loaded)
);
endmodule
