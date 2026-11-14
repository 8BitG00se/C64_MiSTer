
module sid_top 
#(
	parameter MULTI_FILTERS = 1, 
	parameter DUAL = 1,
	parameter PHASE = 0            // OCTOPHONIC: 1 = its lookups one clock later (chip_bank's second user)
)
(
	input         reset,

	input         clk,
	input         ce_1m,

	input [N-1:0] cs,
	input         we,
	input   [4:0] addr,
	input   [7:0] data_in,
	output  [7:0] data_out,

	input  [12:0] fc_offset_l,
	input   [7:0] pot_x_l,
	input   [7:0] pot_y_l,
	input  [17:0] ext_in_l,
	output [17:0] audio_l,

	input  [12:0] fc_offset_r, // not used if DUAL is 0
	input   [7:0] pot_x_r,     // not used if DUAL is 0
	input   [7:0] pot_y_r,     // not used if DUAL is 0
	input  [17:0] ext_in_r,    // not used if DUAL is 0
	output [17:0] audio_r,

	input [N-1:0] filter_en,
	input [N-1:0] mode,
	input [(N*2)-1:0] cfg,

	input         ld_clk,
	input  [11:0] ld_addr,
	input  [15:0] ld_data,
	input         ld_wr,

	// OCTOPHONIC: chip personalities (chip_bank.sv) - this pair's lookups out, the measured
	// combined waveforms back ({P+S+T, P+S, P+T, S+T}) for chip A (chip_ql) and chip B (chip_qr).
	// Fix 81 (chip_slots.sv), for each of this pair's two SIDs: chip_on = it plays measured
	// waveforms, chip_bk = whose (0 chip A, 1 chip B), chip_fc = it has a chip's own filter curve
	// (cfg picks it; an 8580 then uses the curve too, and the Fc offset is off)
	output [11:0] tbl_acc,
	input  [31:0] chip_ql,
	input  [31:0] chip_qr,
	input [N-1:0] chip_on,
	input [N-1:0] chip_bk,
	input [N-1:0] chip_fc,

	// OCTOPHONIC (build 6): '1' while the start screen is up (OctoVIC CTRL = $0B, the start screen's;
	// fpga64_sid_iec.vhd) - ENV3 ($1C) then reads the loudest of the SID's three envelopes, so the
	// start screen's eq shows any voice; '0' (every program): the real voice 3 envelope
	input         eq_any,

	// OCTOPHONIC OCTOSCOPE (Fix 55, rtl/octovic/octoscope.sv): voice sc_sel (0-5: the left chip's voices 1-3, then
	// the right's) out, a clock later - {model, FREQ>=839, osc[7:0]!=0, osc[23:8], envelope DAC, DAC less its DC};
	// and both chips' whole output (audio >> 10, as this microsecond first latched it) for the scope's channels 24-31
	input   [2:0] sc_sel,
	output reg [39:0] sc_rec,
	output reg [15:0] sc_aud,

	// Fix 65: the mixer - bit n*3+k = voice k+1 of this pair's chip n muted (zeroed just before the filter; the
	// oscillator, the sync and ring links and the scope's view of the voice are untouched)
	input   [5:0] vmute
);

localparam N = DUAL ? 2 : 1;

function [7:0] env_max(input [7:0] a, input [7:0] b, input [7:0] c);
	reg [7:0] m;
	begin
		m = a > b ? a : b;
		env_max = m > c ? m : c;
	end
endfunction

// Internal Signals
reg  [15:0] Voice_1_Freq[N];
reg  [11:0] Voice_1_Pw[N];
reg   [7:0] Voice_1_Control[N];
reg   [7:0] Voice_1_Att_dec[N];
reg   [7:0] Voice_1_Sus_Rel[N];

reg  [15:0] Voice_2_Freq[N];
reg  [11:0] Voice_2_Pw[N];
reg   [7:0] Voice_2_Control[N];
reg   [7:0] Voice_2_Att_dec[N];
reg   [7:0] Voice_2_Sus_Rel[N];

reg  [15:0] Voice_3_Freq[N];
reg  [11:0] Voice_3_Pw[N];
reg   [7:0] Voice_3_Control[N];
reg   [7:0] Voice_3_Att_dec[N];
reg   [7:0] Voice_3_Sus_Rel[N];

reg  [10:0] Filter_Fc[N];
reg   [7:0] Filter_Res_Filt[N];
reg   [7:0] Filter_Mode_Vol[N];

wire  [7:0] Misc_Osc3[N];
wire  [7:0] Misc_Env3[N];
wire  [7:0] Misc_Env1[N];
wire  [7:0] Misc_Env2[N];

// OCTOSCOPE: each voice's values for the scope ({lock, osc[7:0] != 0, osc[23:8], env[7:0], dac[12:0]}), voice i*3+k
wire [38:0] scv[N*3];

wire [21:0] voice_1[N];
wire [21:0] voice_2[N];
wire [21:0] voice_3[N];

wire        voice_1_PA_MSB[N];
wire        voice_2_PA_MSB[N];
wire        voice_3_PA_MSB[N];

wire  [7:0] _st_out[N*3];
wire  [7:0] p_t_out[N*3];
wire  [7:0] ps__out[N*3];
wire  [7:0] pst_out[N*3];
wire [11:0] acc_t[N*3];

reg  [17:0] audio[N];

reg   [7:0] bus_data[N];
reg  [12:0] Fc_offset[N];

generate
	genvar i;
	
	for(i=0; i<N; i=i+1) begin :chip
		sid_voice v1
		(
			.clock(clk),
			.ce_1m(ce_1m),
			.reset(reset),
			.mode(mode[i]),
			.freq(Voice_1_Freq[i]),
			.pw(Voice_1_Pw[i]),
			.control(Voice_1_Control[i]),
			.att_dec(Voice_1_Att_dec[i]),
			.sus_rel(Voice_1_Sus_Rel[i]),
			.osc_msb_in(voice_3_PA_MSB[i]),
			.osc_msb_out(voice_1_PA_MSB[i]),
			.voice_out(voice_1[i]),
			.env_out(Misc_Env1[i]),
			._st_out(_st_out[i*3+0]),
			.p_t_out(p_t_out[i*3+0]),
			.ps__out(ps__out[i*3+0]),
			.pst_out(pst_out[i*3+0]),
			.acc_t(acc_t[i*3+0]),
			.sc_dac(scv[i*3+0][12:0]),
			.sc_env(scv[i*3+0][20:13]),
			.sc_acc(scv[i*3+0][36:21]),
			.sc_lonz(scv[i*3+0][37]),
			.sc_lock(scv[i*3+0][38])
		);

		sid_voice v2
		(
			.clock(clk),
			.ce_1m(ce_1m),
			.reset(reset),
			.mode(mode[i]),
			.freq(Voice_2_Freq[i]),
			.pw(Voice_2_Pw[i]),
			.control(Voice_2_Control[i]),
			.att_dec(Voice_2_Att_dec[i]),
			.sus_rel(Voice_2_Sus_Rel[i]),
			.osc_msb_in(voice_1_PA_MSB[i]),
			.osc_msb_out(voice_2_PA_MSB[i]),
			.voice_out(voice_2[i]),
			.env_out(Misc_Env2[i]),
			._st_out(_st_out[i*3+1]),
			.p_t_out(p_t_out[i*3+1]),
			.ps__out(ps__out[i*3+1]),
			.pst_out(pst_out[i*3+1]),
			.acc_t(acc_t[i*3+1]),
			.sc_dac(scv[i*3+1][12:0]),
			.sc_env(scv[i*3+1][20:13]),
			.sc_acc(scv[i*3+1][36:21]),
			.sc_lonz(scv[i*3+1][37]),
			.sc_lock(scv[i*3+1][38])
		);

		sid_voice v3
		(
			.clock(clk),
			.ce_1m(ce_1m),
			.reset(reset),
			.mode(mode[i]),
			.freq(Voice_3_Freq[i]),
			.pw(Voice_3_Pw[i]),
			.control(Voice_3_Control[i]),
			.att_dec(Voice_3_Att_dec[i]),
			.sus_rel(Voice_3_Sus_Rel[i]),
			.osc_msb_in(voice_2_PA_MSB[i]),
			.osc_msb_out(voice_3_PA_MSB[i]),
			.voice_out(voice_3[i]),
			.osc_out(Misc_Osc3[i]),
			.env_out(Misc_Env3[i]),
			._st_out(_st_out[i*3+2]),
			.p_t_out(p_t_out[i*3+2]),
			.ps__out(ps__out[i*3+2]),
			.pst_out(pst_out[i*3+2]),
			.acc_t(acc_t[i*3+2]),
			.sc_dac(scv[i*3+2][12:0]),
			.sc_env(scv[i*3+2][20:13]),
			.sc_acc(scv[i*3+2][36:21]),
			.sc_lonz(scv[i*3+2][37]),
			.sc_lock(scv[i*3+2][38])
		);
		
		always @(posedge clk) Fc_offset[i] <= chip_fc[i] ? 13'd0 : i ? fc_offset_r : fc_offset_l;

		// Register Decoding
		always @(posedge clk) begin
			if (reset) begin
				Voice_1_Freq[i]    <= 0;
				Voice_1_Pw[i]      <= 0;
				Voice_1_Control[i] <= 0;
				Voice_1_Att_dec[i] <= 0;
				Voice_1_Sus_Rel[i] <= 0;
				Voice_2_Freq[i]    <= 0;
				Voice_2_Pw[i]      <= 0;
				Voice_2_Control[i] <= 0;
				Voice_2_Att_dec[i] <= 0;
				Voice_2_Sus_Rel[i] <= 0;
				Voice_3_Freq[i]    <= 0;
				Voice_3_Pw[i]      <= 0;
				Voice_3_Control[i] <= 0;
				Voice_3_Att_dec[i] <= 0;
				Voice_3_Sus_Rel[i] <= 0;
				Filter_Fc[i]       <= 0;
				Filter_Res_Filt[i] <= 0;
				Filter_Mode_Vol[i] <= 0;
			end
			else if(cs[i]) begin
				if (we) begin
					bus_data[i] <= data_in;
					case (addr)
						5'h00: Voice_1_Freq[i][7:0] <= data_in;
						5'h01: Voice_1_Freq[i][15:8]<= data_in;
						5'h02: Voice_1_Pw[i][7:0]   <= data_in;
						5'h03: Voice_1_Pw[i][11:8]  <= data_in[3:0];
						5'h04: Voice_1_Control[i]   <= data_in;
						5'h05: Voice_1_Att_dec[i]   <= data_in;
						5'h06: Voice_1_Sus_Rel[i]   <= data_in;
						5'h07: Voice_2_Freq[i][7:0] <= data_in;
						5'h08: Voice_2_Freq[i][15:8]<= data_in;
						5'h09: Voice_2_Pw[i][7:0]   <= data_in;
						5'h0a: Voice_2_Pw[i][11:8]  <= data_in[3:0];
						5'h0b: Voice_2_Control[i]   <= data_in;
						5'h0c: Voice_2_Att_dec[i]   <= data_in;
						5'h0d: Voice_2_Sus_Rel[i]   <= data_in;
						5'h0e: Voice_3_Freq[i][7:0] <= data_in;
						5'h0f: Voice_3_Freq[i][15:8]<= data_in;
						5'h10: Voice_3_Pw[i][7:0]   <= data_in;
						5'h11: Voice_3_Pw[i][11:8]  <= data_in[3:0];
						5'h12: Voice_3_Control[i]   <= data_in;
						5'h13: Voice_3_Att_dec[i]   <= data_in;
						5'h14: Voice_3_Sus_Rel[i]   <= data_in;
						5'h15: Filter_Fc[i][2:0]    <= data_in[2:0];
						5'h16: Filter_Fc[i][10:3]   <= data_in;
						5'h17: Filter_Res_Filt[i]   <= data_in;
						5'h18: Filter_Mode_Vol[i]   <= data_in;
					endcase
				end
				else begin
					case (addr)
						5'h19: bus_data[i] = i ? pot_x_r : pot_x_l;
						5'h1a: bus_data[i] = i ? pot_y_r : pot_y_l;
						5'h1b: bus_data[i] = Misc_Osc3[i];
						5'h1c: bus_data[i] = !eq_any ? Misc_Env3[i] : env_max(Misc_Env1[i], Misc_Env2[i], Misc_Env3[i]);
					endcase
				end
			end
		end
	end
endgenerate

wire [15:0] F0;
wire n = DUAL && state[3];

sid_tables #(MULTI_FILTERS) sid_tables
(
	.clock(clk),
	.mode(mode[n]),

	.acc_t(f_acc_t),
	._st_out(f__st_out),
	.p_t_out(f_p_t_out),
	.ps__out(f_ps__out),
	.pst_out(f_pst_out),
	
	.cfg(cfg[n*2 +:2]),
	.Fc(Filter_Fc[n]),
	.Fc_offset(Fc_offset[n]),
	.F0(F0),
	.ld_clk(ld_clk),
	.ld_addr(ld_addr),
	.ld_data(ld_data),
	.ld_wr(ld_wr),
	.chipf(chip_fc[n])
);

wire  [7:0] f__st_out;
wire  [7:0] f_p_t_out;
wire  [7:0] f_ps__out;
wire  [7:0] f_pst_out;
reg  [11:0] f_acc_t;
reg   [3:0] state;
assign tbl_acc = f_acc_t;

// a chip's measured waveforms, for the SID being captured (voices 0-2 the pair's left SID, 3-5 its right)
reg        ce_d;
always @(posedge clk) ce_d <= ce_1m;
wire       ce_st = PHASE ? ce_d : ce_1m;

always @(posedge clk) begin
	reg [2:0] v;
	reg        cside;
	reg [31:0] cq;
	reg        con;
	if(~&state) state <= state + 1'd1;
	if(ce_st) state <= 0;

	cside = DUAL && (v >= 3'd3);
	cq    = chip_bk[cside] ? chip_qr : chip_ql;
	con   = chip_on[cside];

	case(state)
		1,3,5,7,9,11: begin
			f_acc_t <= acc_t[state[3:1]];
			v <= state[3:1];
		end
	endcase

	case(state)
		3,5,7: begin
			_st_out[v] <= con ? cq[7:0]   : f__st_out;
			p_t_out[v] <= con ? cq[15:8]  : f_p_t_out;
			ps__out[v] <= con ? cq[23:16] : f_ps__out;
			pst_out[v] <= con ? cq[31:24] : f_pst_out;
		end
		9,11,13: if(DUAL) begin
			_st_out[v] <= con ? cq[7:0]   : f__st_out;
			p_t_out[v] <= con ? cq[15:8]  : f_p_t_out;
			ps__out[v] <= con ? cq[23:16] : f_ps__out;
			pst_out[v] <= con ? cq[31:24] : f_pst_out;
		end
	endcase
end

wire [17:0] faudio;

sid_filter sid_filter
(
	.clk(clk),
	.state(state[2:0]),
	.mode(mode[n]),

	.F0(F0),
	.Res_Filt(Filter_Res_Filt[n]),
	.Mode_Vol(Filter_Mode_Vol[n]),
	.voice1(vmute[n*3+0] ? 22'sd0 : voice_1[n]),
	.voice2(vmute[n*3+1] ? 22'sd0 : voice_2[n]),
	.voice3(vmute[n*3+2] ? 22'sd0 : voice_3[n]),
	.ext_in(22'(signed'({n ? ext_in_r : ext_in_l, 3'b000}))),

	.audio(faudio)
);

always @(posedge clk) begin
	reg [17:0] audio0;
	// faudio is two states later than upstream (was 6) because sid_filter
	// pipelines the compressor across filter-states 5-7 to close timing; the
	// first-pass result lands at state 8 and the DUAL slot at 15 (was 14).
	if(state == 8)  audio0 <= faudio;
	if(state == 15) begin
		audio[n] <= faudio;
		audio[0] <= audio0;
	end
end

assign data_out = cs[0] ? bus_data[0] : bus_data[N-1];

// OCTOSCOPE: the voice asked for (the left chip's for 0-2, the right's for 3-5), and the whole outputs as they
// were first latched this microsecond (state 15: the right chip's then follows a volume write until the next
// microsecond - the emulator's scope takes the value before that write)
reg [1:0] s15;
always @(posedge clk) begin
	reg [2:0] q;
	q = (sc_sel < 3'(N*3)) ? sc_sel : 3'd0;
	sc_rec <= {mode[(q >= 3'd3) ? 1 : 0], scv[q]};
	s15 <= {s15[0], &state};
	if (s15 == 2'b01) sc_aud <= {audio[N-1][17:10], audio[0][17:10]};
end

assign audio_l = audio[0];
assign audio_r = audio[N-1];

endmodule
