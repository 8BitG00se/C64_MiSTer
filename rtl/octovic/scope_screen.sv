// (c) 2026 Mong00se
// Octophonic 64 - THE SCOPE SCREEN (Fix 72, Fix 82): the OCTOSCOPE drawn by the core itself, over any program.
//
// All 24 SID voices live, drawn by the hardware with nothing asked of the program that is running (no layer,
// no copper, no register of its): a hot key turns it on over whatever plays (Fix 72), or sends it to the
// second screen as a picture of its own (Fix 82). OctoVIC puts it out (octovic.sv, SCOPEKEY $D6CF;
// docs/OCTOVIC.md).
//
//   8 rows, one a SID (its own colour); 3 traces a row, its voices 1-3; each trace 120 pixels wide and
//   +-16 lines tall (PAL; +-14 on a 60 Hz picture), a dim line through its middle:
//
//       raster X   6..125    132..251   258..377            (the C64's screen is raster X 32..351)
//       PAL        row k = raster lines 19 + 33k .. 51 + 33k
//       60 Hz      row k = raster lines 28 + 29k .. 56 + 29k
//
//   Pixel x of a trace shows sample i = 5x / 2 of the voice's shown capture (across its 304 samples: the
//   two whole cycles OCTOSCOPE holds still), at y = -(sample >> 3) (60 Hz: less an eighth). It is lit where
//   the line lies between the y of this pixel's sample and the y of the pixel before - an unbroken trace.
//
// How: the captures are in the DDR3 (octoscope.sv). A row's three captures are fetched into a small memory
// (2 x 3 x 304 samples of 5 bits: one M10K) while the row above it is on the beam - the first row's at the
// frame's latch - one 64-bit read at a time through OctoVIC's port, behind everything else that wants it;
// the slot's rules (octoscope.sv: the hole, the fill) are applied as the samples go in. The picture is then
// made as the beam goes: one memory read a pixel, no line buffer. A row is drawn only from a memory that
// holds that row, whole (else just its middle lines), so a half-fetched capture is never shown.
module scope_screen
(
	input             clk,
	input             reset,
	input             on,          // the scope screen is being shown (fetch the captures)
	input             ntsc,        // a 60 Hz picture (263 lines): the smaller rows

	// the VIC's beam, as OctoVIC has it
	input             pix_en,
	input       [9:0] vic_x,
	input       [8:0] vic_y,
	output reg [23:0] rgb,         // the pixel, a clock after its strobe (in step with OctoVIC's own)
	output reg        lit,         //   ... it is a trace's (rgb its colour), it is inside a trace's box
	output reg        box,

	// OCTOSCOPE: the frame's latch, the shown captures may be read, a look-up (answers 2 clocks after q_ch)
	input             latched,
	input             r_ok,
	output reg  [4:0] q_ch,
	input      [11:0] q_word,
	input      [33:0] q_desc,
	input             q_zero,

	// a read of the DDR3 through OctoVIC's port: asked until taken (rack), its answer a pulse with the word
	output reg        rreq,
	output reg [11:0] raddr,
	input             rack,
	input             ans,
	input      [63:0] ans_d
);

// the memory: {half, trace (x 304), sample}
reg         m_we;
reg  [10:0] m_wa;
reg   [4:0] m_wd;
wire [10:0] m_ra;
wire  [4:0] m_q;
ovram #(.AW(11), .DW(5)) mem (.clk(clk), .we(m_we), .wa(m_wa), .wd(m_wd), .ra(m_ra), .q(m_q));

// what each half holds: a row, whole
reg         h_ok[2];
reg   [2:0] h_row[2];

// ---------------------------------------------------------------------------------
//  the fetch: a row's three captures, 38 words each
// ---------------------------------------------------------------------------------
localparam F_IDLE = 0, F_OK = 1, F_LOOK = 2, F_REQ = 3, F_ACK = 4, F_ANS = 5, F_PUT = 6;
reg   [2:0] fs;
reg         p0;                 // wanted: row 0 (the frame's latch)
reg         pn;                 // wanted: row pn_row (the row above it has started)
reg   [2:0] pn_row;
reg   [2:0] f_row;
reg   [1:0] f_c;                // the trace
reg   [5:0] f_w;                // the word
reg   [2:0] f_b;                // the byte
reg   [1:0] f_n;
reg  [11:0] f_base;
reg  [33:0] f_desc;
reg         f_zero;
reg  [63:0] f_d;
wire        f_h = f_row[0];     // rows take the halves in turn
wire  [8:0] f_i = {f_w, f_b};
// the sample, the slot's rules applied (as octoscope_px)
wire signed [7:0] f_s = f_zero ? 8'sd0
                      : (f_i >= f_desc[16:8]) ? f_desc[7:0]
                      : (f_desc[33] && f_i >= {1'b0, f_desc[32:25]} && f_i <= 9'd152) ? f_desc[24:17]
                      : f_d[7:0];
reg         row_new;            // from the beam: a row starts
reg   [2:0] row_new_k;

always @(posedge clk) begin
	m_we <= 0;
	if (reset) begin
		fs <= F_IDLE; p0 <= 0; pn <= 0; rreq <= 0; h_ok[0] <= 0; h_ok[1] <= 0; h_row[0] <= 0; h_row[1] <= 0;
		q_ch <= 0; raddr <= 0;
	end
	else begin
		if (!on) begin p0 <= 0; pn <= 0; h_ok[0] <= 0; h_ok[1] <= 0; end
		else begin
			if (latched) p0 <= 1;
			if (row_new && row_new_k != 3'd7) begin pn <= 1; pn_row <= row_new_k + 3'd1; end
		end
		case (fs)
			F_IDLE: if (on && (p0 || pn)) begin
				if (p0) begin f_row <= 0; p0 <= 0; end
				else    begin f_row <= pn_row; pn <= 0; end
				f_c <= 0;
				fs  <= F_OK;
			end
			F_OK: if (r_ok) begin                    // (the latch applied, its words in the DDR3)
				h_ok[f_h] <= 0;
				q_ch <= {f_row, 1'b0} + {2'd0, f_row} + {3'd0, f_c};     // SID x 3 + voice
				f_n  <= 2'd3;
				fs   <= F_LOOK;
			end
			F_LOOK: if (f_n != 0) f_n <= f_n - 2'd1;
			        else begin f_base <= q_word; f_desc <= q_desc; f_zero <= q_zero; f_w <= 0; fs <= F_REQ; end
			F_REQ: begin rreq <= 1; raddr <= f_base + {6'd0, f_w}; fs <= F_ACK; end
			F_ACK: if (rack) begin rreq <= 0; fs <= F_ANS; end
			F_ANS: if (ans) begin f_d <= ans_d; f_b <= 0; fs <= F_PUT; end
			F_PUT: begin
				// (words 0-37 are samples 0-303 exactly: 38 x 8 = 304)
				m_we <= 1;
				m_wa <= {f_h, (f_c == 2'd0 ? 10'd0 : f_c == 2'd1 ? 10'd304 : 10'd608) + {1'b0, f_i}};
				m_wd <= f_s[7:3];
				f_d  <= {8'd0, f_d[63:8]};
				f_b  <= f_b + 3'd1;
				if (f_b == 3'd7) begin
					if (f_w != 6'd37) begin f_w <= f_w + 6'd1; fs <= F_REQ; end
					else if (f_c != 2'd2) begin f_c <= f_c + 2'd1; fs <= F_OK; end
					else begin
						// (kept only if the scope screen stayed on all through: off clears both halves)
						if (on) begin h_ok[f_h] <= 1; h_row[f_h] <= f_row; end
						fs <= F_IDLE;
					end
				end
			end
			default: fs <= F_IDLE;
		endcase
	end
end

// ---------------------------------------------------------------------------------
//  the picture, as the beam goes. At a pixel's strobe the next pixel's sample is asked for; a clock
//  later it is turned into that pixel (lit, middle line, nothing), which goes out after the next strobe.
// ---------------------------------------------------------------------------------
localparam X0 = 6, XP = 126, XW = 120;

// the rows
reg   [8:0] y_prev;
reg         v_on;
reg   [2:0] v_row;
reg   [5:0] v_l;                // the line within the row
wire  [8:0] top   = ntsc ? 9'd28 : 9'd19;
wire  [5:0] pitch = ntsc ? 6'd29 : 6'd33;
wire  [5:0] half  = ntsc ? 6'd14 : 6'd16;
wire signed [6:0] v_dy = $signed({1'b0, v_l}) - $signed({1'b0, half});

// the next pixel: its trace and sample
wire  [9:0] xn = vic_x + 10'd1;
reg         a_in_c;
reg   [1:0] a_col_c;
reg   [6:0] a_xl_c;
always @(*) begin
	a_in_c = 1; a_col_c = 0; a_xl_c = 0;
	if      (xn >= X0          && xn < X0 + XW)          begin a_col_c = 2'd0; a_xl_c = 7'(xn - 10'(X0)); end
	else if (xn >= X0 + XP     && xn < X0 + XP + XW)     begin a_col_c = 2'd1; a_xl_c = 7'(xn - 10'(X0 + XP)); end
	else if (xn >= X0 + 2 * XP && xn < X0 + 2 * XP + XW) begin a_col_c = 2'd2; a_xl_c = 7'(xn - 10'(X0 + 2 * XP)); end
	else a_in_c = 0;
end
wire  [9:0] a_i5 = {1'b0, a_xl_c, 2'b00} + {3'd0, a_xl_c};               // 5x
wire  [8:0] a_i  = a_i5[9:1];                                             // 5x / 2: 0..297
assign m_ra = {v_row[0], (a_col_c == 2'd0 ? 10'd0 : a_col_c == 2'd1 ? 10'd304 : 10'd608) + {1'b0, a_i}};

reg         p1;                 // the clock after the strobe
reg         a_in, a_first;
reg         b_in, b_lit, b_mid;
reg   [2:0] b_row;
reg   [1:0] l_f;                // the flags of the sample before: {d >= 0, d <= 0}

function [23:0] rowcol(input [2:0] k);
	case (k)
		0: rowcol = 24'h40FF60;  1: rowcol = 24'h40E0FF;  2: rowcol = 24'hFFE040;  3: rowcol = 24'hFF8040;
		4: rowcol = 24'hFF60C0;  5: rowcol = 24'hB080FF;  6: rowcol = 24'h60A0FF;  7: rowcol = 24'hFFFFFF;
	endcase
endfunction

always @(posedge clk) begin
	p1 <= pix_en;
	row_new <= 0;
	if (reset) begin y_prev <= 9'h1FF; v_on <= 0; v_row <= 0; v_l <= 0; a_in <= 0; b_in <= 0; b_lit <= 0; b_mid <= 0; lit <= 0; box <= 0; end
	else begin
		if (pix_en) begin
			// a new raster line: the rows count lines from the top one
			if (vic_y != y_prev) begin
				y_prev <= vic_y;
				if (vic_y == top) begin v_on <= 1; v_row <= 0; v_l <= 0; row_new <= 1; row_new_k <= 0; end
				else if (v_on) begin
					if (v_l == pitch - 6'd1) begin
						v_l <= 0;
						if (v_row == 3'd7) v_on <= 0;
						else begin v_row <= v_row + 3'd1; row_new <= 1; row_new_k <= v_row + 3'd1; end
					end
					else v_l <= v_l + 6'd1;
				end
			end
			a_in    <= a_in_c && v_on;
			a_first <= a_xl_c == 0;
		end
		if (p1) begin
			reg signed [5:0] q;
			reg signed [7:0] d;
			reg        [1:0] f, a;
			reg       [23:0] cc;
			// the pixel made a strobe ago goes out
			cc  = rowcol(b_row);
			rgb <= b_lit ? cc
			     : b_mid ? {2'b00, cc[23:18], 2'b00, cc[15:10], 2'b00, cc[7:2]}
			     : 24'h000000;
			lit <= b_lit;
			box <= b_in;
			// and the next one is made: d = (line - middle) - y, y = -q
			q = $signed({m_q[4], m_q});
			if (ntsc) q = q - $signed({{4{m_q[4]}}, m_q[4:3]});          // less an eighth: -14..14
			d = $signed({v_dy[6], v_dy}) + $signed({{2{q[5]}}, q});
			f = {d >= 0, d <= 0};
			a = a_first ? f : l_f;
			l_f   <= f;
			b_in  <= a_in;
			b_row <= v_row;
			b_mid <= a_in && v_dy == 0;
			b_lit <= a_in && h_ok[v_row[0]] && h_row[v_row[0]] == v_row && (a[1] | f[1]) && (a[0] | f[0]);
		end
	end
end

endmodule
