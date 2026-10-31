// four SID pairs (pairs 3 and 4 a clock behind) sharing one chip_bank, as in fpga64_sid_iec.vhd
module tb (
	input clk, input ce_1m,
	input we_c, input wside, input [1:0] wtbl, input [11:0] widx, input [7:0] wdata,
	input [1:0] chip_on,
	input [3:0] pair, input side, input we, input [4:0] addr, input [7:0] din,
	output [7:0] dout0, output [7:0] dout1, output [7:0] dout2, output [7:0] dout3
);
wire [11:0] a0, a1, a2, a3;
wire [31:0] l0, l1, l2, l3, r0, r1, r2, r3;
chip_bank cb(.clk(clk), .ce_1m(ce_1m), .we(we_c), .wside(wside), .wtbl(wtbl), .widx(widx), .wdata(wdata),
	.acc0(a0), .acc1(a1), .acc2(a2), .acc3(a3), .ql0(l0), .ql1(l1), .ql2(l2), .ql3(l3), .qr0(r0), .qr1(r1), .qr2(r2), .qr3(r3));
wire [1:0] cs0 = pair[0] ? (side ? 2'b10 : 2'b01) : 2'b00;
wire [1:0] cs1 = pair[1] ? (side ? 2'b10 : 2'b01) : 2'b00;
wire [1:0] cs2 = pair[2] ? (side ? 2'b10 : 2'b01) : 2'b00;
wire [1:0] cs3 = pair[3] ? (side ? 2'b10 : 2'b01) : 2'b00;
`define PAIR(n, ph, csx, acx, lx, rx, dx) \
sid_top #(.PHASE(ph)) p``n (.reset(1'b0), .clk(clk), .ce_1m(ce_1m), .cs(csx), .we(we), .addr(addr), .data_in(din), .data_out(dx), \
	.fc_offset_l(13'd0), .pot_x_l(8'd0), .pot_y_l(8'd0), .ext_in_l(18'd0), .audio_l(), \
	.fc_offset_r(13'd0), .pot_x_r(8'd0), .pot_y_r(8'd0), .ext_in_r(18'd0), .audio_r(), \
	.filter_en(2'b11), .mode(2'b10), .cfg(4'd0), .ld_clk(clk), .ld_addr(12'd0), .ld_data(16'd0), .ld_wr(1'b0), \
	.tbl_acc(acx), .chip_ql(lx), .chip_qr(rx), .chip_on(chip_on));
`PAIR(0, 0, cs0, a0, l0, r0, dout0)
`PAIR(1, 0, cs1, a1, l1, r1, dout1)
`PAIR(2, 1, cs2, a2, l2, r2, dout2)
`PAIR(3, 1, cs3, a3, l3, r3, dout3)
endmodule
