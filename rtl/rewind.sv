// Octophonic64RGB - REWIND (Fix 61, Build 13)                              (c) 2026 Mong00se
//
// Hold the rewind key and the game runs backwards; let go and it plays on from that moment.
//
// How it works
//   * The C64's 64K of RAM is read from a copy in block RAM here (every write to the SDRAM's first
//     64K is copied in), so an old byte can be put back in one clock.
//   * Every write to RAM or colour RAM pushes "address + the byte it replaced" onto a stack in the
//     DDR3 (one 64-bit word each; the stack is a ring of 2^AW words - 128 MB).
//   * Once a frame (the first C64 cycle of raster line LINE) a save state is pushed on top: every
//     flip-flop of the 6510 and both CIAs, and the last value written to each VIC-II and SID register
//     (NW words), then a marker word. Recording never stops or slows the machine.
//   * A rewind step (once a frame while the key is held): the 6510 and the CIAs are frozen, the stack
//     is popped back to the save state one frame earlier - each popped word puts its old byte back -
//     the save state is loaded, the VIC-II and SID registers are written back, and the machine runs
//     on. It then plays that one frame forwards (that is the picture and the sound), and at the next
//     frame line the step repeats, one frame further back. The VIC-II is never stopped, so the
//     picture's timing does not change; the 6510 loses a few raster lines in the lower border per step.
//   * At the oldest save state the step repeats on the spot (the game stands still).
//
// Not saved: the REU's memory, a cartridge's RAM, the disk drive (the history is dropped while the
// drive is busy or a file loads - "block"), the SIDs' envelopes and oscillators (their registers are).
module rewind #(
	parameter [28:0] DDR_BASE = 29'h07000000,     // 64-bit word address: byte $38000000
	parameter        AW       = 24,               // the stack: 2^AW words
	parameter  [8:0] LINE     = 9'd256,           // the raster line of the save state (lower border)
	parameter [11:0] NF_MAX   = 12'd1536          // frames kept (30.7 s at 50 Hz)
)
(
	input              clk,
	input              reset,
	input              enable,       // the menu's switch
	input              hold,         // the rewind key
	input              block,        // drive busy / a file loading: no rewind, the history dropped
	input              busy_dma,     // the REU is moving memory: no freeze now

	// the C64 (rtl/fpga64_sid_iec.vhd rw_*)
	input              tick,
	input        [8:0] ry,
	output reg         freeze = 0,
	input      [175:0] cpu_o,
	input      [319:0] cia1_o,
	input      [319:0] cia2_o,
	output reg [175:0] cpu_i,
	output reg [319:0] cia1_i,
	output reg [319:0] cia2_i,
	output reg         ld = 0,
	input              io_wr,
	input        [3:0] io_sel,
	input        [9:0] io_addr,
	input        [7:0] io_data,
	input        [3:0] col_old,
	output reg         vic_we = 0,
	output reg   [5:0] vic_addr,
	output reg   [7:0] vic_data,
	output reg         sid_we = 0,
	output reg   [1:0] sid_cs,
	output reg   [4:0] sid_addr,
	output reg   [7:0] sid_data,
	output reg         col_we = 0,
	output reg   [9:0] col_addr,
	output reg   [3:0] col_data,

	// the memory port, as the SDRAM sees it (c64.sv)
	input       [24:0] m_addr,
	input              m_ce,
	input              m_we,
	input        [7:0] m_din,
	input              m_main,       // the C64's own cycle (not a file load, not the REU's memory)
	output       [7:0] m_q,
	output reg         m_sel = 0,    // m_q is the byte (the access was to the C64's 64K)

	// DDR3 (rtl/octovic/ddram_arb2.sv port B)
	output      [28:0] ddr_addr,
	output       [7:0] ddr_burstcnt,
	output reg         ddr_rd = 0,
	output reg         ddr_we = 0,
	output      [63:0] ddr_din,
	output       [7:0] ddr_be,
	input              ddr_busy,
	input       [63:0] ddr_dout,
	input              ddr_ready,

	output reg         active = 0,   // rewinding (the on-screen word, the sound turned down)
	output reg  [11:0] frames = 0,   // save states held
	output reg         err = 0       // the stack did not read back as written (history dropped)
);

localparam        NW     = 27;                 // words of a save state
localparam  [3:0] T_RAM  = 4'h1, T_COL = 4'h2, T_MARK = 4'hF;
localparam [11:0] MAGIC  = 12'hA5C;
localparam [AW:0] LIMIT  = (1 << AW) - ((AW >= 22) ? (1 << 20) : (1 << (AW - 2)));   // words held before the oldest frames go

// ------------------------------------------------------------------ the 64K copy
reg         m_ce_d = 0;
wire        m_start = m_ce & ~m_ce_d;
wire        m_low   = (m_addr[24:16] == 9'd0);
reg  [15:0] a_addr_r;
reg   [7:0] a_din_r;
reg         a_wpend = 0, a_main = 0;
reg         b_req = 0;                         // an old byte to put back (b_addr, b_data)
reg  [15:0] b_addr;
reg   [7:0] b_data;
wire        b_do = b_req;                      // (it goes first: a write from outside waits a clock)
wire        a_do = a_wpend & ~b_req;
wire  [7:0] qa;

ovram #(16, 8) ram
(
	.clk(clk),
	.we(a_do | b_do),
	.wa(b_do ? b_addr : a_addr_r),
	.wd(b_do ? b_data : a_din_r),
	.ra((m_start & m_low) ? m_addr[15:0] : a_addr_r),
	.q(qa)
);
assign m_q = qa;

reg         jr_req = 0, jc_req = 0;            // a journal word waiting for the FIFO
reg  [63:0] jr_word, jc_word;
reg         ovf = 0;                           // a journal word was lost: the history must go

always @(posedge clk) begin
	m_ce_d  <= m_ce;
	a_wpend <= a_wpend & b_req;
	if (m_start) begin
		m_sel <= m_low;
		if (m_low) begin
			a_addr_r <= m_addr[15:0];
			a_din_r  <= m_din;
			a_wpend  <= m_we;
			a_main   <= m_main;
		end
	end
end

// ------------------------------------------------------------------ the FIFO to the DDR3
reg   [7:0] f_wp = 0, f_rp = 0;
reg   [8:0] f_cnt = 0;
wire        f_full = (f_cnt >= 9'd248);
reg         f_we;
reg  [63:0] f_wd;
wire [63:0] f_q;
ovram #(8, 64) fifo (.clk(clk), .we(f_we), .wa(f_wp), .wd(f_wd), .ra(f_rp), .q(f_q));

// ------------------------------------------------------------------ the register shadows
// 14 words of 8 bytes: 0-5 the VIC-II's $D000-$D02F, 6-9 SID 1's $00-$1F, 10-13 SID 2's
reg         sh_we = 0;
reg   [7:0] sh_lane;
reg   [3:0] sh_wa;
reg  [63:0] sh_wd;
reg   [3:0] sh_ra;
wire [63:0] sh_q;
genvar gi;
generate
	for (gi = 0; gi < 8; gi = gi + 1) begin : shl
		ovram #(4, 8) m (.clk(clk), .we(sh_we & sh_lane[gi]), .wa(sh_wa), .wd(sh_wd[gi*8 +: 8]), .ra(sh_ra), .q(sh_q[gi*8 +: 8]));
	end
endgenerate
reg         sh2_pend = 0;                      // the same write went to SID 2 as well
reg   [4:0] sh2_addr;
reg   [7:0] sh2_data;

// ------------------------------------------------------------------ what was read back
reg   [5:0] rb_wa;
reg         rb_we;
reg  [63:0] rb_wd;
reg   [5:0] rb_ra;
wire [63:0] rb_q;
ovram #(6, 64) rbuf (.clk(clk), .we(rb_we), .wa(rb_wa), .wd(rb_wd), .ra(rb_ra), .q(rb_q));

// ------------------------------------------------------------------ the size of each frame on the stack
reg  [10:0] st_head = 0, st_tail = 0;
reg         st_we;
reg  [19:0] st_wd;
wire [19:0] st_q;
ovram #(11, 20) sizes (.clk(clk), .we(st_we), .wa(st_head), .wd(st_wd), .ra(st_tail), .q(st_q));

// ------------------------------------------------------------------ the stack
reg [AW-1:0] wp = 0;                           // the next word the DDR3 takes
reg   [AW:0] depth = 0;                        // words held (the FIFO's included)
reg   [19:0] fsize = 0;                        // words pushed since the last marker
reg   [15:0] serial = 0;

reg          rd_phase = 0;
reg [AW-1:0] rd_ptr;
reg    [7:0] rd_n;
assign ddr_addr     = DDR_BASE + {{(29-AW){1'b0}}, (rd_phase ? rd_ptr : wp)};
assign ddr_burstcnt = rd_phase ? rd_n : 8'd1;
assign ddr_din      = f_q;
assign ddr_be       = 8'hFF;

// ------------------------------------------------------------------ the machine
localparam [3:0] S_RUN = 0, S_DRAIN = 1, S_FETCH = 2, S_FREQ = 3, S_FWAIT = 4, S_PROC0 = 5, S_PROC1 = 6,
                 S_PEEK = 7, S_PREQ = 8, S_PWAIT = 9, S_LOAD = 10, S_INJ = 11, S_FAIL = 12;
reg    [3:0] state = S_RUN;
reg    [1:0] wst = 0;                          // the DDR3 writer: 0 idle, 1 reading the FIFO, 2 asking
reg    [8:0] ry_d = 0;
reg          seq_on = 0;
reg    [4:0] seq_c = 0;
reg          trim = 0, trim_rd = 0;
reg          flush_req = 0;

reg [AW-1:0] cur;                              // the stack is consumed down to here
reg   [AW:0] used;                             // words consumed in this step
reg    [6:0] n_blk;                            // words in the block read
reg    [5:0] idx;
reg    [6:0] got;
reg    [1:0] mleft;
reg          two;
reg    [4:0] skip;
reg [AW-1:0] sp_new;
reg    [5:0] inj_k;
reg    [2:0] inj_c;
reg          inj_go = 0;

wire         want  = enable & hold & ~block;
wire         jr_take = ~seq_on & jr_req;               // the journal word the FIFO takes this clock
wire         jc_take = ~seq_on & ~jr_req & jc_req;
wire         fb    = tick & (ry == LINE) & (ry_d != LINE);
wire  [AW:0] avail = depth - used;
wire  [63:0] seq_word =
	(seq_c == 5'd0)  ? cpu_o[63:0] :
	(seq_c == 5'd1)  ? cpu_o[127:64] :
	(seq_c == 5'd2)  ? {16'd0, cpu_o[175:128]} :
	(seq_c <  5'd8)  ? cia1_o[(seq_c - 5'd3) * 64 +: 64] :
	(seq_c <  5'd13) ? cia2_o[(seq_c - 5'd8) * 64 +: 64] :
	(seq_c <  5'd27) ? sh_q :
	                   {T_MARK, MAGIC, serial, 32'd0};

// the shadows' read address: a clock ahead of the word that is taken
always @(*) begin
	if (seq_on)       sh_ra = seq_c[3:0] - 4'd12;            // seq_c 12 -> word 0, taken at seq_c 13
	else case (inj_c)
		3'd0:    sh_ra = {1'b0, inj_k[5:3]};                 // the VIC-II's
		3'd1:    sh_ra = 4'd6  + {2'b00, inj_k[4:3]};        // SID 1's
		default: sh_ra = 4'd10 + {2'b00, inj_k[4:3]};        // SID 2's
	endcase
end

always @(posedge clk) begin
	reg [63:0] w;
	reg        enq, adv;

	f_we   <= 0;
	st_we  <= 0;
	rb_we  <= 0;
	sh_we  <= 0;
	ld     <= 0;
	col_we <= 0;
	sid_we <= 0;
	enq = 0;

	if (tick) ry_d <= ry;

	// ---------- the program's writes: the journal and the shadows
	if (jr_take) jr_req <= 0;
	if (jc_take) jc_req <= 0;
	if (a_do & a_main) begin
		if (jr_req & ~jr_take) ovf <= 1;
		jr_req  <= 1;
		jr_word <= {T_RAM, 36'd0, a_addr_r, qa};
	end
	if (io_wr & io_sel[3]) begin
		if (jc_req & ~jc_take) ovf <= 1;
		jc_req  <= 1;
		jc_word <= {T_COL, 46'd0, io_addr, col_old};
	end
	if (b_do) b_req <= 0;
	if (io_wr & io_sel[0]) begin
		if (io_addr[5:0] < 6'd48) begin
			sh_we <= 1; sh_lane <= 8'd1 << io_addr[2:0]; sh_wa <= {1'b0, io_addr[5:3]}; sh_wd <= {8{io_data}};
		end
	end
	else if (io_wr & io_sel[1]) begin
		sh_we <= 1; sh_lane <= 8'd1 << io_addr[2:0]; sh_wa <= 4'd6 + {2'b00, io_addr[4:3]}; sh_wd <= {8{io_data}};
		if (io_sel[2]) begin sh2_pend <= 1; sh2_addr <= io_addr[4:0]; sh2_data <= io_data; end
	end
	else if (io_wr & io_sel[2]) begin
		sh_we <= 1; sh_lane <= 8'd1 << io_addr[2:0]; sh_wa <= 4'd10 + {2'b00, io_addr[4:3]}; sh_wd <= {8{io_data}};
	end
	else if (sh2_pend) begin
		sh2_pend <= 0;
		sh_we <= 1; sh_lane <= 8'd1 << sh2_addr[2:0]; sh_wa <= 4'd10 + {2'b00, sh2_addr[4:3]}; sh_wd <= {8{sh2_data}};
	end

	// ---------- into the FIFO: the save state first, then the journal
	if (seq_on) begin
		if (!f_full) begin
			f_we <= 1; f_wd <= seq_word; enq = 1;
			if (seq_c == NW) begin
				seq_on  <= 0;
				serial  <= serial + 1'd1;
				st_we   <= 1;
				st_wd   <= (fsize == 20'hFFFFF) ? 20'hFFFFF : fsize + 20'd1;
				trim    <= 1;                          // (the table and the counts move on below)
			end
			seq_c <= seq_c + 1'd1;
		end
		else begin seq_on <= 0; ovf <= 1; end          // (never, with the DDR3 alive)
	end
	else if (jr_req) begin
		if (!f_full) begin f_we <= 1; f_wd <= jr_word; enq = 1; end else ovf <= 1;
	end
	else if (jc_req) begin
		if (!f_full) begin f_we <= 1; f_wd <= jc_word; enq = 1; end else ovf <= 1;
	end
	if (f_we) f_wp <= f_wp + 1'd1;
	if (enq) begin
		depth <= depth + 1'd1;
		if (fsize != 20'hFFFFF) fsize <= fsize + 1'd1;
	end
	if (st_we) begin                                   // a save state is complete
		st_head <= st_head + 1'd1;
		frames  <= frames + 1'd1;
		fsize   <= enq ? 20'd1 : 20'd0;
	end
	if (fsize == 20'hFFFFF || ovf) begin flush_req <= 1; ovf <= 0; end

	// ---------- FIFO to the DDR3, one word at a time
	case (wst)
		2'd0: if (f_cnt != 0 && !rd_phase) wst <= 2'd1;
		2'd1: begin ddr_we <= 1; wst <= 2'd2; end
		2'd2: if (!ddr_busy) begin
				ddr_we <= 0;
				f_rp   <= f_rp + 1'd1;
				wp     <= wp + 1'd1;
				wst    <= 2'd3;
			end
		2'd3: wst <= 2'd0;                             // (f_q moves to the next word)
	endcase
	f_cnt <= f_cnt + (f_we ? 9'd1 : 9'd0) - ((wst == 2'd2 && !ddr_busy) ? 9'd1 : 9'd0);

	// ---------- the oldest frames go when there are too many or the stack is nearly full
	if (trim && !st_we && !seq_on && state == S_RUN) begin
		if (frames > NF_MAX || (depth > LIMIT && frames != 0)) begin
			if (!trim_rd) trim_rd <= 1;                // (st_q is the oldest frame's size)
			else begin
				trim_rd <= 0;
				depth   <= depth - st_q + (enq ? 1'd1 : 1'd0);
				st_tail <= st_tail + 1'd1;
				frames  <= frames - 1'd1;
			end
		end
		else begin
			trim <= 0; trim_rd <= 0;
			if (depth > LIMIT) flush_req <= 1;
		end
	end

	// ---------- the steps
	case (state)
		S_RUN: begin
			if ((flush_req | block | ~enable) && !seq_on && !st_we && !trim) begin
				flush_req <= 0;
				frames    <= 0;
				depth     <= enq ? 1'd1 : 1'd0;
				fsize     <= enq ? 20'd1 : 20'd0;
				st_tail   <= st_head;
			end
			else if (fb && !seq_on && !trim) begin
				if (want && frames != 0 && !busy_dma) begin
					freeze <= 1;
					active <= 1;
					state  <= S_DRAIN;
				end
				else begin
					active <= 0;
					if (enable && !block && !flush_req) begin
						seq_on <= 1;
						seq_c  <= 0;
					end
				end
			end
		end

		// everything pushed so far must be in the DDR3 before it is read back
		S_DRAIN: if (f_cnt == 0 && wst == 0 && !f_we && !jr_req && !jc_req && !a_wpend && !sh2_pend && !seq_on) begin
			rd_phase <= 1;
			cur      <= wp;
			used     <= 0;
			two      <= (frames >= 12'd2);
			mleft    <= (frames >= 12'd2) ? 2'd2 : 2'd1;
			skip     <= 0;
			state    <= S_FETCH;
		end

		S_FETCH: begin
			if (avail == 0) state <= S_FAIL;
			else begin
				n_blk  <= (avail >= 64) ? 7'd64 : avail[6:0];
				rd_n   <= (avail >= 64) ? 8'd64 : {1'b0, avail[6:0]};
				rd_ptr <= cur - ((avail >= 64) ? {{(AW-7){1'b0}}, 7'd64} : {{(AW-7){1'b0}}, avail[6:0]});
				got    <= 0;
				ddr_rd <= 1;
				state  <= S_FREQ;
			end
		end
		S_FREQ: if (!ddr_busy) begin ddr_rd <= 0; state <= S_FWAIT; end
		S_FWAIT: begin
			if (got == n_blk) begin
				idx   <= n_blk[5:0] - 6'd1;
				rb_ra <= n_blk[5:0] - 6'd1;
				state <= S_PROC0;
			end
		end
		// a word a clock: rb_q is word idx, rb_ra runs one ahead
		S_PROC0: begin rb_ra <= idx - 6'd1; state <= S_PROC1; end
		S_PROC1: begin
			w = rb_q;
			begin
				adv = 1;
				if (skip != 0) skip <= skip - 1'd1;     // a save state passed over
				else if (w[63:60] == T_RAM) begin
					b_req <= 1; b_addr <= w[23:8]; b_data <= w[7:0];
				end
				else if (w[63:60] == T_COL) begin
					col_we <= 1; col_addr <= w[13:4]; col_data <= w[3:0];
				end
				else if (w[63:60] == T_MARK && w[59:48] == MAGIC) begin
					if (mleft == 2'd1) begin
						// the save state to go back to: it stays on the stack, with its marker
						sp_new <= rd_ptr + {{(AW-6){1'b0}}, idx} + 1'd1;
						state  <= S_PEEK;
						adv = 0;
					end
					else begin mleft <= mleft - 1'd1; skip <= NW; end
				end
				else begin state <= S_FAIL; adv = 0; end

				if (adv) begin
					used <= used + 1'd1;
					if (idx == 0) begin cur <= rd_ptr; state <= S_FETCH; end
					else begin idx <= idx - 1'd1; rb_ra <= idx - 6'd2; end
				end
			end
		end

		// the save state under the marker
		S_PEEK: begin
			if (!b_req) begin
				if (avail < NW + 1) state <= S_FAIL;
				else begin
					rd_n   <= NW;
					rd_ptr <= sp_new - 1'd1 - NW[AW-1:0];
					got    <= 0;
					ddr_rd <= 1;
					state  <= S_PREQ;
				end
			end
		end
		S_PREQ: if (!ddr_busy) begin ddr_rd <= 0; state <= S_PWAIT; end
		S_PWAIT: if (got == NW) state <= S_LOAD;
		S_LOAD: begin
			ld     <= 1;
			inj_k  <= 0;
			inj_go <= 0;
			state  <= S_INJ;
		end

		// the VIC-II's and the SIDs' registers back, one a C64 cycle; then on
		S_INJ: begin
			if (tick) begin
				if (inj_k < 6'd48) begin inj_go <= 1; inj_c <= 0; end
				else begin
					vic_we <= 0;
					if (inj_k == 6'd50) begin
						freeze   <= 0;
						rd_phase <= 0;
						wp       <= sp_new;
						depth    <= depth - used;
						fsize    <= 0;
						if (two) begin frames <= frames - 1'd1; st_head <= st_head - 1'd1; end
						state    <= S_RUN;
					end
					inj_k <= inj_k + 1'd1;
				end
			end
			else if (inj_go) begin
				inj_c <= inj_c + 1'd1;
				case (inj_c)
					3'd1: begin                        // sh_q: the VIC-II's word
						vic_addr <= inj_k;
						vic_data <= sh_q[inj_k[2:0]*8 +: 8];
						vic_we   <= (inj_k != 6'h19) && (inj_k < 6'd47);   // $D019 is not a register to put back
					end
					3'd2: begin                        // SID 1's
						sid_addr <= inj_k[4:0];
						sid_data <= sh_q[inj_k[2:0]*8 +: 8];
						sid_cs   <= 2'b01;
						sid_we   <= (inj_k < 6'd25);
					end
					3'd3: begin                        // SID 2's
						sid_data <= sh_q[inj_k[2:0]*8 +: 8];
						sid_cs   <= 2'b10;
						sid_we   <= (inj_k < 6'd25);
					end
					3'd4: begin inj_go <= 0; inj_k <= inj_k + 1'd1; end
					default: ;
				endcase
			end
		end

		// the stack was not as written: nothing more can be trusted - drop the history and go on
		S_FAIL: begin
			if (tick && !ddr_rd) begin
				err       <= 1;
				freeze    <= 0;
				rd_phase  <= 0;
				flush_req <= 1;
				state     <= S_RUN;
			end
		end
		default: state <= S_RUN;
	endcase

	// ---------- words coming back from the DDR3
	if (ddr_ready && rd_phase) begin
		got <= got + 1'd1;
		if (state == S_FWAIT || state == S_FREQ) begin
			rb_we <= 1; rb_wa <= got[5:0]; rb_wd <= ddr_dout;
		end
		else if (state == S_PWAIT || state == S_PREQ) begin
			case (got)
				7'd0: cpu_i[63:0]    <= ddr_dout;
				7'd1: cpu_i[127:64]  <= ddr_dout;
				7'd2: cpu_i[175:128] <= ddr_dout[47:0];
				7'd3, 7'd4, 7'd5, 7'd6, 7'd7:      cia1_i[(got - 7'd3) * 64 +: 64] <= ddr_dout;
				7'd8, 7'd9, 7'd10, 7'd11, 7'd12:   cia2_i[(got - 7'd8) * 64 +: 64] <= ddr_dout;
				default: begin
					sh_we <= 1; sh_lane <= 8'hFF; sh_wa <= got[3:0] - 4'd13; sh_wd <= ddr_dout;
				end
			endcase
		end
	end

	if (reset) begin
		state <= S_RUN; freeze <= 0; rd_phase <= 0; ddr_rd <= 0; seq_on <= 0; trim <= 0; trim_rd <= 0;
		flush_req <= 1; active <= 0; b_req <= 0; vic_we <= 0; inj_go <= 0; err <= 0;
		jr_req <= 0; jc_req <= 0; sh2_pend <= 0;
	end
end

endmodule


// The on-screen "REWIND" with the seconds held and a bar, top left, while rewinding.
// Like the drive overlay: a 3-bit colour (0 = see-through) for c64.sv's ovl_color.
module rewind_osd
(
	input            clk,
	input            ce,            // the C64's pixel (clk / 4)
	input            hblank,
	input            vblank,
	input            on,
	input            err,
	input     [11:0] frames,
	output reg [2:0] pixel_color = 0
);

// 5x7 letters: R E W I N D and the digits; a row is 5 bits, the left pixel first
function [4:0] glyph(input [3:0] ch, input [2:0] row);
	reg [34:0] g;
	begin
		case (ch)
			4'd0:  g = 35'b01110_10001_10011_10101_11001_10001_01110;   // 0
			4'd1:  g = 35'b00100_01100_00100_00100_00100_00100_01110;
			4'd2:  g = 35'b01110_10001_00001_00010_00100_01000_11111;
			4'd3:  g = 35'b11110_00001_00001_01110_00001_00001_11110;
			4'd4:  g = 35'b00010_00110_01010_10010_11111_00010_00010;
			4'd5:  g = 35'b11111_10000_11110_00001_00001_10001_01110;
			4'd6:  g = 35'b00110_01000_10000_11110_10001_10001_01110;
			4'd7:  g = 35'b11111_00001_00010_00100_01000_01000_01000;
			4'd8:  g = 35'b01110_10001_10001_01110_10001_10001_01110;
			4'd9:  g = 35'b01110_10001_10001_01111_00001_00010_01100;
			4'd10: g = 35'b11110_10001_10001_11110_10100_10010_10001;   // R
			4'd11: g = 35'b11111_10000_10000_11110_10000_10000_11111;   // E
			4'd12: g = 35'b10001_10001_10001_10101_10101_11011_10001;   // W
			4'd13: g = 35'b01110_00100_00100_00100_00100_00100_01110;   // I
			4'd14: g = 35'b10001_11001_10101_10011_10001_10001_10001;   // N
			default: g = 35'b11110_10001_10001_10001_10001_10001_11110; // D
		endcase
		glyph = g[(6 - row) * 5 +: 5];
	end
endfunction

reg  [9:0] x = 0, y = 0;
reg        old_hb = 0;
always @(posedge clk) begin
	if (hblank) x <= 0; else if (ce) x <= x + 1'd1;
	if (ce) old_hb <= hblank;
	if (vblank) y <= 0; else if (ce && old_hb && !hblank) y <= y + 1'd1;
end

// seconds = frames / 50 (x41 / 2048), two digits
wire [17:0] sx   = frames * 6'd41;
wire  [6:0] secs = sx[17:11];
wire  [3:0] tens = (secs >= 30) ? 4'd3 : (secs >= 20) ? 4'd2 : (secs >= 10) ? 4'd1 : 4'd0;
wire  [6:0] ones7 = secs - {tens, 3'd0} - {2'd0, tens, 1'd0};
wire  [3:0] ones = ones7[3:0];

// the box: 2x2 pixels a dot; the word at X0,Y0 - 9 characters of 6 dots; under it the bar, 54 dots
localparam X0 = 10'd40, Y0 = 10'd24;
wire [9:0] dx = x - X0, dy = y - Y0;
wire       in_txt = (x >= X0) && (dx < 10'd108) && (y >= Y0) && (dy < 10'd14);
wire       in_bar = (x >= X0) && (dx < 10'd108) && (y >= Y0 + 10'd18) && (dy < 10'd24);
wire [8:0] cdot   = dx[9:1];                       // dot across (0-53)
wire [3:0] cpos   = (cdot < 6) ? 4'd0 : (cdot < 12) ? 4'd1 : (cdot < 18) ? 4'd2 : (cdot < 24) ? 4'd3 :
                    (cdot < 30) ? 4'd4 : (cdot < 36) ? 4'd5 : (cdot < 42) ? 4'd6 : (cdot < 48) ? 4'd7 : 4'd8;
wire [8:0] cin    = cdot - {cpos, 2'd0} - {1'd0, cpos, 1'd0};      // dot within the character (0-5)
wire [3:0] ch     = (cpos == 0) ? 4'd10 : (cpos == 1) ? 4'd11 : (cpos == 2) ? 4'd12 : (cpos == 3) ? 4'd13 :
                    (cpos == 4) ? 4'd14 : (cpos == 5) ? 4'd15 : (cpos == 7) ? tens : ones;
wire [4:0] grow   = glyph(ch, dy[3:1]);
wire       txt_px = in_txt && (cpos != 6) && (cin < 5) && grow[4 - cin[2:0]];
// the bar: 108 pixels for NF_MAX frames (frames / 14.2: x9 / 128)
wire [15:0] bx    = frames * 4'd9;
wire  [8:0] blen  = bx[15:7];
wire       edge_px = in_bar && (dx == 0 || dx == 10'd107 || dy == 10'd18 || dy == 10'd23);
wire       fill_px = in_bar && ({1'b0, dx[7:0]} < blen);

always @(posedge clk) if (ce) begin
	pixel_color <= 0;
	if (on) begin
		if (txt_px | edge_px) pixel_color <= err ? 3'd4 : 3'd7;      // white (red: the history was dropped)
		else if (fill_px)     pixel_color <= 3'd2;                   // green
	end
end

endmodule
