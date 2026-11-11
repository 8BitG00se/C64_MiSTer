// Octophonic 64 - hot keys (Fix 58)                         (c) 2026 Mong00se
// From anything running, hold SHIFT and a function key on the keyboard for
// about a second:
//   SHIFT+F1  back to the KERNAL start screen (the OSD's Reset)
//   SHIFT+F2  RUN/STOP+RESTORE (break out, the program stays in memory)
//   SHIFT+F3  (spare)
//   SHIFT+F4  wipe and restart (memory cleared, as at power-on)
// The keys still reach the C64 as normal while held (SHIFT+F1 is F2 on a real
// C64 keyboard), so a quick press does what it always did; only a held one
// acts, and only once until the keys are let go.
module hotkeys #(parameter HOLD = 26'd24_000_000)   // ~0.75 s at clk_sys
(
	input             clk,
	input      [10:0] ps2_key,     // hps_io: [10] strobe, [9] pressed, [8] extended, [7:0] code
	output reg        kernal,      // a one-clock pulse each
	output reg        brk,
	output reg        wipe,
	output reg        spare
);

reg shl = 0, shr = 0, f1 = 0, f2 = 0, f3 = 0, f4 = 0;
reg old_stb = 0, fired = 0;
reg [25:0] cnt = 0;

always @(posedge clk) begin
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10] && !ps2_key[8]) begin
		case (ps2_key[7:0])
			8'h12: shl <= ps2_key[9];
			8'h59: shr <= ps2_key[9];
			8'h05: f1  <= ps2_key[9];
			8'h06: f2  <= ps2_key[9];
			8'h04: f3  <= ps2_key[9];
			8'h0C: f4  <= ps2_key[9];
			default: ;
		endcase
	end

	{kernal, brk, wipe, spare} <= 0;
	if ((shl | shr) & (f1 | f2 | f3 | f4)) begin
		if (!fired) begin
			if (cnt == HOLD) begin
				fired  <= 1;
				kernal <= f1;
				brk    <= f2 & ~f1;
				spare  <= f3 & ~f1 & ~f2;
				wipe   <= f4 & ~f1 & ~f2 & ~f3;
			end
			else cnt <= cnt + 1'd1;
		end
	end
	else begin
		cnt   <= 0;
		fired <= 0;
	end
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
