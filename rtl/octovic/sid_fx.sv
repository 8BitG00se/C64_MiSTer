// OCTOSID FX - what SID 1 plays, spread over SIDs 2, 3 and 4 (the Octophonic's extra SIDs):
//   chorus: every write to SID 1 is written to SID 2 too, its pitches a little sharp
//           (SID 1 is on the left, SID 2 on the right: a wide stereo sound)
//   echo:   every write to SID 1 again on SID 3 (left) DLY_L later and SID 4 (right) DLY_R
//           later, at half the volume - a stereo echo, for a big hall sound
// Any game, untouched. The extra writes go to the SIDs' own buses on clocks when the 6510
// is not using them, so nothing the 6510 does is held up or changed.
module sid_fx #(
	parameter AW    = 11,            // the echo's memory: 2^AW writes (2048)
	parameter DLY_L = 20'd140000,    // microseconds
	parameter DLY_R = 20'd200000
) (
	input             clk,
	input             reset,
	input             ce_1m,         // a microsecond
	input       [1:0] mode,          // b0 chorus, b1 echo
	input             cpu_wr,        // the 6510 writes an I/O register this clock
	input             sid1_wr,       //   ...and it is SID 1
	input       [4:0] addr,
	input       [7:0] data,
	input             busy1,         // the 6510 has SID pair 1 (SIDs 1, 2) selected
	input             busy2,         //   ... pair 2 (SIDs 3, 4)
	output reg        inj_we,        // a write to inject this clock:
	output reg  [1:0] inj_tgt,       //   1 SID 2, 2 SID 3, 3 SID 4
	output reg  [4:0] inj_addr,
	output reg  [7:0] inj_data
);

// --- time
reg [19:0] now;
always @(posedge clk) if (reset) now <= 0; else if (ce_1m) now <= now + 20'd1;

// --- SID 1's pitches, as written (for the detune)
reg [15:0] freq[3];
wire [1:0] vo = (addr < 5'd7) ? 2'd0 : (addr < 5'd14) ? 2'd1 : 2'd2;
wire [4:0] vb = (vo == 2'd0) ? 5'd0 : (vo == 2'd1) ? 5'd7 : 5'd14;
wire       is_freq = (addr < 5'd21) && (addr - vb < 5'd2);

// --- the chorus: up to two writes waiting for SID 2
reg        pa, pb;                   // pending: A (the write, or the pitch's low byte), B (its high byte)
reg  [4:0] pa_a, pb_a;
reg  [7:0] pa_d;
reg  [1:0] pv;                       // the voice whose pitch is waiting
wire [15:0] fq    = freq[pv];
wire [15:0] sharp = fq + {8'd0, fq[15:8]} + {9'd0, fq[15:9]};   // +0.6%: a gentle beat
reg        fq_wait;                  // (the pitch is computed a clock after the write)

// --- the echo: SID 1's writes, stamped with the time, in a ring
localparam DW = 33;
reg  [AW-1:0] wp, rl, rr;            // write, the left tap, the right tap
reg  [AW-1:0] ra;
wire [DW-1:0] rq;
wire          ring_we = !reset && sid1_wr && mode[1] && addr < 5'd25;
ovram #(.AW(AW), .DW(DW)) ring (.clk(clk), .we(ring_we), .wa(wp), .wd({now, addr, data}), .ra(ra), .q(rq));
// what each tap holds next (fetched from the ring)
reg  [DW-1:0] tl, tr;
reg           tl_v, tr_v;
reg     [1:0] fetch;                 // 0 idle, 1 fetching for L, 2 for R
reg           fetch2;                // (the read takes a clock)
wire   [19:0] age_l = now - tl[32:13];
wire   [19:0] age_r = now - tr[32:13];
wire          due_l = tl_v && age_l >= DLY_L;
wire          due_r = tr_v && age_r >= DLY_R;
function [7:0] half_vol(input [4:0] a, input [7:0] d);
	half_vol = (a == 5'h18) ? {d[7:4], 1'b0, d[3:1]} : d;
endfunction

always @(posedge clk) begin
	inj_we <= 0;
	if (reset) begin
		pa <= 0; pb <= 0; fq_wait <= 0; wp <= 0; rl <= 0; rr <= 0; tl_v <= 0; tr_v <= 0; fetch <= 0; fetch2 <= 0;
		freq[0] <= 0; freq[1] <= 0; freq[2] <= 0;
	end
	else begin
		// a write to SID 1: keep its pitch, queue the chorus copy, put it in the ring
		if (sid1_wr) begin
			if (is_freq) begin
				if (addr == vb) freq[vo][7:0] <= data; else freq[vo][15:8] <= data;
			end
			if (mode[0]) begin
				if (is_freq) begin pv <= vo; fq_wait <= 1; pa_a <= vb; pb_a <= vb + 5'd1; end
				else begin pa <= 1; pa_a <= addr; pa_d <= data; end
			end
			if (mode[1] && addr < 5'd25) begin
				wp <= wp + 1'd1;
				// full: the oldest goes (the right tap is always the furthest behind)
				if (wp + 1'd1 == rr) begin
					rr <= rr + 1'd1; tr_v <= 0;
					if (rl == rr) begin rl <= rl + 1'd1; tl_v <= 0; end
				end
			end
		end
		if (fq_wait) begin fq_wait <= 0; pa <= 1; pb <= 1; pa_d <= sharp[7:0]; end

		// the taps: fetch the next write for one that is empty (a fetch under way when the ring
		// drops its oldest write is abandoned - what it fetches may be gone)
		if (sid1_wr && mode[1] && wp + 1'd1 == rr && fetch != 0) begin fetch <= 0; fetch2 <= 0; end
		else if (fetch2) begin
			fetch2 <= 0;
			if (fetch == 2'd1) begin tl <= rq; tl_v <= 1; end else begin tr <= rq; tr_v <= 1; end
			fetch <= 0;
		end
		else if (fetch != 0) fetch2 <= 1;
		else if (!tl_v && rl != wp && !(sid1_wr && mode[1])) begin ra <= rl; fetch <= 2'd1; end
		else if (!tr_v && rr != wp && !(sid1_wr && mode[1])) begin ra <= rr; fetch <= 2'd2; end

		// one write out, on a clock the 6510 is not writing (and not using that pair)
		if (!cpu_wr && !sid1_wr && !fq_wait) begin
			if (pa && !busy1) begin
				inj_we <= 1; inj_tgt <= 2'd1; inj_addr <= pa_a; inj_data <= pa_d; pa <= 0;
				if (pb) pa_d <= sharp[15:8];               // (B goes next, through A)
				if (pb) begin pa <= 1; pa_a <= pb_a; pb <= 0; end
			end
			else if (due_l && !busy2 && fetch != 2'd1) begin
				inj_we <= 1; inj_tgt <= 2'd2; inj_addr <= tl[12:8]; inj_data <= half_vol(tl[12:8], tl[7:0]);
				tl_v <= 0; rl <= rl + 1'd1;
			end
			else if (due_r && !busy2 && fetch != 2'd2) begin
				inj_we <= 1; inj_tgt <= 2'd3; inj_addr <= tr[12:8]; inj_data <= half_vol(tr[12:8], tr[7:0]);
				tr_v <= 0; rr <= rr + 1'd1;
			end
		end
		if (mode[1] == 0) begin rl <= wp; rr <= wp; tl_v <= 0; tr_v <= 0; end
		if (mode[0] == 0) begin pa <= 0; pb <= 0; end
	end
end
endmodule
