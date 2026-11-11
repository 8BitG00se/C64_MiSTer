// =====================================================================================
//  OCTOSCOPE (OctoVIC version 5, Fix 55) - a real oscilloscope of every SID voice.
//  (c) 2026 Mong00se. See docs/OCTOVIC.md, OCTOSCOPE.
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
//  A complete capture is kept until the next; at the start of each frame (the renderer's raster line 0)
//  the newest complete capture of every channel becomes the one shown for that whole frame (no tearing).
//
//  How it is built: one channel a clock (32 clocks = a microsecond = 32 channels), pipelined; three
//  slots of 304 samples a channel in block RAM (the one being captured, the newest complete one, the one
//  shown) - nothing is ever copied, only the slot numbers change. Two places where the emulator writes
//  many samples at once (the jump into cycle 2 after a sync / test-bit wrap, and the fill at the end)
//  are not written at all: the slot keeps them as a rule (a "hole" [hs..152] = hv, and "from fn on" = fv)
//  that the reader applies, so every capture costs at most one RAM write a microsecond.
// =====================================================================================
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
	output reg        latch_pending,
	output reg        latch_now,      // (a pulse: the latch happened)
	output reg        tick_done,      // (a pulse: every channel of a microsecond has been stored - for the checks)

	// the renderer: a channel's shown slot (its base word, its rules), then its words
	input       [4:0] r_ch,
	output reg [12:0] r_base,         // valid 2 clocks after r_ch
	output reg [33:0] r_desc,         // {hole on, hole start, hole value, fill from, fill value}
	output reg        r_zero,         // nothing captured since reset: all 0
	input      [12:0] r_addr,
	output reg [31:0] r_q             // 4 samples (sample 4w + k in byte k), a clock after r_addr
);

localparam SCN = 304, WPS = 76;       // samples, words a slot

// ---------------------------------------------------------------------------------
//  the memories
// ---------------------------------------------------------------------------------
// samples: 96 slots (channel x 3 + slot) of 76 words of 4 bytes; one byte written at a time
reg [3:0][7:0] smem[0:96*WPS-1];
reg        sm_we;
reg [12:0] sm_wa;
reg  [1:0] sm_lane;
reg  [7:0] sm_wd;
always @(posedge clk) begin
	if (sm_we) smem[sm_wa][sm_lane] <= sm_wd;
	r_q <= smem[r_addr];
end

// each slot's rules: {hole on, hole start (8), hole value (8), fill from (9), fill value (8)}
(* ramstyle = "MLAB, no_rw_check" *) reg [33:0] dmem[0:95];
reg        dm_we;
reg  [6:0] dm_wa;
reg [33:0] dm_wd;
reg  [6:0] dm_ra;
always @(posedge clk) begin
	if (dm_we) dmem[dm_wa] <= dm_wd;
	r_desc <= dmem[dm_ra];
end

// each channel's capture: {n (9), cycle (1), on (1), age (16), tick (7), hole on (1), hole start (8), hole value (8)}
(* ramstyle = "MLAB, no_rw_check" *) reg [50:0] cmem[0:31];
reg        cm_we;
reg  [4:0] cm_wa, cm_ra;
reg [50:0] cm_wd, cm_q;
always @(posedge clk) begin
	if (cm_we) cmem[cm_wa] <= cm_wd;
	cm_q <= cmem[cm_ra];
end

// the slots: being captured, newest complete, shown; and "nothing yet" (since reset: all 0, as the emulator starts)
reg  [1:0] cap[32], done[32], disp[32];
reg [31:0] done_z, disp_z;

function [12:0] slot_base(input [4:0] ch, input [1:0] sl);
	reg [6:0] s;
	begin
		s = {ch, 1'b0} + {2'd0, ch} + {5'd0, sl};          // ch x 3 + slot
		slot_base = {s, 6'd0} + {3'd0, s, 3'd0} + {4'd0, s, 2'd0};   // x 76
	end
endfunction

// the renderer's side: the shown slot of r_ch
reg [4:0] r_ch1;
always @(posedge clk) begin
	r_ch1  <= r_ch;
	dm_ra  <= {r_ch, 1'b0} + {2'd0, r_ch} + {5'd0, disp[r_ch]};
	r_base <= slot_base(r_ch1, disp[r_ch1]);
	r_zero <= disp_z[r_ch1];
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
reg        isvA;            // a voice (else a whole output)
reg  [1:0] pair1;
reg  [2:0] side1;
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
reg        wrapB, lockB;
reg  [7:0] xB;
reg [50:0] stB;
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
	wrapB <= isvA & recA[37];
	lockB <= isvA & recA[38];
	xm  = {8'd0, recA[36:21]} * 24'd152;
	xB  <= xm[23:16];
	stB <= fresh ? 51'd0 : cm_q;
	if (reset) fresh <= 1;
	else if (vA && chA == 5'd31) fresh <= 0;
end

// stage B: sc_store
always @(posedge clk) begin
	sm_we <= 0; dm_we <= 0; cm_we <= 0; latch_now <= 0; tick_done <= 0;
	if (latch_req) latch_pending <= 1;
	if (reset) begin
		latch_pending <= 0;
		for (int c = 0; c < 32; c = c + 1) begin cap[c] <= 2'd0; done[c] <= 2'd1; disp[c] <= 2'd1; end
		done_z <= '1; disp_z <= '1;
	end
	else begin
		// nothing running (the machine paused): a latch need not wait for a microsecond's end
		if (latch_pending && !vB && !vA && !v1 && ks[5] && !ce_1m) begin
			for (int c = 0; c < 32; c = c + 1) disp[c] <= done[c];
			disp_z <= done_z; latch_pending <= 0; latch_now <= 1;
		end
		if (vB) begin
			reg  [8:0] n;  reg cyc, on;  reg [15:0] age;  reg [6:0] tick;  reg hok;  reg [7:0] hs, hv;
			reg        comp, timed, wr, ret;
			reg  [8:0] t, wi;
			reg  [1:0] cp, ncap, wslot;
			reg [33:0] dsc;
			{n, cyc, on, age, tick, hok, hs, hv} = stB;
			comp = 0; timed = 0; wr = 0; ret = 0; wi = 0; dsc = 0;
			cp   = cap[chB];
			ncap = 2'd3 - cp - disp[chB];          // the slot that is neither the new complete one nor the shown one
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
			if (!ret) begin                        // by time: a sample every 66 us
				if (on) begin on = 0; n = 0; end
				tick = tick + 7'd1;
				if (tick >= 7'd66) begin
					tick = 0; wr = 1; wi = n; n = n + 9'd1;
					if (n >= 9'(SCN)) begin comp = 1; timed = 1; n = 0; dsc = {1'b0, 8'd0, 8'd0, 9'(SCN), 8'd0}; end
				end
			end
			// the writes: a locked capture's sample after its completion goes into the new slot; a timed
			// capture's last sample is in the slot that just completed
			wslot = (comp && !timed) ? ncap : cp;
			sm_we <= wr; sm_wa <= slot_base(chB, wslot) + {6'd0, wi[8:2]}; sm_lane <= wi[1:0]; sm_wd <= sB;
			dm_we <= comp; dm_wa <= {chB, 1'b0} + {2'd0, chB} + {5'd0, cp}; dm_wd <= dsc;
			cm_we <= 1; cm_wa <= chB; cm_wd <= {n, cyc, on, age, tick, hok, hs, hv};
			if (comp) begin cap[chB] <= ncap; done[chB] <= cp; done_z[chB] <= 1'b0; end
			if (chB == 5'd31) begin
				tick_done <= 1;
				// the frame's latch: at the end of a whole microsecond (channel 31's own news included)
				if (latch_pending || latch_req) begin
					for (int c = 0; c < 31; c = c + 1) disp[c] <= done[c];
					disp[31] <= comp ? cp : done[31];
					disp_z <= {comp ? 1'b0 : done_z[31], done_z[30:0]};
					latch_pending <= 0; latch_now <= 1;
				end
			end
		end
	end
end

endmodule
