// sim/octoscope: OctoVIC (with OCTOSCOPE) and the four SID pairs as fpga64_sid_iec.vhd wires them (sid, sid2,
// sid3 and sid4: SIDs 0-1, 2-3, 4-5, 6-7; PHASE 0, 0, 1, 1), for tb.cpp. The dbg_ outputs are the voices' own
// registers (sid_voice's DAC, envelope DAC, oscillator, FREQ) and the chips' outputs, read by hierarchical name -
// the C model of the emulator's octovic_scope_tick takes them, not the scope's own record path.
module tb_top
(
	input             clk,
	input             reset,
	// OctoVIC
	input             cs, wr, rd,
	input       [7:0] addr, din,
	output      [7:0] dout,
	input             pix_en,
	input       [9:0] vic_x,
	input       [8:0] vic_y,
	input       [3:0] vic_index,
	input      [23:0] vic_rgb,
	output     [23:0] rgb,
	input             quarter,
	output     [28:0] ddr_addr,
	output            ddr_rd, ddr_we,
	output     [63:0] ddr_din,
	output      [7:0] ddr_be,
	input             ddr_busy,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,
	// the SIDs
	input             sid_ce,
	input       [7:0] sid_cs,       // one SID (0-7)
	input             sid_we,
	input       [4:0] sid_addr,
	input       [7:0] sid_data,
	input       [1:0] sid_mode,     // left chips, right chips: 0 6581, 1 8580
	// what the checks look at
	output     [12:0] dbg_dac[24],
	output      [7:0] dbg_env[24],
	output     [23:0] dbg_osc[24],
	output     [15:0] dbg_freq[24],
	output     [17:0] dbg_aud[8],
	output            dbg_tick, dbg_latch,
	output            dbg_comp, dbg_dbl, dbg_bad, dbg_rok,
	output      [4:0] dbg_ch,
	output      [1:0] dbg_slot,
	output      [8:0] dbg_wptr, dbg_rptr,
	output     [15:0] dbg_lost
);
wire [2:0]  sc_sel;
wire [39:0] rec[4];
wire [15:0] aud[4];
wire [17:0] al[4], ar[4];
genvar g;
generate for (g = 0; g < 4; g = g + 1) begin : sp
	sid_top #(.PHASE(g >= 2 ? 1 : 0)) s
	(
		.reset(reset), .clk(clk), .ce_1m(sid_ce),
		.cs(sid_cs[g*2 +: 2]), .we(sid_we), .addr(sid_addr), .data_in(sid_data), .data_out(),
		.fc_offset_l(13'd0), .pot_x_l(8'd0), .pot_y_l(8'd0), .ext_in_l(18'd0), .audio_l(al[g]),
		.fc_offset_r(13'd0), .pot_x_r(8'd0), .pot_y_r(8'd0), .ext_in_r(18'd0), .audio_r(ar[g]),
		.filter_en(2'b11), .mode(sid_mode), .cfg(4'd0),
		.ld_clk(clk), .ld_addr(12'd0), .ld_data(16'd0), .ld_wr(1'b0),
		.tbl_acc(), .chip_ql(32'd0), .chip_qr(32'd0), .chip_on(2'b00), .chip_bk(2'b00), .chip_fc(2'b00), .eq_any(1'b0),
		.sc_sel(sc_sel), .sc_rec(rec[g]), .sc_aud(aud[g])
	);
	assign dbg_aud[g*2]   = al[g];
	assign dbg_aud[g*2+1] = ar[g];
end endgenerate

octovic octo
(
	.clk(clk), .reset(reset), .cs(cs), .wr(wr), .rd(rd), .addr(addr), .din(din), .dout(dout),
	.pix_en(pix_en), .vic_x(vic_x), .vic_y(vic_y), .vic_index(vic_index), .vic_rgb(vic_rgb),
	.rgb(rgb), .rgb_vic(), .split(1'b0), .quarter(quarter),
	.ddr_addr(ddr_addr), .ddr_burstcnt(), .ddr_rd(ddr_rd), .ddr_we(ddr_we), .ddr_din(ddr_din), .ddr_be(ddr_be),
	.ddr_busy(ddr_busy), .ddr_dout(ddr_dout), .ddr_dout_ready(ddr_dout_ready), .irq(),
	.sid_ce(sid_ce), .sc_sel(sc_sel),
	.sc_rec0(rec[0]), .sc_rec1(rec[1]), .sc_rec2(rec[2]), .sc_rec3(rec[3]),
	.sc_aud0(aud[0]), .sc_aud1(aud[1]), .sc_aud2(aud[2]), .sc_aud3(aud[3])
);
assign dbg_tick  = octo.scope.tick_done;
assign dbg_latch = octo.scope.latch_now;
assign dbg_comp  = octo.scope.comp_w;
assign dbg_ch    = octo.scope.ch_w;
assign dbg_slot  = octo.scope.cp_w;
assign dbg_dbl   = octo.scope.dbl_w;
assign dbg_bad   = octo.scope.bad_w;
assign dbg_rok   = octo.scope.r_ok;
assign dbg_wptr  = octo.scope.wptr;
assign dbg_rptr  = octo.scope.rptr;
assign dbg_lost  = octo.scope.lost;

assign dbg_dac[0] = sp[0].s.chip[0].v1.dac_out;  assign dbg_env[0] = sp[0].s.chip[0].v1.env_dac[7:0];  assign dbg_osc[0] = sp[0].s.chip[0].v1.oscillator;  assign dbg_freq[0] = sp[0].s.chip[0].v1.freq;
assign dbg_dac[1] = sp[0].s.chip[0].v2.dac_out;  assign dbg_env[1] = sp[0].s.chip[0].v2.env_dac[7:0];  assign dbg_osc[1] = sp[0].s.chip[0].v2.oscillator;  assign dbg_freq[1] = sp[0].s.chip[0].v2.freq;
assign dbg_dac[2] = sp[0].s.chip[0].v3.dac_out;  assign dbg_env[2] = sp[0].s.chip[0].v3.env_dac[7:0];  assign dbg_osc[2] = sp[0].s.chip[0].v3.oscillator;  assign dbg_freq[2] = sp[0].s.chip[0].v3.freq;
assign dbg_dac[3] = sp[0].s.chip[1].v1.dac_out;  assign dbg_env[3] = sp[0].s.chip[1].v1.env_dac[7:0];  assign dbg_osc[3] = sp[0].s.chip[1].v1.oscillator;  assign dbg_freq[3] = sp[0].s.chip[1].v1.freq;
assign dbg_dac[4] = sp[0].s.chip[1].v2.dac_out;  assign dbg_env[4] = sp[0].s.chip[1].v2.env_dac[7:0];  assign dbg_osc[4] = sp[0].s.chip[1].v2.oscillator;  assign dbg_freq[4] = sp[0].s.chip[1].v2.freq;
assign dbg_dac[5] = sp[0].s.chip[1].v3.dac_out;  assign dbg_env[5] = sp[0].s.chip[1].v3.env_dac[7:0];  assign dbg_osc[5] = sp[0].s.chip[1].v3.oscillator;  assign dbg_freq[5] = sp[0].s.chip[1].v3.freq;
assign dbg_dac[6] = sp[1].s.chip[0].v1.dac_out;  assign dbg_env[6] = sp[1].s.chip[0].v1.env_dac[7:0];  assign dbg_osc[6] = sp[1].s.chip[0].v1.oscillator;  assign dbg_freq[6] = sp[1].s.chip[0].v1.freq;
assign dbg_dac[7] = sp[1].s.chip[0].v2.dac_out;  assign dbg_env[7] = sp[1].s.chip[0].v2.env_dac[7:0];  assign dbg_osc[7] = sp[1].s.chip[0].v2.oscillator;  assign dbg_freq[7] = sp[1].s.chip[0].v2.freq;
assign dbg_dac[8] = sp[1].s.chip[0].v3.dac_out;  assign dbg_env[8] = sp[1].s.chip[0].v3.env_dac[7:0];  assign dbg_osc[8] = sp[1].s.chip[0].v3.oscillator;  assign dbg_freq[8] = sp[1].s.chip[0].v3.freq;
assign dbg_dac[9] = sp[1].s.chip[1].v1.dac_out;  assign dbg_env[9] = sp[1].s.chip[1].v1.env_dac[7:0];  assign dbg_osc[9] = sp[1].s.chip[1].v1.oscillator;  assign dbg_freq[9] = sp[1].s.chip[1].v1.freq;
assign dbg_dac[10] = sp[1].s.chip[1].v2.dac_out;  assign dbg_env[10] = sp[1].s.chip[1].v2.env_dac[7:0];  assign dbg_osc[10] = sp[1].s.chip[1].v2.oscillator;  assign dbg_freq[10] = sp[1].s.chip[1].v2.freq;
assign dbg_dac[11] = sp[1].s.chip[1].v3.dac_out;  assign dbg_env[11] = sp[1].s.chip[1].v3.env_dac[7:0];  assign dbg_osc[11] = sp[1].s.chip[1].v3.oscillator;  assign dbg_freq[11] = sp[1].s.chip[1].v3.freq;
assign dbg_dac[12] = sp[2].s.chip[0].v1.dac_out;  assign dbg_env[12] = sp[2].s.chip[0].v1.env_dac[7:0];  assign dbg_osc[12] = sp[2].s.chip[0].v1.oscillator;  assign dbg_freq[12] = sp[2].s.chip[0].v1.freq;
assign dbg_dac[13] = sp[2].s.chip[0].v2.dac_out;  assign dbg_env[13] = sp[2].s.chip[0].v2.env_dac[7:0];  assign dbg_osc[13] = sp[2].s.chip[0].v2.oscillator;  assign dbg_freq[13] = sp[2].s.chip[0].v2.freq;
assign dbg_dac[14] = sp[2].s.chip[0].v3.dac_out;  assign dbg_env[14] = sp[2].s.chip[0].v3.env_dac[7:0];  assign dbg_osc[14] = sp[2].s.chip[0].v3.oscillator;  assign dbg_freq[14] = sp[2].s.chip[0].v3.freq;
assign dbg_dac[15] = sp[2].s.chip[1].v1.dac_out;  assign dbg_env[15] = sp[2].s.chip[1].v1.env_dac[7:0];  assign dbg_osc[15] = sp[2].s.chip[1].v1.oscillator;  assign dbg_freq[15] = sp[2].s.chip[1].v1.freq;
assign dbg_dac[16] = sp[2].s.chip[1].v2.dac_out;  assign dbg_env[16] = sp[2].s.chip[1].v2.env_dac[7:0];  assign dbg_osc[16] = sp[2].s.chip[1].v2.oscillator;  assign dbg_freq[16] = sp[2].s.chip[1].v2.freq;
assign dbg_dac[17] = sp[2].s.chip[1].v3.dac_out;  assign dbg_env[17] = sp[2].s.chip[1].v3.env_dac[7:0];  assign dbg_osc[17] = sp[2].s.chip[1].v3.oscillator;  assign dbg_freq[17] = sp[2].s.chip[1].v3.freq;
assign dbg_dac[18] = sp[3].s.chip[0].v1.dac_out;  assign dbg_env[18] = sp[3].s.chip[0].v1.env_dac[7:0];  assign dbg_osc[18] = sp[3].s.chip[0].v1.oscillator;  assign dbg_freq[18] = sp[3].s.chip[0].v1.freq;
assign dbg_dac[19] = sp[3].s.chip[0].v2.dac_out;  assign dbg_env[19] = sp[3].s.chip[0].v2.env_dac[7:0];  assign dbg_osc[19] = sp[3].s.chip[0].v2.oscillator;  assign dbg_freq[19] = sp[3].s.chip[0].v2.freq;
assign dbg_dac[20] = sp[3].s.chip[0].v3.dac_out;  assign dbg_env[20] = sp[3].s.chip[0].v3.env_dac[7:0];  assign dbg_osc[20] = sp[3].s.chip[0].v3.oscillator;  assign dbg_freq[20] = sp[3].s.chip[0].v3.freq;
assign dbg_dac[21] = sp[3].s.chip[1].v1.dac_out;  assign dbg_env[21] = sp[3].s.chip[1].v1.env_dac[7:0];  assign dbg_osc[21] = sp[3].s.chip[1].v1.oscillator;  assign dbg_freq[21] = sp[3].s.chip[1].v1.freq;
assign dbg_dac[22] = sp[3].s.chip[1].v2.dac_out;  assign dbg_env[22] = sp[3].s.chip[1].v2.env_dac[7:0];  assign dbg_osc[22] = sp[3].s.chip[1].v2.oscillator;  assign dbg_freq[22] = sp[3].s.chip[1].v2.freq;
assign dbg_dac[23] = sp[3].s.chip[1].v3.dac_out;  assign dbg_env[23] = sp[3].s.chip[1].v3.env_dac[7:0];  assign dbg_osc[23] = sp[3].s.chip[1].v3.oscillator;  assign dbg_freq[23] = sp[3].s.chip[1].v3.freq;
endmodule
