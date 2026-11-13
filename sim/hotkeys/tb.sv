// Fix 74 test: rtl/hotkeys.sv in the keyboard stream            (c) 2026 Mong00se
// Small HOLD/STEP/GAP so the test is quick; the logic is the same as the real one.
`timescale 1ns/1ps
module tb;
	reg clk = 0;
	always #5 clk = ~clk;
	reg  [10:0] ps2 = 0;
	wire [10:0] out;
	wire kernal, brk, wipe, spare;
	hotkeys #(.HOLD(26'd200), .STEP(21'd60), .GAP(8'd4)) dut
		(.clk(clk), .ps2_key(ps2), .key_out(out), .kernal(kernal), .brk(brk), .wipe(wipe), .spare(spare));

	// what the C64 side sees: every toggle of out[10], as a list
	integer n_out = 0;
	reg [9:0]  o_code [0:63];
	integer    o_time [0:63];
	reg [10:0] last_out = 0;
	integer    cyc = 0;
	integer n_kernal = 0, n_brk = 0, n_wipe = 0, n_spare = 0;
	always @(posedge clk) begin
		cyc <= cyc + 1;
		if (out[10] != last_out[10]) begin o_code[n_out] <= out[9:0]; o_time[n_out] <= cyc; n_out <= n_out + 1; end
		last_out <= out;
		if (kernal) n_kernal <= n_kernal + 1;
		if (brk)    n_brk    <= n_brk + 1;
		if (wipe)   n_wipe   <= n_wipe + 1;
		if (spare)  n_spare  <= n_spare + 1;
	end

	task ev(input down, input ext, input [7:0] code);   // one keyboard event
		begin
			@(posedge clk);
			ps2 = {~ps2[10], down, ext, code};
			repeat (3) @(posedge clk);
		end
	endtask
	task wait_c(input integer c); begin repeat (c) @(posedge clk); end endtask

	integer fails = 0;
	task check(input cond, input string what);
		begin if (!cond) begin fails = fails + 1; $display("FAIL: %s", what); end else $display("ok:   %s", what); end
	endtask
	task reset_counts; begin n_out = 0; n_kernal = 0; n_brk = 0; n_wipe = 0; n_spare = 0; end endtask

	localparam SHL = 8'h12, F1 = 8'h05, F2 = 8'h06, F3 = 8'h04, F4 = 8'h0C, KA = 8'h1C;

	integer i, t0, t1;
	initial begin
		wait_c(10);

		// 1. A plain F1 (no SHIFT) goes straight through, press then release
		reset_counts;
		ev(1,0,F1); wait_c(30); ev(0,0,F1); wait_c(30);
		check(n_out == 2 && o_code[0] == {2'b10,F1} && o_code[1] == {2'b00,F1}, "F1 without SHIFT passes unchanged");

		// 2. SHIFT + a tapped F1: SHIFT passes, F1 is replayed as press (held STEP) then release; no hot key
		reset_counts;
		ev(1,0,SHL); wait_c(20);
		ev(1,0,F1);  wait_c(40);  ev(0,0,F1);  wait_c(200);
		ev(0,0,SHL); wait_c(30);
		check(n_kernal == 0, "tap: no hot key");
		check(n_out == 4, "tap: four events reach the C64 (SHIFT, F1 down, F1 up, SHIFT up)");
		check(o_code[0] == {2'b10,SHL} && o_code[1] == {2'b10,F1} && o_code[2] == {2'b00,F1} && o_code[3] == {2'b00,SHL}, "tap: order SHIFT dn, F1 dn, F1 up, SHIFT up");
		check(o_time[2] - o_time[1] >= 60, "tap: the replayed press stays down at least STEP");

		// 3. SHIFT + F1 held past HOLD: hot key fires once, the C64 sees only SHIFT, not F1 (press, repeats, release)
		reset_counts;
		ev(1,0,SHL); wait_c(20);
		ev(1,0,F1);  wait_c(100); ev(1,0,F1); wait_c(150); ev(1,0,F1); wait_c(100);  // repeats
		ev(0,0,F1);  wait_c(30);
		ev(0,0,SHL); wait_c(30);
		check(n_kernal == 1 && n_brk == 0 && n_wipe == 0 && n_spare == 0, "hold F1: KERNAL hot key fires exactly once");
		check(n_out == 2 && o_code[0] == {2'b10,SHL} && o_code[1] == {2'b00,SHL}, "hold F1: the C64 saw SHIFT only, F1 never reached it");

		// 4. Same for F2, F3, F4: each fires its own pulse, nothing leaks
		for (i = 0; i < 3; i = i + 1) begin
			reset_counts;
			ev(1,0,SHL); wait_c(10);
			ev(1,0, (i==0)?F2:(i==1)?F3:F4); wait_c(260);
			ev(0,0, (i==0)?F2:(i==1)?F3:F4); wait_c(20);
			ev(0,0,SHL); wait_c(20);
			check(n_out == 2, "hold F2/F3/F4: nothing but SHIFT reaches the C64");
			check((i==0 && n_brk==1 && n_kernal==0 && n_wipe==0 && n_spare==0) ||
			      (i==1 && n_spare==1 && n_kernal==0 && n_brk==0 && n_wipe==0) ||
			      (i==2 && n_wipe==1 && n_kernal==0 && n_brk==0 && n_spare==0), "hold F2/F3/F4: its own pulse only");
		end

		// 5. SHIFT let go before the held-back F1 is let go: F1 is dropped, never sent unshifted
		reset_counts;
		ev(1,0,SHL); wait_c(10);
		ev(1,0,F1);  wait_c(20);
		ev(0,0,SHL); wait_c(20);
		ev(0,0,F1);  wait_c(100);
		check(n_out == 2 && o_code[0] == {2'b10,SHL} && o_code[1] == {2'b00,SHL}, "SHIFT first: the F key is dropped, not sent unshifted");
		check(n_kernal == 0, "SHIFT first: no hot key");

		// 6. Other keys pass in order, also while an F key is held back, and hold fires afterwards
		reset_counts;
		ev(1,0,SHL); wait_c(10);
		ev(1,0,F1);  wait_c(20);
		ev(1,0,KA);  wait_c(20);  ev(0,0,KA); wait_c(20);
		wait_c(300);
		ev(0,0,F1);  wait_c(20);  ev(0,0,SHL); wait_c(20);
		check(n_out == 4 && o_code[1] == {2'b10,KA} && o_code[2] == {2'b00,KA}, "other keys pass in order while F1 is held back");
		check(n_kernal == 1, "other keys: the hot key still fires");

		// 7. After a hot key, a following tap works normally again (state cleared)
		reset_counts;
		ev(1,0,SHL); wait_c(10); ev(1,0,F1); wait_c(30); ev(0,0,F1); wait_c(150); ev(0,0,SHL); wait_c(20);
		check(n_kernal == 0 && n_out == 4, "after a hot key: a tap works again");

		// 8. Extended keys with the same code as an F key are not touched
		reset_counts;
		ev(1,0,SHL); wait_c(10); ev(1,1,F1); wait_c(300); ev(0,1,F1); wait_c(20); ev(0,0,SHL); wait_c(20);
		check(n_kernal == 0 && n_out == 4 && o_code[1] == {2'b11,F1}, "extended 05 is not an F key");

		// 9. Right SHIFT works like left SHIFT
		reset_counts;
		ev(1,0,8'h59); wait_c(10); ev(1,0,F4); wait_c(260); ev(0,0,F4); wait_c(10); ev(0,0,8'h59); wait_c(20);
		check(n_wipe == 1 && n_out == 2, "right SHIFT+F4 works");

		// 10. A fast typist: two taps close together both arrive, in order, and nothing is lost
		reset_counts;
		ev(1,0,SHL); wait_c(10);
		ev(1,0,F1); wait_c(10); ev(0,0,F1); wait_c(5);
		ev(1,0,F3); wait_c(10); ev(0,0,F3); wait_c(400);
		ev(0,0,SHL); wait_c(20);
		check(n_out == 6 && o_code[1] == {2'b10,F1} && o_code[2] == {2'b00,F1} && o_code[3] == {2'b10,F3} && o_code[4] == {2'b00,F3}, "two quick taps both arrive, in order");

		$display("%0d failure(s)", fails);
		if (fails == 0) $display("HOTKEYS_SIM_OK"); else $display("HOTKEYS_SIM_FAILED");
		$finish;
	end
endmodule
