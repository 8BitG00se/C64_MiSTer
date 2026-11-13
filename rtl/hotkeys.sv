// Octophonic 64 - hot keys (Fix 58, Fix 74)                 (c) 2026 Mong00se
// From anything running, hold SHIFT and a function key on the keyboard for
// about a second:
//   SHIFT+F1  back to the KERNAL start screen (the OSD's Reset)
//   SHIFT+F2  RUN/STOP+RESTORE (break out, the program stays in memory)
//   SHIFT+F3  (spare)
//   SHIFT+F4  wipe and restart (memory cleared, as at power-on)
//
// Fix 74 - the hot key never reaches the game. This module sits in the keyboard stream on its way
// to the C64 (key_out). While SHIFT is down, an F1-F4 press is held back:
//   * held for HOLD: the hot key acts, and neither that press, its keyboard repeats nor its release
//     are ever sent on - the game sees nothing of it;
//   * let go before that (a tap - SHIFT+F1 is how a PC keyboard types the C64's F2): the press is
//     sent on at once as a short real key press (STEP long), so a tap does what it always did,
//     only a moment later;
//   * SHIFT let go first: the held-back key is dropped (never a wrong, unshifted F key).
// Every other key passes straight through (one clock later), in order. Events are queued, one
// every GAP clocks (STEP after a replayed press, so the C64 scan sees it).
module hotkeys #(parameter HOLD = 26'd24_000_000,   // ~0.75 s at clk_sys
                 parameter STEP = 21'd1_280_000,    // ~40 ms: a replayed tap stays down this long
                 parameter GAP  = 8'd16)            // clocks between two sent events
(
	input             clk,
	input      [10:0] ps2_key,     // the keyboard stream: [10] strobe (toggles), [9] pressed, [8] extended, [7:0] code
	output reg [10:0] key_out = 0, // the same stream for the C64, minus the hot keys
	output reg        kernal,      // a one-clock pulse each
	output reg        brk,
	output reg        wipe,
	output reg        spare
);

function [2:0] fidx(input [7:0] c);       // 1-4 for F1-F4 (PS/2 set 2: 05 06 04 0C), else 0
	case (c)
		8'h05: fidx = 3'd1; 8'h06: fidx = 3'd2; 8'h04: fidx = 3'd3; 8'h0C: fidx = 3'd4;
		default: fidx = 3'd0;
	endcase
endfunction

reg        shl = 0, shr = 0;
reg        old_stb = 0;
reg  [2:0] pend = 0;                       // the held-back F key (1-4), 0 = none
reg [25:0] cnt = 0;
reg  [2:0] swal = 0;                       // a fired F key whose repeats and release are being dropped

reg [10:0] q [0:15];                       // the out queue: [10] = a replayed press (stays down STEP)
reg  [3:0] qr = 0, qw = 0;
reg  [4:0] qn = 0;
reg [20:0] wcnt = 0;

always @(posedge clk) begin
	reg  [3:0] w;
	reg  [4:0] n;
	reg  [2:0] k;
	reg        isev;
	reg  [9:0] e;
	w = qw;
	n = qn;
	{kernal, brk, wipe, spare} <= 0;

	old_stb <= ps2_key[10];
	isev = (old_stb != ps2_key[10]);
	e    = ps2_key[9:0];
	k    = e[8] ? 3'd0 : fidx(e[7:0]);

	if (isev) begin
		if (!e[8] && e[7:0] == 8'h12) shl <= e[9];
		if (!e[8] && e[7:0] == 8'h59) shr <= e[9];

		if (k != 0) begin
			if (e[9]) begin                                   // an F1-F4 press
				if (k == pend || k == swal) begin end         // its keyboard repeat: dropped
				else if ((shl | shr) && pend == 0 && swal == 0) begin
					pend <= k;                                // hold it back
					cnt  <= 0;
				end
				else if (n < 5'd16) begin q[w] <= {1'b0, e}; w = w + 1'd1; n = n + 1'd1; end
			end
			else begin                                        // an F1-F4 release
				if (k == pend) begin                          // a tap: send it on as a short press
					pend <= 0;
					if (n < 5'd15) begin
						q[w] <= {1'b1, 1'b1, e[8:0]}; w = w + 1'd1;      // press, held STEP
						q[w] <= {1'b0, e};            w = w + 1'd1;      // then the release
						n = n + 2'd2;
					end
				end
				else if (k == swal) swal <= 0;                // the fired key's release: dropped
				else if (n < 5'd16) begin q[w] <= {1'b0, e}; w = w + 1'd1; n = n + 1'd1; end
			end
		end
		else begin
			if (pend != 0 && !e[8] && !e[9] && (e[7:0] == 8'h12 || e[7:0] == 8'h59)) begin
				// SHIFT let go while an F key is held back: drop the F key, never send it unshifted
				if (!((e[7:0] == 8'h12 ? shr : shl))) begin swal <= pend; pend <= 0; end   // (its release and repeats are dropped too)
			end
			if (n < 5'd16) begin q[w] <= {1'b0, e}; w = w + 1'd1; n = n + 1'd1; end
		end
	end

	// the held-back key: held long enough = the hot key
	if (pend != 0) begin
		if (cnt == HOLD) begin
			swal   <= pend;
			pend   <= 0;
			kernal <= (pend == 3'd1);
			brk    <= (pend == 3'd2);
			spare  <= (pend == 3'd3);
			wipe   <= (pend == 3'd4);
		end
		else cnt <= cnt + 1'd1;
	end

	// the queue out, one event at a time
	if (wcnt != 0) wcnt <= wcnt - 1'd1;
	else if (qn != 0) begin          // (qn: what was queued before this clock - a queue entry is readable the clock after it is written)
		key_out <= {~key_out[10], q[qr][9:0]};
		wcnt    <= q[qr][10] ? STEP : {13'd0, GAP};
		qr      <= qr + 1'd1;
		n        = n - 1'd1;
	end
	qw <= w;
	qn <= n;
end

endmodule

// RUN/STOP+RESTORE as keyboard events into the C64's key stream: RUN/STOP
// down, RESTORE (F11) down, both up, ~40 ms apart (the KERNAL's IRQ sees
// RUN/STOP before the NMI checks it).
module hotkey_break #(parameter STEP = 21'd1_280_000)
(
	input            clk,
	input            start,
	output reg       busy = 0,
	output reg       stb = 0,      // a pulse: send code
	output reg [9:0] code = 0      // [9] pressed, [8] extended, [7:0]
);

reg [2:0]  st = 0;
reg [20:0] t = 0;

always @(posedge clk) begin
	stb <= 0;
	if (start && !busy) begin
		busy <= 1;
		st   <= 0;
		t    <= 0;
	end
	else if (busy) begin
		t <= t + 1'd1;
		if (t == STEP) begin
			t   <= 0;
			st  <= st + 1'd1;
			stb <= 1;
			case (st)
				0: code <= 10'h276;   // RUN/STOP down
				1: code <= 10'h278;   // RESTORE down
				2: code <= 10'h078;   // RESTORE up
				3: code <= 10'h076;   // RUN/STOP up
				default: begin code <= 10'h000; busy <= 0; end
			endcase
		end
	end
end

endmodule
