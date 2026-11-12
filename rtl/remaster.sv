// Octophonic64RGB - LEVEL 2 REMASTER (Build 14)                              (c) 2026 Mong00se
//
// Redrawn blocks and sprites from the pack, at the C64's own pixel grid, 256 colours. Spec: docs/RGB256.md
// "Level 2". Built only into the RGB companion core (`define RGB256), between the VIC-II and the Level 1
// recolour unit (rtl/rgb256.sv).
//
// How it works
//   * The VIC's pixels go through a 16-line ring (line RAM); the picture leaves 16 raster lines late, the
//     vertical sync with it. While a text row's 8 lines are on their way through, the ENGINE reads each
//     cell's 64 graphics-layer pixels back (a second copy of them), makes the cell's key (CRC-64), reads
//     the key's bucket from the pack's block table in the DDR3 and keeps the tile if it is there. When
//     the row comes out of the ring its tiles are in block RAM.
//   * A sprite: when its display starts the engine reads its 63 data bytes from the rewind unit's copy
//     of the C64's RAM, makes its key, reads the bucket from the sprite table and keeps the frame - long
//     before the sprite's first line comes out of the ring.
//   * Each pixel coming out: border table, the sprites' frames (front to back, the VIC's own priority
//     bits), the tile, or what the VIC drew - as a palette slot that overrides Level 1's (ovr), or the
//     VIC's colour index and tag for Level 1 to colour as before.
//   * Learn mode: a key not in its table is written once to a log in the DDR3 and marked in the table.
//
// The pixel pipeline (the VIC holds a pixel 4 clocks): A the pixel arrives (its raster X changes) - the
// ring is read; B the old pixel is out, the new one written; C tile / frame / char code reads; D the
// choice; E index and tag to rgb256, F the slot override meets rgb256's remap stage.
module remaster #(
	parameter [28:0] DDR_PACK  = 29'h06800000,    // the pack: 64-bit word address (byte $34000000)
	parameter [28:0] DDR_LEARN = 29'h06C00000     // the learn log (byte $36000000)
)
(
	input              clk,
	input              reset,
	input              on,           // Level 2 wanted (the key's switch)
	input              learn,        // learn mode
	input              reload,       // one clock: a pack has just gone in - read its Level 2 header

	// the VIC (rtl/video_vicII_656x.vhd)
	input        [3:0] index,
	input       [28:0] tag,
	input       [25:0] l2_pix,       // [3:0] gfx colour [4] fg [5] cell start [6] display state [9:7] RC [17:10] sprite starts [25:18] char code
	input      [183:0] l2_spr,
	input        [1:0] bank,
	input              vsync_in,

	// to rgb256, 16 lines later
	output reg   [3:0] d_index = 0,
	output reg  [28:0] d_tag = 0,
	output reg         d_vsync = 0,
	output reg         ovr = 0,      // the slot is Level 2's
	output reg   [7:0] ovr_slot = 0,

	// the C64's RAM (rtl/rewind.sv's copy)
	output reg  [15:0] x_addr = 0,
	output reg         x_req = 0,
	input              x_ack,        // the read is taken this clock; x_q is the byte on the next
	input        [7:0] x_q,

	// DDR3
	output reg  [28:0] ddr_addr = 0,
	output reg   [7:0] ddr_burstcnt = 1,
	output reg         ddr_rd = 0,
	output reg         ddr_we = 0,
	output reg  [63:0] ddr_din = 0,
	output       [7:0] ddr_be,
	input              ddr_busy,
	input       [63:0] ddr_dout,
	input              ddr_ready,

	output reg         l2_ok = 0,    // the pack in the DDR3 has Level 2
	output reg  [15:0] lcount = 0    // keys learned (records in the log)
);

assign ddr_be = 8'hFF;

function [63:0] crc4(input [63:0] c, input [3:0] n);   // CRC-64 (poly $42F0E1EBA9EA3693), 4 bits, MSB first
	reg [63:0] t;
	integer k;
	begin
		t = c ^ {n, 60'd0};
		for (k = 0; k < 4; k = k + 1) t = t[63] ? ({t[62:0], 1'b0} ^ 64'h42F0E1EBA9EA3693) : {t[62:0], 1'b0};
		crc4 = t;
	end
endfunction

// ================================================================== the VIC's pixel
wire  [9:0] vx    = tag[18:9];
wire  [8:0] vy    = tag[8:0];
wire  [1:0] vkind = tag[28:27];
reg   [9:0] vx_d  = 0;
wire        stb   = (vx != vx_d);            // a new pixel (stage A)
wire        wrap  = stb && (vx == 10'd0);    // ... the first of a line
reg   [3:0] slot  = 0;                       // the ring's line
wire  [3:0] slot_n = wrap ? slot + 4'd1 : slot;
wire [13:0] lb_addr = {1'b0, slot_n, 9'd0} + {7'd0, slot_n, 3'd0} + {4'd0, vx};   // line*520 + x

wire  [3:0] p_gfx  = l2_pix[3:0];
wire        p_fg   = l2_pix[4];
wire        p_cs   = l2_pix[5] & l2_pix[6];
wire  [2:0] p_rc   = l2_pix[9:7];
wire  [7:0] p_ss   = l2_pix[17:10];
wire  [7:0] p_code = l2_pix[25:18];

// ------------------------------------------------------------------ the ring: 16 lines of 520 pixels
// [3:0] the VIC's colour [5:4] kind [8:6] sprite [12:9] gfx colour [13] fg [14] cell start [15] vsync
reg  [15:0] a_new;
reg  [13:0] a_addr;
reg         a_v = 0;
reg  [15:0] lb_q;
(* ramstyle = "M10K, no_rw_check" *) reg [15:0] lb_m [0:8319];
always @(posedge clk) begin
	if (a_v) lb_m[a_addr] <= a_new;
	lb_q <= lb_m[lb_addr];
end

// ------------------------------------------------------------------ capture: cells of the line going in
reg   [6:0] ccol = 7'd127;                   // the cell being shifted out (127: none yet)
reg   [3:0] cbit = 4'd8;                     // its pixel (8: past it)
reg   [2:0] line_rc;
reg   [3:0] run = 0;                         // lines of a whole row seen so far (RC 0, 1, 2 ...)
wire  [6:0] ccol_n = p_cs ? ccol + 7'd1 : ccol;
wire  [3:0] cbit_n = p_cs ? 4'd0 : (cbit[3] ? 4'd8 : cbit + 4'd1);
wire        c_in   = (ccol_n < 7'd40) && !cbit_n[3];

// the graphics layer again, by cell, for the engine: {line, column, pixel}
reg         g_we = 0;
reg  [12:0] g_wa;
reg   [3:0] g_wd;
reg  [12:0] g_ra;
wire  [3:0] g_q;
ovram #(13, 4) gcopy (.clk(clk), .we(g_we), .wa(g_wa), .wd(g_wd), .ra(g_ra), .q(g_q));

// the char code of each cell of each line in the ring, and those of the line coming out
reg         cc_we = 0;
reg   [9:0] cc_wa;
reg   [7:0] cc_wd;
reg   [9:0] cc_ra;
wire  [7:0] cc_q;
ovram #(10, 8) ccode (.clk(clk), .we(cc_we), .wa(cc_wa), .wd(cc_wd), .ra(cc_ra), .q(cc_q));
reg         dc_we = 0;
reg   [5:0] dc_wa;
reg   [5:0] dc_ra;
wire  [7:0] dc_q;
ovram #(6, 8) dcode (.clk(clk), .we(dc_we), .wa(dc_wa), .wd(cc_q), .ra(dc_ra), .q(dc_q));

// ------------------------------------------------------------------ rows
reg   [4:0] rinfo [0:15];                    // each ring line: [4] part of a whole row, [3] its tile buffer, [2:0] RC
reg         nextbuf = 0;
reg  [39:0] tvalid [0:1];                    // tiles in (per buffer, per column)
reg         rj_pend = 0;                     // a row for the engine
reg   [3:0] rj_slot;
reg         rj_buf;
integer     ri;
initial begin for (ri = 0; ri < 16; ri = ri + 1) rinfo[ri] = 0; tvalid[0] = 0; tvalid[1] = 0; end

// ------------------------------------------------------------------ sprites of the line going in
wire  [5:0] s_mcnt [0:7];
wire        s_xe   [0:7];
wire        s_prio [0:7];
wire        s_mc   [0:7];
wire  [3:0] s_col  [0:7];
wire  [7:0] s_ptr  [0:7];
genvar gi;
generate
	for (gi = 0; gi < 8; gi = gi + 1) begin : sp
		assign s_mcnt[gi] = l2_spr[gi*22 +: 6];
		assign s_xe[gi]   = l2_spr[gi*22 + 6];
		assign s_prio[gi] = l2_spr[gi*22 + 7];
		assign s_mc[gi]   = l2_spr[gi*22 + 8];
		assign s_col[gi]  = l2_spr[gi*22 + 9 +: 4];
		assign s_ptr[gi]  = l2_spr[gi*22 + 13 +: 8];
	end
endgenerate
wire  [3:0] s_mm0 = l2_spr[179:176];
wire  [3:0] s_mm1 = l2_spr[183:180];

// a sprite's record for a line: [19] shown [18] frame buffer [17] behind graphics [16] X-expanded [15:10] MC [9:0] X of its first pixel
reg  [19:0] cs_rec [0:7];                    // the line going in
reg  [19:0] cs_snap [0:7];                   // ... as it ended (to be stored)
reg  [19:0] ds_rec [0:7];                    // the line coming out
reg   [7:0] spp = 0;                         // each sprite's current frame buffer
reg   [7:0] s_first = 8'hFF;                 // its next start is the start of a display (not seen since the frame began / its last row)
reg  [15:0] fvalid = 0;                      // frame in: {buffer, sprite}
reg   [7:0] sj_pend = 0;                     // sprites for the engine
reg   [7:0] sj_kill = 0;                     // ... whose job is void (started again before it was done)
reg  [15:0] sj_addr [0:7];
reg  [12:0] sj_key  [0:7];                   // mc, colour, $D025, $D026
reg   [7:0] sj_pp;
integer     si;
initial for (si = 0; si < 8; si = si + 1) begin cs_rec[si] = 0; cs_snap[si] = 0; ds_rec[si] = 0; end

reg         si_we = 0;
reg   [6:0] si_wa;
reg  [19:0] si_wd;
reg   [6:0] si_ra;
wire [19:0] si_q;
ovram #(7, 20) sinfo (.clk(clk), .we(si_we), .wa(si_wa), .wd(si_wd), .ra(si_ra), .q(si_q));

// ------------------------------------------------------------------ the line's start: what the line coming out needs
reg   [8:0] ry0 [0:15];                      // each ring line's raster Y at its first pixel
reg   [8:0] d_ry_a, d_ry_b;                  // the line coming out: its Y before and after the VIC's Y steps
reg   [9:0] ry_x = 10'd1023;                 // the X at which the VIC's Y steps
reg   [8:0] vy_d = 0;
reg   [4:0] d_rinfo = 0;
reg   [6:0] wseq = 7'd127;                   // the start-of-line sequencer (127: idle)
reg   [3:0] wslot;                           // the line that has just ended
integer     yi;
initial for (yi = 0; yi < 16; yi = yi + 1) ry0[yi] = 0;

// ------------------------------------------------------------------ the engine's stores
// tiles: {buffer, column, row} -> 8 pixels
reg         t_we = 0;
reg   [9:0] t_wa;
reg  [63:0] t_wd;
reg   [9:0] t_ra;
wire [63:0] t_q;
ovram #(10, 64) tiles (.clk(clk), .we(t_we), .wa(t_wa), .wd(t_wd), .ra(t_ra), .q(t_q));
// frames: per sprite {buffer, word of the entry (1-63)} -> 8 pixels
reg   [7:0] f_we = 0;
reg   [6:0] f_wa;
reg  [63:0] f_wd;
wire  [6:0] f_ra [0:7];
wire [63:0] f_q  [0:7];
generate
	for (gi = 0; gi < 8; gi = gi + 1) begin : fr
		ovram #(7, 64) m (.clk(clk), .we(f_we[gi]), .wa(f_wa), .wd(f_wd), .ra(f_ra[gi]), .q(f_q[gi]));
	end
endgenerate
// the border table: 64 words of 8 lines
reg         b_we = 0;
reg   [5:0] b_wa;
reg  [63:0] b_wd;
reg   [5:0] b_ra;
wire [63:0] b_q;
ovram #(6, 64) btab (.clk(clk), .we(b_we), .wa(b_wa), .wd(b_wd), .ra(b_ra), .q(b_q));

// ================================================================== the pixel coming out
// stage B: lb_q is the pixel of 16 lines ago
reg         b_v = 0;
reg   [9:0] a_x, b_x;
reg  [15:0] b_pix;
reg   [6:0] dcol = 7'd127;
reg   [3:0] dbit = 4'd8;
wire        q_cs   = lb_q[14];
wire  [6:0] dcol_n = q_cs ? dcol + 7'd1 : dcol;
wire  [3:0] dbit_n = q_cs ? 4'd0 : (dbit[3] ? 4'd8 : dbit + 4'd1);
// stage C
reg         c_v = 0;
reg  [15:0] c_pix;
reg   [9:0] c_x;
reg   [8:0] c_ry;
reg         c_cell, c_tv, c_inc;
reg   [2:0] c_bit;
reg   [7:0] c_sin;
reg   [2:0] c_csel [0:7];
wire [10:0] s_dx  [0:7];
wire  [9:0] s_cx  [0:7];
wire  [7:0] s_inw;
generate
	for (gi = 0; gi < 8; gi = gi + 1) begin : dsp
		assign s_dx[gi]  = {1'b0, b_x} - {1'b0, ds_rec[gi][9:0]};
		assign s_cx[gi]  = ds_rec[gi][16] ? {1'b0, s_dx[gi][9:1]} : s_dx[gi][9:0];
		assign s_inw[gi] = ds_rec[gi][19] && !s_dx[gi][10] && (s_cx[gi] < 10'd24);
		assign f_ra[gi]  = {ds_rec[gi][18], ds_rec[gi][15:10] - 6'd2 + {4'd0, s_cx[gi][4:3]}};
	end
endgenerate
wire  [8:0] a_ry = (a_x >= ry_x) ? d_ry_b : d_ry_a;
wire  [8:0] b_ry = (b_x >= ry_x) ? d_ry_b : d_ry_a;
wire        l2on = on & l2_ok;

// stage D: the choice
reg   [7:0] f_byte [0:7];
reg   [7:0] cand;
reg   [7:0] t_byte, bd_byte;
reg   [2:0] m, win;
reg         any, repl_m, tile_hit;
reg         o_ovr = 0;
reg   [7:0] o_slot = 0;
reg         c_vs;
integer     di, dj;
always @(*) begin
	t_byte  = t_q[c_bit*8 +: 8];
	bd_byte = b_q[c_ry[2:0]*8 +: 8];
	m       = c_pix[8:6];
	repl_m  = l2on && ds_rec[m][19] && fvalid[{ds_rec[m][18], m}];
	any = 0; win = 0;
	for (di = 7; di >= 0; di = di - 1) begin
		f_byte[di] = f_q[di][c_csel[di]*8 +: 8];
		cand[di] = l2on && c_sin[di] && fvalid[{ds_rec[di][18], di[2:0]}] && (f_byte[di] != 0)
		           && (!ds_rec[di][17] || !c_pix[13])
		           && ((c_pix[5:4] != 2'd1) || repl_m || (di[2:0] < m));
		if (cand[di]) begin any = 1; win = di[2:0]; end
	end
	tile_hit = l2on && c_cell && c_tv && (t_byte != 0);
end

// ================================================================== the engine
localparam [4:0] E_IDLE = 0, E_HDR = 1, E_HDRW = 2, E_LRN = 3, E_LRNW = 4, E_BRD = 5, E_BRDW = 6, E_BRDZ = 7,
                 C_HASH = 8, C_REQ = 9, C_RX = 10, C_DONE = 11,
                 S_PRE = 12, S_RD = 13, S_RD2 = 14, S_REQ = 15, S_RX = 16, S_DONE = 17,
                 L_MARK = 18, L_REC = 19, L_RECW = 20, L_CNT = 21, L_END = 22, E_REQ = 23;
reg   [4:0] st = E_IDLE, st_ret;
reg         do_hdr = 1;
reg  [21:0] blk_off, spr_off, brd_off;       // in words, from the pack's start
reg   [4:0] nb, ns;
reg         rj_run = 0;                      // a row in hand
reg   [3:0] ej_slot;
reg         ej_buf;
reg   [5:0] rcol;
reg  [63:0] crc;
reg   [6:0] cnt;
reg         hv = 0, hv0 = 0;                          // the graphics copy's answer is here
reg   [5:0] hcnt;
reg   [3:0] hn;                              // a byte's high half
reg  [63:0] kacc;
reg   [7:0] rxk;
reg         m0, m1, e0, e1;
reg   [2:0] sn;                              // the sprite in hand
reg         sway;
reg         is_spr;
reg  [28:0] ent_addr;                        // the entry looked at / to mark
reg  [28:0] lptr;                            // the next log record's address
reg   [3:0] lk;
reg   [5:0] bk;

// the key's bytes, kept for the learn record (8 words)
reg         k_we = 0;
reg   [2:0] k_wa;
reg   [2:0] k_ra;
wire [63:0] k_q;
ovram #(3, 64) kbuf (.clk(clk), .we(k_we), .wa(k_wa), .wd(kacc), .ra(k_ra), .q(k_q));

wire [63:0] nb_mask = (64'd1 << nb) - 64'd1;
wire [63:0] ns_mask = (64'd1 << ns) - 64'd1;
wire [24:0] blk_bucket = crc[24:0] & nb_mask[24:0];
wire [24:0] spr_bucket = crc[24:0] & ns_mask[24:0];
wire [28:0] blk_addr = DDR_PACK + {7'd0, blk_off} + {blk_bucket, 4'd0} + {3'd0, blk_bucket, 1'b0};    // bucket * 18 words
wire [28:0] spr_addr = DDR_PACK + {7'd0, spr_off} + {spr_bucket[21:0], 7'd0};                        // bucket * 128 words
wire        learn_ok = learn && l2_ok && (lcount < 16'hFFF0);
wire [63:0] crc_b = crc4(crc4(crc, x_q[7:4]), x_q[3:0]);

function [2:0] low8(input [7:0] v);
	begin
		low8 = v[0] ? 3'd0 : v[1] ? 3'd1 : v[2] ? 3'd2 : v[3] ? 3'd3 : v[4] ? 3'd4 : v[5] ? 3'd5 : v[6] ? 3'd6 : 3'd7;
	end
endfunction

reg   [7:0] pre_byte;
always @(*) begin
	case (cnt[1:0])
		2'd0:    pre_byte = {7'd0, sj_key[sn][12]};
		2'd1:    pre_byte = {4'd0, sj_key[sn][11:8]};
		2'd2:    pre_byte = {4'd0, sj_key[sn][7:4]};
		default: pre_byte = {4'd0, sj_key[sn][3:0]};
	endcase
end

integer ci;
always @(posedge clk) begin
	vx_d  <= vx;
	a_v   <= stb;
	g_we  <= 0;
	cc_we <= 0;
	dc_we <= 0;
	si_we <= 0;
	t_we  <= 0;
	f_we  <= 0;
	b_we  <= 0;
	k_we  <= 0;
	if (reload) do_hdr <= 1;

	// ---------------------------------------------------------- stages B to E: the pixel coming out
	// B
	b_v   <= a_v;
	b_x   <= a_x;
	if (a_v) begin
		b_pix <= lb_q;
		dcol  <= dcol_n;
		dbit  <= dbit_n;
		dc_ra <= (dcol_n < 7'd40) ? dcol_n[5:0] : 6'd0;
		t_ra  <= {d_rinfo[3], (dcol_n < 7'd40) ? dcol_n[5:0] : 6'd0, d_rinfo[2:0]};
		b_ra  <= a_ry[8:3];
	end
	// C
	c_v    <= b_v;
	if (b_v) begin
		c_pix  <= b_pix;
		c_x    <= b_x;
		c_ry   <= b_ry;
		c_cell <= d_rinfo[4] && (dcol < 7'd40) && !dbit[3];
		c_inc  <= (dcol < 7'd40) && !dbit[3];
		c_tv   <= tvalid[d_rinfo[3]][(dcol < 7'd40) ? dcol[5:0] : 6'd0];
		c_bit  <= dbit[2:0];
		c_sin  <= s_inw;
		for (dj = 0; dj < 8; dj = dj + 1) c_csel[dj] <= s_cx[dj][2:0];
	end
	// D -> E: index and tag for rgb256, the override one clock behind them
	if (c_v) begin
		d_vsync <= c_pix[15];
		o_ovr   <= 0;
		if (c_pix[5:4] == 2'd3) begin                       // blank
			d_index <= 4'd0;
			d_tag   <= {2'd3, 8'd0, c_x, c_ry};
		end
		else if (c_pix[5:4] == 2'd2) begin                  // border
			d_index <= c_pix[3:0];
			d_tag   <= {2'd2, 8'd0, c_x, c_ry};
			o_ovr   <= l2on && (bd_byte != 0);
			o_slot  <= bd_byte;
		end
		else if (any) begin                                 // a sprite's frame
			d_index <= c_pix[3:0];
			d_tag   <= {2'd1, 5'd0, win, c_x, c_ry};
			o_ovr   <= 1;
			o_slot  <= f_byte[win];
		end
		else if (c_pix[5:4] == 2'd1 && !repl_m) begin       // the VIC's sprite
			d_index <= c_pix[3:0];
			d_tag   <= {2'd1, 5'd0, m, c_x, c_ry};
		end
		else begin                                          // graphics: the tile, or Level 1's
			d_index <= c_pix[12:9];
			d_tag   <= {2'd0, c_inc ? dc_q : 8'd0, c_x, c_ry};        // (the char code where there is a cell)
			o_ovr   <= tile_hit;
			o_slot  <= t_byte;
		end
	end
	ovr      <= o_ovr;
	ovr_slot <= o_slot;

	// ---------------------------------------------------------- stage A: the pixel going in
	if (stb) begin
		a_new  <= {vsync_in, p_cs & (ccol_n < 7'd40), p_fg, p_gfx, tag[21:19], vkind, index};
		a_addr <= lb_addr;
		a_x    <= vx;
		slot   <= slot_n;
		vy_d   <= vy;
		if (vy != vy_d && !wrap) ry_x <= vx;

		if (wrap) begin
			// the line that ended: a whole row's line?
			wslot <= slot;
			wseq  <= 0;
			if (ccol == 7'd39 && line_rc == 3'd0)                     run <= 4'd1;
			else if (ccol == 7'd39 && run != 0 && line_rc == run[2:0]) run <= run + 4'd1;
			else                                                       run <= 0;
			if (ccol == 7'd39 && run == 4'd7 && line_rc == 3'd7) begin
				// RC 0-7 seen in order: the row is whole - its 8 ring lines get a tile buffer, the engine the row
				for (ci = 0; ci < 8; ci = ci + 1) rinfo[slot - 4'd7 + ci[3:0]] <= {1'b1, nextbuf, ci[2:0]};
				tvalid[nextbuf] <= 0;
				rj_pend <= 1;
				rj_slot <= slot - 4'd7;
				rj_buf  <= nextbuf;
				nextbuf <= ~nextbuf;
				run     <= 0;
			end
			// the line coming out now (it is about to be written over)
			d_rinfo <= rinfo[slot_n];
			rinfo[slot_n] <= 0;
			d_ry_a  <= ry0[slot_n];
			d_ry_b  <= ry0[slot_n + 4'd1];
			ry0[slot_n] <= vy;
			dcol <= 7'd127;
			dbit <= 4'd8;
			ccol <= 7'd127;
			cbit <= 4'd8;
			for (ci = 0; ci < 8; ci = ci + 1) begin
				cs_snap[ci] <= cs_rec[ci];
				cs_rec[ci]  <= 0;
			end
		end
		else begin
			ccol <= ccol_n;
			cbit <= cbit_n;
			if (p_cs && ccol_n == 7'd0) line_rc <= p_rc;
			if (p_cs && ccol_n < 7'd40) begin
				cc_we <= 1; cc_wa <= {slot, ccol_n[5:0]}; cc_wd <= p_code;
			end
			if (c_in) begin
				g_we <= 1; g_wa <= {slot, ccol_n[5:0], cbit_n[2:0]}; g_wd <= p_gfx;
			end
			// sprites starting at this pixel
			for (ci = 0; ci < 8; ci = ci + 1) if (p_ss[ci]) begin
				if (s_mcnt[ci] == 6'd3 && s_first[ci]) begin
					// its display starts: a frame to find (into its other buffer)
					s_first[ci] <= 0;
					sj_addr[ci] <= {bank, s_ptr[ci], 6'd0};
					sj_key[ci]  <= {s_mc[ci], s_col[ci], s_mc[ci] ? {s_mm0, s_mm1} : 8'd0};
					if (sj_pend[ci] || (st >= S_PRE && st <= S_DONE && sn == ci[2:0])) begin
						sj_kill[ci] <= 1;                              // (the last one is not done yet: neither counts)
						fvalid[{~spp[ci], ci[2:0]}] <= 0;
						fvalid[{spp[ci], ci[2:0]}]  <= 0;
						cs_rec[ci] <= {1'b1, spp[ci], s_prio[ci], s_xe[ci], s_mcnt[ci], vx};
					end
					else begin
						spp[ci]    <= ~spp[ci];
						fvalid[{~spp[ci], ci[2:0]}] <= 0;
						cs_rec[ci] <= {1'b1, ~spp[ci], s_prio[ci], s_xe[ci], s_mcnt[ci], vx};
					end
					sj_pend[ci] <= 1;
				end
				else begin
					cs_rec[ci] <= {1'b1, spp[ci], s_prio[ci], s_xe[ci], s_mcnt[ci], vx};
					if (s_mcnt[ci] != 6'd3) s_first[ci] <= 1;         // (past its first row: the next row 0 is a new display)
				end
			end
		end
		if (vsync_in) s_first <= 8'hFF;
	end

	// ---------------------------------------------------------- the start of a line: the sprites' records and the char codes
	// 0-9: the records of the line coming out (ring line `slot`) are read; 10-17: the ended line's are stored;
	// 18-59: the char codes of the line coming out are copied before the line going in writes over them
	if (wseq != 7'd127) begin
		wseq <= wseq + 7'd1;
		if (wseq < 7'd8)  si_ra <= {slot, wseq[2:0]};
		if (wseq >= 7'd2 && wseq < 7'd10) ds_rec[wseq[3:0] - 4'd2] <= si_q;
		if (wseq >= 7'd10 && wseq < 7'd18) begin
			si_we <= 1; si_wa <= {wslot, wseq[2:0] - 3'd2}; si_wd <= cs_snap[wseq[2:0] - 3'd2];
		end
		if (wseq >= 7'd18 && wseq < 7'd58) cc_ra <= {slot, wseq[5:0] - 6'd18};
		if (wseq >= 7'd19 && wseq < 7'd59) begin dc_we <= 1; dc_wa <= wseq[5:0] - 6'd19; end   // (written on the next clock, when the code is out)
		if (wseq == 7'd60) wseq <= 7'd127;
	end

	// ---------------------------------------------------------- the engine
	if (ddr_rd & ~ddr_busy) ddr_rd <= 0;
	if (ddr_we & ~ddr_busy) ddr_we <= 0;
	hv  <= hv0;
	hv0 <= 0;

	case (st)
		E_IDLE: begin
			if (do_hdr) begin
				do_hdr <= 0; l2_ok <= 0; rj_run <= 0;
				tvalid[0] <= 0; tvalid[1] <= 0; fvalid <= 0;
				ddr_addr <= DDR_PACK + 29'h700; ddr_burstcnt <= 8'd8; rxk <= 0;
				st <= E_REQ; st_ret <= E_HDRW;
			end
			else if (sj_pend != 0) begin
				sn <= low8(sj_pend);
				sj_pend[low8(sj_pend)] <= 0;
				sj_kill[low8(sj_pend)] <= 0;
				sj_pp[low8(sj_pend)]   <= spp[low8(sj_pend)];
				crc <= 64'hFFFFFFFFFFFFFFFF; cnt <= 0; is_spr <= 1;
				st <= l2_ok ? S_PRE : E_IDLE;
			end
			else if (rj_pend) begin
				rj_pend <= 0; rj_run <= l2_ok; ej_slot <= rj_slot; ej_buf <= rj_buf; rcol <= 0;
			end
			else if (rj_run) begin
				crc <= 64'hFFFFFFFFFFFFFFFF; cnt <= 0; hcnt <= 0; is_spr <= 0;
				st <= C_HASH;
			end
		end

		// a read: ask, then on to st_ret when it is taken
		E_REQ: begin
			ddr_rd <= 1;
			st <= st_ret;
		end

		// ----- the pack's Level 2 header, the learn log's count, the border table
		E_HDRW: if (ddr_ready) begin
			rxk <= rxk + 8'd1;
			case (rxk[2:0])
				3'd0: m0 <= (ddr_dout[31:0] == 32'h324C564C);           // "LVL2"
				3'd1: begin blk_off <= ddr_dout[24:3];  nb <= (ddr_dout[36:32] > 5'd20) ? 5'd20 : ddr_dout[36:32]; end
				3'd2: begin spr_off <= ddr_dout[24:3];  ns <= (ddr_dout[36:32] > 5'd16) ? 5'd16 : ddr_dout[36:32]; end
				3'd3: brd_off <= ddr_dout[24:3];
				default: ;
			endcase
			if (rxk[2:0] == 3'd7) begin
				if (m0) begin
					ddr_addr <= DDR_LEARN; ddr_burstcnt <= 8'd1;
					st <= E_REQ; st_ret <= E_LRNW;
				end
				else st <= E_IDLE;
			end
		end
		E_LRNW: if (ddr_ready) begin
			lcount <= (ddr_dout[31:0] == 32'h324E524C) ? ddr_dout[47:32] : 16'd0;   // "LRN2"
			bk <= 0;
			if (brd_off != 0) begin
				ddr_addr <= DDR_PACK + {7'd0, brd_off}; ddr_burstcnt <= 8'd64;
				st <= E_REQ; st_ret <= E_BRDW;
			end
			else st <= E_BRDZ;
		end
		E_BRDW: if (ddr_ready) begin
			b_we <= 1; b_wa <= bk; b_wd <= ddr_dout;
			bk <= bk + 6'd1;
			if (bk == 6'd63) st <= E_LRN;
		end
		E_BRDZ: begin
			b_we <= 1; b_wa <= bk; b_wd <= 64'd0;
			bk <= bk + 6'd1;
			if (bk == 6'd63) st <= E_LRN;
		end
		E_LRN: begin
			lptr  <= DDR_LEARN + 29'd1 + {10'd0, lcount, 3'd0} + {12'd0, lcount, 1'b0};   // 1 + count * 10
			l2_ok <= 1;
			st    <= E_IDLE;
		end

		// ----- a cell: its 64 pixels -> key -> bucket -> tile
		C_HASH: begin
			// cnt 0-63 asks for row cnt[5:3], pixel cnt[2:0]; the answer is here two clocks on
			if (!cnt[6]) begin
				g_ra <= {ej_slot + {1'b0, cnt[5:3]}, rcol, cnt[2:0]};
				cnt  <= cnt + 7'd1;
			end
			hv0 <= !cnt[6];
		end
		C_REQ: begin
			ent_addr <= blk_addr;
			ddr_addr <= blk_addr; ddr_burstcnt <= 8'd18; rxk <= 0;
			st <= E_REQ; st_ret <= C_RX;
		end
		C_RX: if (ddr_ready) begin
			rxk <= rxk + 8'd1;
			if (rxk == 8'd0) begin m0 <= (ddr_dout == crc); e0 <= (ddr_dout == 64'd0); end
			if (rxk == 8'd9) begin m1 <= (ddr_dout == crc) && !m0; e1 <= (ddr_dout == 64'd0); end
			if ((rxk >= 8'd1 && rxk <= 8'd8 && m0) || (rxk >= 8'd10 && m1)) begin
				t_we <= 1; t_wd <= ddr_dout;
				t_wa <= {ej_buf, rcol, (rxk >= 8'd10) ? rxk[2:0] - 3'd2 : rxk[2:0] - 3'd1};
			end
			if (rxk == 8'd17) st <= C_DONE;
		end
		C_DONE: begin
			if (m0 | m1) tvalid[ej_buf][rcol] <= 1;
			rcol <= rcol + 6'd1;
			if (rcol == 6'd39 || rj_pend) rj_run <= 0;                 // the row is done (or the next one is already here)
			if (!(m0 | m1) && learn_ok && (e0 | e1)) begin
				ent_addr <= ent_addr + (e0 ? 29'd0 : 29'd9);
				st <= L_MARK;
			end
			else st <= E_IDLE;
		end

		// ----- a sprite: mc, colours, 63 bytes -> key -> bucket -> frame
		S_PRE: begin                                                   // the 4 bytes before the data
			crc <= crc4(crc4(crc, pre_byte[7:4]), pre_byte[3:0]);
			cnt <= cnt + 7'd1;
			if (cnt == 7'd3) begin cnt <= 0; st <= S_RD; end
		end
		S_RD: begin
			x_addr <= sj_addr[sn] + {10'd0, cnt[5:0]};
			x_req  <= 1;
			if (x_req & x_ack) begin x_req <= 0; st <= S_RD2; end
		end
		S_RD2: begin
			crc  <= crc_b;
			kacc <= {x_q, kacc[63:8]};
			cnt  <= cnt + 7'd1;
			if (cnt[2:0] == 3'd7) begin k_we <= 1; k_wa <= cnt[5:3]; end   // (kacc is whole on the next clock, when it is written)
			if (cnt == 7'd62) begin                                        // (the last word has 7 bytes)
				kacc <= {8'd0, x_q, kacc[63:16]};
				k_we <= 1; k_wa <= 3'd7;
				sway <= 0; st <= S_REQ;
			end
			else st <= S_RD;
		end
		S_REQ: begin
			ent_addr <= spr_addr + (sway ? 29'd64 : 29'd0);
			ddr_addr <= spr_addr + (sway ? 29'd64 : 29'd0); ddr_burstcnt <= 8'd64; rxk <= 0;
			st <= E_REQ; st_ret <= S_RX;
		end
		S_RX: if (ddr_ready) begin
			rxk <= rxk + 8'd1;
			if (rxk == 8'd0) begin
				m0 <= (ddr_dout == crc);
				if (!sway) e0 <= (ddr_dout == 64'd0); else e1 <= (ddr_dout == 64'd0);
			end
			else begin
				f_we[sn] <= 1; f_wa <= {sj_pp[sn], rxk[5:0]}; f_wd <= ddr_dout;
			end
			if (rxk == 8'd63) st <= S_DONE;
		end
		S_DONE: begin
			if (m0) begin
				if (!sj_kill[sn] && !sj_pend[sn]) fvalid[{sj_pp[sn], sn}] <= 1;
				st <= E_IDLE;
			end
			else if (!sway) begin sway <= 1; st <= S_REQ; end
			else if (learn_ok && (e0 | e1)) begin
				ent_addr <= ent_addr - (e0 ? 29'd64 : 29'd0);
				st <= L_MARK;
			end
			else st <= E_IDLE;
		end

		// ----- learn: mark the key in the table, write its record, count it
		L_MARK: if (!ddr_we) begin
			ddr_addr <= ent_addr; ddr_burstcnt <= 8'd1; ddr_din <= crc; ddr_we <= 1;
			lk <= 0; k_ra <= 0;
			st <= L_REC;
		end
		L_REC: if (!ddr_we) begin
			ddr_addr <= lptr + {25'd0, lk}; ddr_burstcnt <= 8'd1; ddr_we <= 1;
			case (lk)
				4'd0:    ddr_din <= is_spr ? {4'd0, sj_key[sn][3:0], 4'd0, sj_key[sn][7:4], 4'd0, sj_key[sn][11:8], 7'd0, sj_key[sn][12], 24'd0, 8'd2}
				                           : 64'd1;
				4'd1:    ddr_din <= crc;
				default: ddr_din <= (!is_spr && lk >= 4'd6) ? 64'd0 : k_q;
			endcase
			if (lk >= 4'd1) k_ra <= lk[2:0] - 3'd1;                     // (the record's word lk+1 is key word lk-1)
			lk <= lk + 4'd1;
			if (lk == 4'd9) st <= L_CNT;
		end
		L_CNT: if (!ddr_we) begin
			ddr_addr <= DDR_LEARN; ddr_burstcnt <= 8'd1; ddr_we <= 1;
			ddr_din  <= {16'd0, lcount + 16'd1, 32'h324E524C};
			lcount   <= lcount + 16'd1;
			lptr     <= lptr + 29'd10;
			st <= L_END;
		end
		L_END: if (!ddr_we) st <= E_IDLE;

		default: st <= E_IDLE;
	endcase

	// the graphics copy's answers: two nibbles make a key byte, 8 bytes a word for the learn record
	if (st == C_HASH && hv) begin
		crc  <= crc4(crc, g_q);
		hcnt <= hcnt + 6'd1;
		if (!hcnt[0]) hn <= g_q;
		else begin
			kacc <= {hn, g_q, kacc[63:8]};
			if (hcnt[3:0] == 4'hF) begin k_we <= 1; k_wa <= {1'b0, hcnt[5:4]}; end
		end
		if (hcnt == 6'd63) st <= C_REQ;
	end

	if (reset) begin
		st <= E_IDLE; do_hdr <= 1; l2_ok <= 0; rj_pend <= 0; rj_run <= 0; sj_pend <= 0;
		ddr_rd <= 0; ddr_we <= 0; x_req <= 0; fvalid <= 0; tvalid[0] <= 0; tvalid[1] <= 0;
	end
end

endmodule
