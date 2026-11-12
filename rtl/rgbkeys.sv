// Octophonic64RGB - the remaster keys (Build 12)                (c) 2026 Mong00se
//
// Hold the Windows key and press a function key:
//   WIN+F1  back to the Octophonic core (its start screen)
//   WIN+F2  held: REWIND - the game runs backwards until F2 is let go (Build 13, rtl/rewind.sv)
//           (the Menu key, between right ALT and right CTRL on a PC keyboard, held does the same -
//           the C64 has no use for that key)
//   WIN+F3  the next palette of the pack (1, 2, ... the last, Off, 1 ...)
//   WIN+F5  the next colour grading            (Octophonic Main remakes the pack and sends it)
//   WIN+F7  the gradient strength: next step   (Octophonic Main remakes the pack and sends it)
//   WIN+F8  save the pack beside the game      (Octophonic Main)
//
// No leak: while a Windows key is held, F1-F8 never reach the C64 - press AND release are both held
// back (a release only if its press was), so the game never sees them. The old SHIFT+F3 palette key
// reached the game as F4; SHIFT+F1-F4 keep their Octophonic meaning (rtl/hotkeys.sv) and are not
// used here. The Windows keys themselves only set the core's tape modifier, which nothing else uses.
module rgbkeys
(
	input             clk,
	input      [10:0] ps2_key,     // hps_io: [10] strobe, [9] pressed, [8] extended, [7:0] code
	output reg [10:0] key_out = 0, // the same keys minus the held-back ones, for the C64's keyboard
	output reg        home = 0,    // one-clock pulses
	output reg        pal = 0,
	output reg        grade = 0,
	output reg        grad = 0,
	output reg        save = 0,
	output            rew          // a level: WIN+F2 is held
);

reg       old_stb = 0;
reg       win_l = 0, win_r = 0;
reg [7:0] held = 0;            // F1-F8 whose press was held back (their release is held back too)
reg       menu = 0;            // the Menu key is down
assign    rew = held[1] | menu;

function [3:0] fkey(input [7:0] c);    // 1-8 for F1-F8, 0 for any other key
	case (c)
		8'h05: fkey = 4'd1; 8'h06: fkey = 4'd2; 8'h04: fkey = 4'd3; 8'h0C: fkey = 4'd4;
		8'h03: fkey = 4'd5; 8'h0B: fkey = 4'd6; 8'h83: fkey = 4'd7; 8'h0A: fkey = 4'd8;
		default: fkey = 4'd0;
	endcase
endfunction

wire       ext  = ps2_key[8];
wire       down = ps2_key[9];
wire [3:0] f    = ext ? 4'd0 : fkey(ps2_key[7:0]);
wire [2:0] fi   = f[2:0] - 3'd1;

always @(posedge clk) begin
	reg pass;
	{home, pal, grade, grad, save} <= 0;
	old_stb <= ps2_key[10];
	if (old_stb != ps2_key[10]) begin
		pass = 1;
		if (ext && ps2_key[7:0] == 8'h1F) win_l <= down;
		if (ext && ps2_key[7:0] == 8'h27) win_r <= down;
		if (ext && ps2_key[7:0] == 8'h2F) begin menu <= down; pass = 0; end
		if (f != 0) begin
			if (down && (win_l | win_r | held[fi])) begin   // (held: the keyboard's repeats after WIN is let go)
				pass = 0;
				if (!held[fi]) begin                 // the first press only, not the keyboard's repeats
					held[fi] <= 1;
					case (f)
						4'd1: home  <= 1;
						4'd3: pal   <= 1;
						4'd5: grade <= 1;
						4'd7: grad  <= 1;
						4'd8: save  <= 1;
						default: ;
					endcase
				end
			end
			else if (!down && held[fi]) begin
				pass = 0;
				held[fi] <= 0;
			end
		end
		if (pass) key_out <= {~key_out[10], ps2_key[9:0]};
	end
end

endmodule
