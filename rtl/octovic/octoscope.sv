// =====================================================================================
//  OCTOSCOPE (OctoVIC version 5, Fix 55) - a real oscilloscope of every SID voice.
//  (c) 2026 Mong00se. See docs/OCTOVIC.md, OCTOSCOPE, and docs/OCTOVIC_MEMORY.md.
//
//  The capture side of it: every microsecond (the SIDs' ce_1m) each of 32 channels takes a sample -
//  channels 0-23 the 24 voices (SID s, voice v: 3s + v), the waveform centred on its own middle times its
//  envelope, (DAC - 2048) x ENV >> 12; channels 24-31 each SID's whole output >> 10 - and stores it the way
//  the emulator's sc_store does, exactly:
//
//    - FREQ >= 839: in step with the voice's own oscillator. A capture starts at a wrap and sample n is
//      written once n <= cycle x 152 + (acc[23:8] x 152) >> 16, so the 304 samples are 2 whole cycles;
//      at the wrap that ends the second cycle the rest is filled with the sample of that moment and the
//      capture is complete. A capture still not complete 40,000 us after it started gives way to:
//    - otherwise: by time, a sample every 66 us into the same 304, complete each time it fills.
//
//  A complete capture is kept until the next; at the start of each frame (the renderer's raster line 0, at the
//  end of a whole microsecond) the newest complete capture of every channel becomes the one shown for that frame.
//
//  How it is built: one channel a clock (32 clocks = a microsecond = 32 channels), pipelined. The samples live
//  in the DDR3 (byte $33000000, just above the 16 MB of VRAM): three slots of 304 bytes a channel - the one
//  being captured, the newest complete one, the one shown - and only the slot numbers change, nothing is copied.
//  Each channel gathers its samples into an 8-byte word (with byte enables) on chip and hands a whole word to a
//  write queue when the next sample goes to another word or the capture completes: at most one word a channel a
//  microsecond, and far fewer for any note. Two places where the emulator writes many samples at once (the jump
//  into cycle 2 after a sync / test-bit wrap, and the fill at the end) are not written at all: the slot keeps them
//  as a rule (a "hole" [hs..152] = hv, and "from fn on" = fv) that the reader applies.
//  The frame's latch is applied to each channel as the engine next passes it (within a microsecond); the shown
//  slots may be read once that has happened and every word queued before the latch is in the DDR3 (r_ok).
// =====================================================================================
(* multstyle = "dsp" *)          // its multiplies in the DSP blocks (there are some to spare; logic is short)
module octoscope
(
	input             clk,
	input             reset,
	input             ce_1m,          // the SIDs' microsecond (their registers change on this edge)

	// the four sid_tops: voice sc_sel of each (0-5), a clock later its record; their whole outputs
	output reg  [2:0] sc_sel,
	input      [39:0] rec0, rec1, rec2, rec3,   // {model, FREQ>=839, wrapped, acc[23:8], ENV DAC, DAC - DC}
	input      [15:0] aud0, aud1, aud2, aud3,   // {right, left} audio[17:10]

	// the frame starts: latch the newest complete captures for showing (done at the end of a microsecond)
	input             latch_req,
	output reg        latch_now,      // (a pulse: the latch happened)
	output reg        tick_done,      // (a pulse: every channel of a microsecond has been stored - for the checks)
	output reg        gen,            // flips at each latch (the renderer's cache of a slot is from before)
	output            r_ok,           // the shown slots may be read (latched, applied, their words in the DDR3)

	// the write queue to the DDR3 (OctoVIC's port: after the renderer's reads, before them when it fills up)
	output            wq_valid,
	output     [11:0] wq_addr,        // the word: slot (channel x 3 + slot) x 38 + word
	output     [63:0] wq_data,
	output      [7:0] wq_be,
	output            wq_full,        // over half full: before the renderer's reads that are not due yet
	input             wq_pop,

	// the renderer: a channel's shown slot, its rules (2 clocks after r_ch)
	input       [4:0] r_ch,
	output reg  [6:0] r_slot,         // channel x 3 + slot
	output reg [11:0] r_word,         // its first word (slot x 38), a clock after r_slot
	output reg [33:0] r_desc,         // {hole on, hole start, hole value, fill from, fill value}
	output reg        r_zero,         // nothing captured since reset: all 0

	// Fix 72, the scope screen (scope_screen.sv): a second look-up of its own, the same answers 2 clocks after r2_ch
	input       [4:0] r2_ch,
	output reg [11:0] r2_word,
	output reg [33:0] r2_desc,
	output reg        r2_zero
);

localparam SCN = 304;

// ---------------------------------------------------------------------------------
//  the on-chip memories (block RAM: there is room; logic is what is short)
// ---------------------------------------------------------------------------------
// each slot's rules
reg [33:0] dmem[0:95];
reg        dm_we;
reg  [6:0] dm_wa;
reg [33:0] dm_wd;
reg  [6:0] dm_ra;
always @(posedge clk) begin
	if (dm_we) dmem[dm_wa] <= dm_wd;
	r_desc <= dmem[dm_ra];
end

// Fix 72: the scope screen's own copy of the rules (a second read port; written with the first)
reg [33:0] dmem2[0:95];
reg  [6:0] dm2_ra;
always @(posedge clk) begin
	if (dm_we) dmem2[dm_wa] <= dm_wd;
	r2_desc <= dmem2[dm2_ra];
end

// each channel: its capture {n, cycle, on, age, tick, hole on, hole start, hole value} (51), its slots
// {captured ^0, complete ^1, shown ^1, nothing complete yet (inverted), latch seen} (8), the word being
// gathered {on, slot, word, data, byte enables} (81), and last microsecond's oscillator {osc[23:8], osc[7:0]!=0}
// (17: a wrap is the new below the old) - all 0 after reset is the right start
reg [156:0] cmem[0:31];
reg         cm_we;
reg   [4:0] cm_wa, cm_ra;
reg [156:0] cm_wd, cm_q;
always @(posedge clk) begin
	if (cm_we) cmem[cm_wa] <= cm_wd;
	cm_q <= cmem[cm_ra];
end

// the write queue: 256 words {word address (12), data (64), byte enables (8)}
reg  [83:0] wmem[0:255];
reg         wm_we;
reg  [83:0] wm_wd;
reg   [7:0] wm_wa;
reg   [8:0] wptr, wptr1, wptr2, rptr;          // (wptr2: what the read side may see - the RAM's write is 2 clocks old)
reg  [83:0] wq_q;
wire  [8:0] rptr_n = rptr + {8'd0, wq_pop};
always @(posedge clk) begin
	if (wm_we) wmem[wm_wa] <= wm_wd;
	wq_q <= wmem[rptr_n[7:0]];
end
assign wq_valid = wptr2 != rptr;
assign {wq_addr, wq_data, wq_be} = wq_q;
assign wq_full  = (wptr2 - rptr) >= 9'd128;
reg   [8:0] wq_mark;                           // the queue as it stood at the latch
reg         lat_busy;                          // a latch not yet applied to every channel
reg  [15:0] lost;                              // (words that found the queue full - never, by design; checked)
reg         wq_ok;                             // the queue has passed the mark (kept: the counters go round)
assign r_ok = !lat_busy && wq_ok;
always @(posedge clk) begin
	if (reset) begin rptr <= 0; wptr1 <= 0; wptr2 <= 0; wq_ok <= 1; end
	else begin
		rptr <= rptr_n; wptr1 <= wptr; wptr2 <= wptr1;
		if (latch_now) wq_ok <= 0;
		else if ($signed(rptr - wq_mark) >= 0) wq_ok <= 1;
	end
end

// the shown slots, for the renderer (each written by the engine as it applies a latch)
reg  [1:0] disp[32];
reg [31:0] disp_z;
always @(posedge clk) begin
	dm_ra  <= {r_ch, 1'b0} + {2'd0, r_ch} + {5'd0, disp[r_ch]};
	r_slot <= {r_ch, 1'b0} + {2'd0, r_ch} + {5'd0, disp[r_ch]};
	r_zero <= disp_z[r_ch];
	r_word <= r_slot * 12'd38;
end
// Fix 72: the same for the scope screen (slot x 38 by adding: 32 + 4 + 2)
reg  [6:0] r2_slot;
reg        r2_z1;
always @(posedge clk) begin
	dm2_ra  <= {r2_ch, 1'b0} + {2'd0, r2_ch} + {5'd0, disp[r2_ch]};
	r2_slot <= {r2_ch, 1'b0} + {2'd0, r2_ch} + {5'd0, disp[r2_ch]};
	r2_z1   <= disp_z[r2_ch];
	r2_zero <= r2_z1;
	r2_word <= {r2_slot, 5'd0} + {3'd0, r2_slot, 2'd0} + {4'd0, r2_slot, 1'b0};
end

// ---------------------------------------------------------------------------------
//  the engine: slot k of a microsecond is channel k
//    c_k   sc_sel = voice of channel k          (k < 24)
//    c_k+1 the sid_tops' records out; cmem read of channel k asked
//    c_k+2 stage A: the record, the state     -> the sample, the phase
//    c_k+3 stage B: sc_store                  -> the writes (at the end of c_k+3)
// ---------------------------------------------------------------------------------
reg  [5:0] ks;              // the slot being selected (32: none)
reg  [2:0] ksel;
reg  [1:0] kpair;
reg        v1, vA, vB;
reg  [4:0] ch1, chA, chB;
reg        fresh;           // since reset: the first microsecond starts from nothing

always @(posedge clk) begin
	if (reset) begin ks <= 6'd32; sc_sel <= 0; ksel <= 0; kpair <= 0; end
	else if (ce_1m) begin ks <= 0; sc_sel <= 0; ksel <= 0; kpair <= 0; end
	else if (!ks[5]) begin
		ks <= ks + 6'd1;
		if (ksel == 3'd5) begin ksel <= 0; kpair <= kpair + 2'd1; end else ksel <= ksel + 3'd1;
		sc_sel <= (ksel == 3'd5) ? 3'd0 : ksel + 3'd1;
	end
end

// stage A inputs
reg [39:0] recA;
reg  [7:0] audA;
reg        isvA;
reg  [1:0] pair1;
always @(posedge clk) begin
	v1 <= !reset && !ks[5]; ch1 <= ks[4:0]; pair1 <= kpair;
	cm_ra <= ks[4:0];
	vA <= v1; chA <= ch1;
	case (pair1)
		0: recA <= rec0;  1: recA <= rec1;  2: recA <= rec2;  default: recA <= rec3;
	endcase
	isvA <= ch1 < 5'd24;
	case (ch1[2:0])
		0: audA <= aud0[7:0];  1: audA <= aud0[15:8];  2: audA <= aud1[7:0];  3: audA <= aud1[15:8];
		4: audA <= aud2[7:0];  5: audA <= aud2[15:8];  6: audA <= aud3[7:0];  default: audA <= aud3[15:8];
	endcase
end

// stage A: the sample, the phase within the cycle
reg signed [7:0] sB;
reg         wrapB, lockB;
reg   [7:0] xB;
reg [156:0] stB;
reg  [16:0] oscB;
always @(posedge clk) begin
	reg signed [12:0] w;
	reg signed [21:0] p;
	reg signed  [9:0] q;
	reg        [23:0] xm;
	vB <= vA; chB <= chA;
	w  = $signed(recA[12:0]) + (recA[39] ? 13'sd0 : -13'sd1152);      // DAC + DC - 2048 (DC 0x380 6581, 0x800 8580)
	p  = w * $signed({1'b0, recA[20:13]});
	q  = isvA ? 10'(p >>> 12) : $signed({{2{audA[7]}}, audA});
	sB <= (q > 10'sd127) ? 8'sd127 : (q < -10'sd127) ? -8'sd127 : q[7:0];
	begin
		reg [16:0] po;
		po = fresh ? 17'd0 : cm_q[156:140];
		// the oscillator wrapped: new < old. Its low byte is not handed over, only whether it is 0 - enough: with
		// osc[23:8] the same, the new is below the old only when it was set to 0 (an overflow lowers osc[23:8])
		wrapB <= isvA & ((recA[36:21] < po[16:1]) || (recA[36:21] == po[16:1] && !recA[37] && po[0]));
	end
	oscB  <= recA[37:21];
	lockB <= isvA & recA[38];
	xm  = {8'd0, recA[36:21]} * 24'd152;
	xB  <= xm[23:16];
	stB <= fresh ? 157'd0 : cm_q;
	if (reset) fresh <= 1;
	else if (vA && chA == 5'd31) fresh <= 0;
end

// stage B: sc_store
// for the checks only (nothing reads them in the core): a capture completed - its channel and slot; two words to
// queue for one channel in one microsecond (never happens); a word queued for the slot being shown (never)
reg         comp_w, dbl_w, bad_w;
reg   [1:0] cp_w;
reg   [4:0] ch_w;
always @(posedge clk) begin
	dm_we <= 0; cm_we <= 0; wm_we <= 0; latch_now <= 0; tick_done <= 0; comp_w <= 0; dbl_w <= 0; bad_w <= 0;
	if (reset) begin
		gen <= 0; lat_busy <= 0; wptr <= 0; wq_mark <= 0; lost <= 0;
		for (int c = 0; c < 32; c = c + 1) disp[c] <= 2'd1;
		disp_z <= '1;
	end
	else if (vB) begin
		reg  [8:0] n;  reg cyc, on;  reg [15:0] age;  reg [6:0] tick;  reg hok;  reg [7:0] hs, hv;
		reg  [1:0] cp, dn, ds;  reg dz, lg;
		reg        sv;  reg [1:0] ss;  reg [5:0] sw;  reg [63:0] sd;  reg [7:0] sbe;
		reg        comp, timed, wr, ret, enq;
		reg  [8:0] t, wi;
		reg  [1:0] ncap, wslot;
		reg [33:0] dsc;
		reg [83:0] e;
		reg  [6:0] sidx;
		{n, cyc, on, age, tick, hok, hs, hv} = stB[50:0];
		{cp, dn, ds, dz, lg} = stB[58:51];
		dn = dn ^ 2'd1; ds = ds ^ 2'd1; dz = !dz;
		{sv, ss, sw, sd, sbe} = stB[139:59];
		// a frame's latch not yet applied to this channel: what was complete then is what is shown
		if (lg != gen) begin
			ds = dn; lg = gen;
			disp[chB] <= dn; disp_z[chB] <= dz;
		end
		comp = 0; timed = 0; wr = 0; ret = 0; wi = 0; dsc = 0; enq = 0; e = 0;
		ncap = 2'd3 - cp - ds;                     // the slot that is neither the new complete one nor the shown one
		if (age != 16'hFFFF) age = age + 16'd1;
		if (lockB) begin
			if (wrapB) begin
				if (on) begin
					if (cyc) begin comp = 1; dsc = {hok, hs, hv, n, sB}; on = 0; end     // 2 cycles: the rest is this sample
					else cyc = 1;
				end
				if (!on) begin on = 1; cyc = 0; n = 0; age = 0; hok = 0; end
			end
			if (on && age < 16'd40000) begin
				ret = 1;
				t = cyc ? 9'd152 + {1'b0, xB} : {1'b0, xB};
				if (n <= t && n < 9'(SCN)) begin
					if (t == n) begin wr = 1; wi = n; end
					else begin hok = 1; hs = n[7:0]; hv = sB; end     // the jump into cycle 2: [n..152] all this sample
					n = t + 9'd1;
				end
			end
		end
		if (!ret) begin                            // by time: a sample every 66 us
			if (on) begin on = 0; n = 0; end
			tick = tick + 7'd1;
			if (tick >= 7'd66) begin
				tick = 0; wr = 1; wi = n; n = n + 9'd1;
				if (n >= 9'(SCN)) begin comp = 1; timed = 1; n = 0; dsc = {1'b0, 8'd0, 8'd0, 9'(SCN), 8'd0}; end
			end
		end
		// a locked capture's sample after its completion goes into the new slot; a timed capture's last sample is
		// in the slot that just completed
		wslot = (comp && !timed) ? ncap : cp;
		// the word being gathered goes to the queue when this sample is for another word (or slot), or the capture
		// it belongs to is complete; a locked completion hands it over before this sample starts the next slot's
		if (wr && sv && (ss != wslot || sw != wi[8:3])) begin enq = 1; e = {sv, ss, sw, sd, sbe}; sv = 0; sbe = 0; end
		if (comp && !timed && sv) begin enq = 1; e = {sv, ss, sw, sd, sbe}; sv = 0; sbe = 0; end
		if (wr) begin
			if (!sv) begin sbe = 0; ss = wslot; sw = wi[8:3]; end
			sv = 1;
			sd[wi[2:0]*8 +: 8] = sB;
			sbe[wi[2:0]] = 1'b1;
		end
		if (comp && timed) begin if (enq) dbl_w <= 1; enq = 1; e = {sv, ss, sw, sd, sbe}; sv = 0; sbe = 0; end
		if (enq) begin
			bad_w <= e[79:78] == ds;
			sidx = {chB, 1'b0} + {2'd0, chB} + {5'd0, e[79:78]};
			wm_wd <= {sidx * 12'd38 + {6'd0, e[77:72]}, e[71:0]};
			if ((wptr - rptr) == 9'd256) begin if (lost != 16'hFFFF) lost <= lost + 16'd1; end
			else begin wm_we <= 1; wm_wa <= wptr[7:0]; wptr <= wptr + 9'd1; end
		end
		dm_we <= comp; dm_wa <= {chB, 1'b0} + {2'd0, chB} + {5'd0, cp}; dm_wd <= dsc;
		comp_w <= comp; cp_w <= cp; ch_w <= chB;
		if (comp) begin dn = cp; cp = ncap; dz = 0; end
		cm_we <= 1; cm_wa <= chB;
		cm_wd <= {oscB[15:0], oscB[16], sv, ss, sw, sd, sbe, cp, dn ^ 2'd1, ds ^ 2'd1, !dz, lg, n, cyc, on, age, tick, hok, hs, hv};
		if (chB == 5'd31) begin
			tick_done <= 1;
			if (lat_busy) lat_busy <= 0;                 // every channel has applied the latch
			// the frame's latch: at the end of a whole microsecond (channel 31's own news included)
			if (latch_req || lpend) begin
				gen <= !gen; lat_busy <= 1; latch_now <= 1;
				wq_mark <= wptr + {8'd0, enq && (wptr - rptr) != 9'd256};
			end
		end
	end
end
reg lpend;
always @(posedge clk) begin
	if (reset) lpend <= 0;
	else if (vB && chB == 5'd31) lpend <= 0;
	else if (latch_req) lpend <= 1;
end

endmodule

// ---------------------------------------------------------------------------------
//  one sample of a line of the trace (octovic draws a pixel a clock with it): the sample (the slot's rules
//  applied), and the flags {d >= 0, d <= 0, d >= -1, d <= 1} of d = (line - SCY) - y, y = -(s x SCG) / 128
//  rounded towards 0 - a clock later
// ---------------------------------------------------------------------------------
(* multstyle = "dsp" *)
module octoscope_px
(
	input             clk,
	input       [8:0] i,              // the sample
	input       [7:0] b,              // its byte as written
	input      [33:0] desc,           // the slot's rules
	input             zero,           // nothing captured: 0
	input       [7:0] g,              // SCG
	input       [9:0] dy,             // line - SCY
	output reg  [3:0] f
);
always @(posedge clk) begin
	reg signed  [7:0] sm;
	reg signed [16:0] pr;
	reg signed  [9:0] q, d;
	sm = zero ? 8'sd0
	   : (i >= desc[16:8]) ? desc[7:0]                                       // from fn on: fv
	   : (desc[33] && i >= {1'b0, desc[32:25]} && i <= 9'd152) ? desc[24:17] // the hole: hv
	   : b;
	pr = sm * $signed({1'b0, g});
	q  = 10'((pr + (pr[16] ? 17'sd127 : 17'sd0)) >>> 7);                     // (s x g) / 128 towards 0 = -y
	d  = $signed(dy) + q;
	f <= {d >= 0, d <= 0, d >= -10'sd1, d <= 10'sd1};
end
endmodule
