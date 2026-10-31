// =====================================================================================
//  OctoVIC - the Octophonic 64's graphics chip (see docs/OCTOVIC.md)
//
//  Draws two tile layers and 128 sprites out of 16MB of VRAM in the DDR3, a raster line at a
//  time into a four-line buffer up to three lines ahead of the beam, and puts the VIC's own
//  picture in front of it (see-through where it is the KEY colour) or behind it.
//
//  The renderer asks for 64-bit words (one at a time, pipelined); the answers come back in
//  order with a tag saying what each one is for, and the consumer turns them into map
//  entries, sprite table entries or pixels (one a clock, through the palette, into the line
//  buffer). The display side reads the buffer as the VIC puts out each pixel, and clears it.
//
//  Version 2 adds: a maths unit (multiply, divide), a blitter (copy, fill, skip-0 copy, line) that
//  works in the VRAM on its own, sprite collisions (sprite-sprite, sprite-layer), and an
//  interrupt (a raster line, the collisions, the blitter finished); a bitmap layer turned and
//  sized (each line's pixels walked across the picture at any angle and scale); see-through colours (a layer's
//  or a sprite's pixels mixed with what is under them: half and half, added, taken away).
// =====================================================================================
module octovic
(
	input             clk,
	input             reset,

	// the 6510's bus: $D600-$D6FF once unlocked
	input             cs,
	input             wr,          // a pulse: din to register addr
	input             rd,          // a pulse: the CPU is reading register addr (its side effects come later)
	input       [7:0] addr,
	input       [7:0] din,
	output reg  [7:0] dout,

	// the VIC
	input             pix_en,      // the VIC's pixel strobe
	input       [9:0] vic_x,       // its raster X at the strobe (the pixel coming out)
	input       [8:0] vic_y,       // its raster line
	input       [3:0] vic_index,   // the pixel's colour (valid the clock after the strobe)
	input      [23:0] vic_rgb,     // that colour through the core's palette
	output reg [23:0] rgb,         // the picture

	// the DDR3 (Avalon)
	output reg [28:0] ddr_addr,
	output      [7:0] ddr_burstcnt,
	output reg        ddr_rd,
	output reg        ddr_we,
	output reg [63:0] ddr_din,
	output reg  [7:0] ddr_be,
	input             ddr_busy,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,

	output            irq          // version 2: the interrupt, high while any enabled flag is set
);

localparam [28:0] VBASE = 29'h06400000;        // byte $32000000
localparam RW = 396;                           // pixels drawn a line: raster X 0-395 (x -32..363)
localparam FIRST = 16, LAST = 299;             // raster lines drawn

assign ddr_burstcnt = 8'd1;

// ---------------------------------------------------------------------------------
//  REGISTERS
// ---------------------------------------------------------------------------------
reg  [23:0] vaddr;
reg   [7:0] vinc;
reg   [7:0] ctrl;
reg   [3:0] key;
reg   [7:0] xadj, yadj;
reg         copen;
reg   [7:0] sprcount;
reg  [23:0] copbase, satbase, sprgfx;
// the animation: every DIV frames the copper list and the sprite table move on by STEP, for
// STEPS steps, then start again - a day going by, a ship flying past, with no 6510 at all
reg  [23:0] copstep, satstep;
reg  [15:0] copsteps, satsteps;
reg   [7:0] copdiv, satdiv;
reg         anim_rst;               // (any of them, or COPBASE / SATBASE, written: from the start)
reg  [23:0] cop_off, sat_off;
reg  [15:0] cop_k, sat_k;
reg   [7:0] cop_d, sat_d;
reg  [23:0] sat_fr;                 // the sprite table this frame copies
reg   [1:0] palsel;
reg   [7:0] palidx, palr, palg;
reg   [7:0] lctrl[2];
reg   [7:0] lmode[2];               // version 2: b0-1 how the layer's pixels mix with what is under them,
                                    //   b2 turned and sized (a bitmap layer), b3 nothing outside the picture
reg  [31:0] af_u0, af_v0, af_dux, af_dvx, af_duy, af_dvy;   // version 2: turning and sizing, 16.16
reg  [23:0] mapbase[2], tilebase[2], lsbase[2];
reg  [15:0] scrollx[2], scrolly[2];
reg  [23:0] vpal[16];
reg  [23:0] backdrop;
reg   [7:0] frame;
reg   [7:0] vrd_data;
// version 2 -------------------------------------------------------------------------
// the maths unit
reg  [15:0] mula, mulb;
reg   [7:0] mathctl;
reg  [31:0] divn, divq;
reg  [15:0] divd, divr;
reg         div_busy;
reg   [5:0] div_cnt;
reg  [16:0] div_rem;                // (17 bits: the compare)
wire signed [31:0] mul_s = $signed(mula) * $signed(mulb);
wire        [31:0] mul_u = {16'd0, mula} * {16'd0, mulb};
wire        [31:0] mulr  = mathctl[0] ? mul_s : mul_u;
// the blitter's registers
reg  [23:0] bsrc, bdst;
reg  [15:0] bw, bh, bss, bds;
reg   [7:0] bfill;
reg   [1:0] bop;
reg  [15:0] lx0, ly0, lx1, ly1;
reg         blt_go;                 // a pulse: start
wire        blt_busy;
wire        blt_done;               // a pulse from the blitter
// the interrupt
reg   [8:0] irqline;
reg   [3:0] irqen, irqst;           // b0 raster line, b1 sprite-sprite, b2 sprite-layer, b3 blitter done
reg   [8:0] irq_prev_y;
reg   [3:0] collidx;
reg         coll_new;               // a pulse from the consumer: last frame's collisions latched
reg [127:0] coll_ss, coll_sl;       // last frame's collisions: sprite-sprite, sprite-layer
assign irq = |(irqst & irqen);

wire ENABLE  = ctrl[0];
wire VICPAL  = ctrl[1];
wire VICBACK = ctrl[2];
wire KEYEN   = ctrl[3];

// the palette: written by the registers, read by the consumer
reg         pal_we;
reg   [7:0] pal_wa;
reg  [23:0] pal_wd;

integer ii;

// the VIC's colours (Pepto), for VICPAL until a program sets its own
function [23:0] c64col(input [3:0] i);
	case (i)
		0: c64col = 24'h000000;  1: c64col = 24'hFFFFFF;  2: c64col = 24'h68372B;  3: c64col = 24'h70A4B2;
		4: c64col = 24'h6F3D86;  5: c64col = 24'h588D43;  6: c64col = 24'h352879;  7: c64col = 24'hB8C76F;
		8: c64col = 24'h6F4F25;  9: c64col = 24'h433900; 10: c64col = 24'h9A6759; 11: c64col = 24'h444444;
	   12: c64col = 24'h6C6C6C; 13: c64col = 24'h9AD284; 14: c64col = 24'h6C5EB5; 15: c64col = 24'h959595;
	endcase
endfunction

// the write FIFO: CPU bytes for the VRAM
(* ramstyle = "MLAB, no_rw_check" *) reg  [31:0] wf[16];
reg   [3:0] wf_r, wf_w;
wire        wf_empty = wf_r == wf_w;
wire        wf_full  = (wf_w + 4'd1) == wf_r;

reg         pf_req;            // a VDATA read wanted (VADDR set or moved on)
reg   [4:0] rd_delay;          // a CPU read of VDATA: its side effect half a microsecond on

// register writes: the CPU's, or the copper's when the CPU has none this clock
wire        cpu_w = cs & wr;
reg         cop_w;             // from the renderer
reg   [7:0] cop_wa, cop_wd;
wire        cop_take = cop_w & ~cpu_w;
wire        rw_en = cpu_w | cop_w;
wire  [7:0] rw_a  = cpu_w ? addr : cop_wa;
wire  [7:0] rw_d  = cpu_w ? din  : cop_wd;
wire        rw_cpu = cpu_w;

always @(posedge clk) begin
	pal_we <= 0;
	anim_rst <= 0;
	if (reset) begin
		copstep <= 0; satstep <= 0; copsteps <= 0; satsteps <= 0; copdiv <= 0; satdiv <= 0; anim_rst <= 1;
		vaddr <= 0; vinc <= 1; ctrl <= 0; key <= 0; xadj <= 0; yadj <= 0; copen <= 0; sprcount <= 0;
		copbase <= 0; satbase <= 0; sprgfx <= 0; palsel <= 0; palidx <= 0; palr <= 0; palg <= 0;
		lctrl[0] <= 0; lctrl[1] <= 0; lmode[0] <= 0; lmode[1] <= 0;
		af_u0 <= 0; af_v0 <= 0; af_dux <= 32'h10000; af_dvx <= 0; af_duy <= 0; af_dvy <= 32'h10000; scrollx[0] <= 0; scrollx[1] <= 0; scrolly[0] <= 0; scrolly[1] <= 0;
		mapbase[0] <= 0; mapbase[1] <= 0; tilebase[0] <= 0; tilebase[1] <= 0; lsbase[0] <= 0; lsbase[1] <= 0;
		for (ii = 0; ii < 16; ii = ii + 1) vpal[ii] <= c64col(ii[3:0]);
		backdrop <= 0;
		wf_w <= 0; pf_req <= 0; rd_delay <= 0;
		mula <= 0; mulb <= 0; mathctl <= 0; divn <= 0; divd <= 0; divq <= 0; divr <= 0; div_busy <= 0;
		bsrc <= 0; bdst <= 0; bw <= 0; bh <= 0; bss <= 0; bds <= 0; bfill <= 0; bop <= 0; blt_go <= 0;
		lx0 <= 0; ly0 <= 0; lx1 <= 0; ly1 <= 0;
		irqline <= 0; irqen <= 0; irqst <= 0; irq_prev_y <= 0; collidx <= 0;
	end
	else begin
		blt_go <= 0;
		if (pf_clr) pf_req <= 0;
		// the divider: a bit a clock, 32 clocks (done before the CPU can look: a microsecond is 32 clocks)
		if (div_busy) begin
			reg [16:0] r2;
			r2 = {div_rem[15:0], divq[31]};
			if (r2 >= {1'b0, divd}) begin div_rem <= r2 - {1'b0, divd}; divq <= {divq[30:0], 1'b1}; end
			else begin div_rem <= r2; divq <= {divq[30:0], 1'b0}; end
			div_cnt <= div_cnt - 6'd1;
			if (div_cnt == 6'd1) begin
				div_busy <= 0;
				divr <= (r2 >= {1'b0, divd}) ? (r2[15:0] - divd) : r2[15:0];
			end
		end
		// the interrupt's flags
		irq_prev_y <= vic_y;
		if (vic_y != irq_prev_y && vic_y == irqline) irqst[0] <= 1;
		if (coll_new && coll_ss != 0) irqst[1] <= 1;
		if (coll_new && coll_sl != 0) irqst[2] <= 1;
		if (blt_done) irqst[3] <= 1;
		// a CPU read of VDATA: on, half a microsecond later (the CPU has the byte by then)
		if (cs & rd & addr == 8'h04) rd_delay <= 5'd16;
		else if (rd_delay != 0) begin
			rd_delay <= rd_delay - 5'd1;
			if (rd_delay == 5'd1) begin vaddr <= vaddr + {16'd0, vinc}; pf_req <= 1; end
		end
		if (rw_en) begin
			if ((rw_a >= 8'h10 && rw_a <= 8'h15) || (rw_a >= 8'h40 && rw_a <= 8'h4B)) anim_rst <= 1;
			case (rw_a)
				8'h00: if (rw_cpu) begin vaddr[7:0]   <= rw_d; pf_req <= 1; end
				8'h01: if (rw_cpu) begin vaddr[15:8]  <= rw_d; pf_req <= 1; end
				8'h02: if (rw_cpu) begin vaddr[23:16] <= rw_d; pf_req <= 1; end
				8'h03: if (rw_cpu) vinc <= rw_d;
				8'h04: if (rw_cpu & ~wf_full) begin
						wf[wf_w] <= {vaddr, rw_d}; wf_w <= wf_w + 4'd1;
						vaddr <= vaddr + {16'd0, vinc}; pf_req <= 1;
					end
				8'h05: ctrl <= rw_d;
				8'h06: key <= rw_d[3:0];
				8'h0C: xadj <= rw_d;
				8'h0D: yadj <= rw_d;
				8'h0E: copen <= rw_d[0];
				8'h0F: sprcount <= (rw_d > 8'd128) ? 8'd128 : rw_d;
				8'h10: copbase[7:0] <= rw_d;  8'h11: copbase[15:8] <= rw_d;  8'h12: copbase[23:16] <= rw_d;
				8'h13: satbase[7:0] <= rw_d;  8'h14: satbase[15:8] <= rw_d;  8'h15: satbase[23:16] <= rw_d;
				8'h40: copstep[7:0]   <= rw_d;  8'h41: copstep[15:8]  <= rw_d;  8'h42: copstep[23:16]  <= rw_d;
				8'h43: copsteps[7:0]  <= rw_d;  8'h44: copsteps[15:8] <= rw_d;  8'h45: copdiv <= rw_d;
				8'h46: satstep[7:0]   <= rw_d;  8'h47: satstep[15:8]  <= rw_d;  8'h48: satstep[23:16]  <= rw_d;
				8'h49: satsteps[7:0]  <= rw_d;  8'h4A: satsteps[15:8] <= rw_d;  8'h4B: satdiv <= rw_d;
				8'h16: sprgfx[7:0]  <= rw_d;  8'h17: sprgfx[15:8]  <= rw_d;  8'h18: sprgfx[23:16]  <= rw_d;
				8'h19: palsel <= rw_d[1:0];
				8'h1A: palidx <= rw_d;
				8'h1B: palr <= rw_d;
				8'h1C: palg <= rw_d;
				8'h1D: begin
						case (palsel)
							0: begin pal_we <= 1; pal_wa <= palidx; pal_wd <= {palr, palg, rw_d}; end
							1: vpal[palidx[3:0]] <= {palr, palg, rw_d};
							default: backdrop <= {palr, palg, rw_d};
						endcase
						palidx <= palidx + 8'd1;
					end
				8'h20, 8'h30: lctrl[rw_a[4]] <= rw_d;
				8'h2F, 8'h3F: lmode[rw_a[4]] <= rw_d;
				8'h21, 8'h31: mapbase[rw_a[4]][7:0]   <= rw_d;
				8'h22, 8'h32: mapbase[rw_a[4]][15:8]  <= rw_d;
				8'h23, 8'h33: mapbase[rw_a[4]][23:16] <= rw_d;
				8'h24, 8'h34: tilebase[rw_a[4]][7:0]   <= rw_d;
				8'h25, 8'h35: tilebase[rw_a[4]][15:8]  <= rw_d;
				8'h26, 8'h36: tilebase[rw_a[4]][23:16] <= rw_d;
				8'h28, 8'h38: scrollx[rw_a[4]][7:0]  <= rw_d;
				8'h29, 8'h39: scrollx[rw_a[4]][15:8] <= rw_d;
				8'h2A, 8'h3A: scrolly[rw_a[4]][7:0]  <= rw_d;
				8'h2B, 8'h3B: scrolly[rw_a[4]][15:8] <= rw_d;
				8'h2C, 8'h3C: lsbase[rw_a[4]][7:0]   <= rw_d;
				8'h2D, 8'h3D: lsbase[rw_a[4]][15:8]  <= rw_d;
				8'h2E, 8'h3E: lsbase[rw_a[4]][23:16] <= rw_d;
				// version 2
				8'h50: mula[7:0] <= rw_d;  8'h51: mula[15:8] <= rw_d;
				8'h52: mulb[7:0] <= rw_d;  8'h53: mulb[15:8] <= rw_d;
				8'h58: mathctl <= rw_d;
				8'h59: divn[7:0] <= rw_d;  8'h5A: divn[15:8] <= rw_d;  8'h5B: divn[23:16] <= rw_d;  8'h5C: divn[31:24] <= rw_d;
				8'h5D: divd[7:0] <= rw_d;
				8'h5E: begin
						divd[15:8] <= rw_d;
						if ({rw_d, divd[7:0]} == 16'd0) begin divq <= 32'hFFFFFFFF; divr <= divn[15:0]; div_busy <= 0; end
						else begin divq <= divn; div_rem <= 0; div_cnt <= 6'd32; div_busy <= 1; end
					end
				8'h66: lx0[7:0] <= rw_d;  8'h67: lx0[15:8] <= rw_d;  8'h68: ly0[7:0] <= rw_d;  8'h69: ly0[15:8] <= rw_d;
				8'h6A: lx1[7:0] <= rw_d;  8'h6B: lx1[15:8] <= rw_d;  8'h6C: ly1[7:0] <= rw_d;  8'h6D: ly1[15:8] <= rw_d;
				8'h70: bsrc[7:0] <= rw_d;  8'h71: bsrc[15:8] <= rw_d;  8'h72: bsrc[23:16] <= rw_d;
				8'h73: bdst[7:0] <= rw_d;  8'h74: bdst[15:8] <= rw_d;  8'h75: bdst[23:16] <= rw_d;
				8'h76: bw[7:0] <= rw_d;    8'h77: bw[15:8] <= rw_d;
				8'h78: bh[7:0] <= rw_d;    8'h79: bh[15:8] <= rw_d;
				8'h7A: bss[7:0] <= rw_d;   8'h7B: bss[15:8] <= rw_d;
				8'h7C: bds[7:0] <= rw_d;   8'h7D: bds[15:8] <= rw_d;
				8'h7E: bfill <= rw_d;
				8'h7F: begin bop <= rw_d[2:1]; if (rw_d[0] && !blt_busy) blt_go <= 1; end
				8'h80: irqline[7:0] <= rw_d;  8'h81: irqline[8] <= rw_d[0];
				8'h82: irqen <= rw_d[3:0];
				8'h83: irqst <= irqst & ~rw_d[3:0];
				8'h84: collidx <= rw_d[3:0];
				8'h88: af_u0[7:0]   <= rw_d;  8'h89: af_u0[15:8]   <= rw_d;  8'h8A: af_u0[23:16]   <= rw_d;  8'h8B: af_u0[31:24]   <= rw_d;
				8'h8C: af_v0[7:0]   <= rw_d;  8'h8D: af_v0[15:8]   <= rw_d;  8'h8E: af_v0[23:16]   <= rw_d;  8'h8F: af_v0[31:24]   <= rw_d;
				8'h90: af_dux[7:0]  <= rw_d;  8'h91: af_dux[15:8]  <= rw_d;  8'h92: af_dux[23:16]  <= rw_d;  8'h93: af_dux[31:24]  <= rw_d;
				8'h94: af_dvx[7:0]  <= rw_d;  8'h95: af_dvx[15:8]  <= rw_d;  8'h96: af_dvx[23:16]  <= rw_d;  8'h97: af_dvx[31:24]  <= rw_d;
				8'h98: af_duy[7:0]  <= rw_d;  8'h99: af_duy[15:8]  <= rw_d;  8'h9A: af_duy[23:16]  <= rw_d;  8'h9B: af_duy[31:24]  <= rw_d;
				8'h9C: af_dvy[7:0]  <= rw_d;  8'h9D: af_dvy[15:8]  <= rw_d;  8'h9E: af_dvy[23:16]  <= rw_d;  8'h9F: af_dvy[31:24]  <= rw_d;
				default: ;
			endcase
		end
	end
end

// reading
always @(*) begin
	case (addr)
		8'h00: dout = vaddr[7:0];   8'h01: dout = vaddr[15:8];  8'h02: dout = vaddr[23:16];
		8'h03: dout = vinc;         8'h04: dout = vrd_data;     8'h05: dout = ctrl;
		8'h06: dout = {4'd0, key};  8'h08: dout = {5'd0, blt_busy, div_busy, ~wf_empty};
		8'h09: dout = vic_y[7:0];   8'h0A: dout = {7'd0, vic_y[8]};  8'h0B: dout = frame;
		8'h0C: dout = xadj;         8'h0D: dout = yadj;          8'h0E: dout = {7'd0, copen};
		8'h0F: dout = sprcount;     8'h19: dout = {6'd0, palsel}; 8'h1A: dout = palidx;
		8'h1E: dout = 8'h8C;        8'h1F: dout = 8'h02;
		8'h50: dout = mula[7:0];    8'h51: dout = mula[15:8];    8'h52: dout = mulb[7:0];    8'h53: dout = mulb[15:8];
		8'h54: dout = mulr[7:0];    8'h55: dout = mulr[15:8];    8'h56: dout = mulr[23:16];  8'h57: dout = mulr[31:24];
		8'h58: dout = mathctl;
		8'h60: dout = divq[7:0];    8'h61: dout = divq[15:8];    8'h62: dout = divq[23:16];  8'h63: dout = divq[31:24];
		8'h64: dout = divr[7:0];    8'h65: dout = divr[15:8];
		8'h7F: dout = {blt_busy, 4'd0, bop, 1'b0};
		8'h80: dout = irqline[7:0]; 8'h81: dout = {7'd0, irqline[8]};
		8'h82: dout = {4'd0, irqen}; 8'h83: dout = {4'd0, irqst};
		8'h84: dout = {4'd0, collidx};
		8'h85: dout = coll_ss[collidx*8 +: 8];
		8'h86: dout = coll_sl[collidx*8 +: 8];
		8'h20, 8'h30: dout = lctrl[addr[4]];
		8'h2F, 8'h3F: dout = lmode[addr[4]];
		8'h28, 8'h38: dout = scrollx[addr[4]][7:0];  8'h29, 8'h39: dout = scrollx[addr[4]][15:8];
		8'h2A, 8'h3A: dout = scrolly[addr[4]][7:0];  8'h2B, 8'h3B: dout = scrolly[addr[4]][15:8];
		default: dout = 8'hFF;
	endcase
end

// ---------------------------------------------------------------------------------
//  THE DDR3 PORT: VRAM writes first, then the CPU's VDATA fetch, then the renderer's reads
// ---------------------------------------------------------------------------------
localparam K_MAP = 3'd0, K_TILE = 3'd1, K_SPR = 3'd2, K_SAT = 3'd3, K_LS = 3'd4, K_COP = 3'd5, K_VRD = 3'd6, K_BLT = 3'd7;

// a tag: kind[2:0], then per kind -
//   MAP:  [8:3] first entry, [10:9] its lane
//   TILE: [12:3] raster X of pixel 0 (signed), [13] flip, [14] high half, [18:15] bank, [19] 256 colours
//   SPR:  [18:3] raster X of the sprite's pixel 0 (signed), [20:19] width, [21] flip, [22] high half,
//         [26:23] bank, [27] 256 colours, [33:28] the word's first sprite pixel, [40:34] the sprite
//   TILE and SPR: [42:41] how the pixels mix (0 over, 1 half and half, 2 added, 3 taken away)
//   TILE, turned and sized (version 2): [20] set, [22:21] pixels in the word less 1, [34:23] each
//         one's byte in the word (3 bits each), [12:3] the first one's place on the line
//   SAT:  [9:3] the sprite    LS: [4:3] lane    VRD: [5:3] byte    BLT: (the blitter's word)
localparam TW = 43;

// the renderer's requests: a little FIFO, so it can ask once a clock
reg    [20:0] rqf_w[4];
reg  [TW-1:0] rqf_t[4];
reg     [2:0] rqf_wp, rqf_rp;
wire          rqf_empty = rqf_wp == rqf_rp;
wire          rqf_full  = (rqf_wp - rqf_rp) == 3'd4;
reg           pf_clr;
// version 2: the blitter's requests - held until taken (ack), dropped by the blitter when it sees the ack
reg           blt_rreq, blt_rack, blt_wreq, blt_wack;
reg    [20:0] blt_raddr;
reg    [23:0] blt_waddr;
reg     [7:0] blt_wdata;
reg    [63:0] blt_rdata;
reg           blt_got;
reg           blt_got_clr;     // from the blitter: it has the word

reg  [TW-1:0] cmd_tag;
(* ramstyle = "MLAB, no_rw_check" *) reg  [TW-1:0] tf[32];          // the tags of the reads on their way, in order
reg     [4:0] tf_r, tf_w;
reg     [5:0] outstanding;     // reads asked for, not yet answered
reg     [5:0] df_count;        // answers waiting for the consumer
wire          room = (outstanding + df_count) < 6'd30;

wire accepted_rd = ddr_rd & ~ddr_busy;
wire port_free   = ~(ddr_rd | ddr_we) | ~ddr_busy;

always @(posedge clk) begin
	pf_clr <= 0;
	if (reset) begin
		ddr_rd <= 0; ddr_we <= 0; wf_r <= 0; tf_w <= 0; rqf_rp <= 0; blt_wack <= 0; blt_rack <= 0;
	end
	else begin
		if (accepted_rd) begin tf[tf_w] <= cmd_tag; tf_w <= tf_w + 5'd1; end
		if (port_free) begin
			ddr_rd <= 0; ddr_we <= 0;
			if (!wf_empty) begin
				ddr_addr <= VBASE + {8'd0, wf[wf_r][31:11]};
				ddr_din  <= {8{wf[wf_r][7:0]}};
				ddr_be   <= 8'd1 << wf[wf_r][10:8];
				ddr_we   <= 1;
				wf_r     <= wf_r + 4'd1;
			end
			else if (pf_req && !pf_clr && room) begin
				ddr_addr <= VBASE + {8'd0, vaddr[23:3]};
				cmd_tag  <= {{(TW-6){1'b0}}, vaddr[2:0], K_VRD};
				ddr_rd   <= 1;
				pf_clr   <= 1;
			end
			else if (!rqf_empty && room) begin
				ddr_addr <= VBASE + {8'd0, rqf_w[rqf_rp[1:0]]};
				cmd_tag  <= rqf_t[rqf_rp[1:0]];
				ddr_rd   <= 1;
				rqf_rp   <= rqf_rp + 3'd1;
			end
			else if (blt_wreq && !blt_wack) begin           // version 2: the blitter, when nothing else wants the port
				ddr_addr <= VBASE + {8'd0, blt_waddr[23:3]};
				ddr_din  <= {8{blt_wdata}};
				ddr_be   <= 8'd1 << blt_waddr[2:0];
				ddr_we   <= 1;
				blt_wack <= 1;
			end
			else if (blt_rreq && !blt_rack && room) begin
				ddr_addr <= VBASE + {8'd0, blt_raddr};
				cmd_tag  <= {{(TW-3){1'b0}}, K_BLT};
				ddr_rd   <= 1;
				blt_rack <= 1;
			end
		end
		if (!blt_wreq) blt_wack <= 0;
		if (!blt_rreq) blt_rack <= 0;
	end
end

// the answers: into a FIFO with their tags
(* ramstyle = "MLAB, no_rw_check" *) reg  [63:0]   df_d[32];
(* ramstyle = "MLAB, no_rw_check" *) reg [TW-1:0]  df_t[32];
reg   [4:0]   df_r, df_w;
wire          df_pop;
always @(posedge clk) begin
	if (reset) begin
		outstanding <= 0; df_w <= 0; tf_r <= 0; df_count <= 0;
	end
	else begin
		outstanding <= outstanding + (accepted_rd ? 6'd1 : 6'd0) - (ddr_dout_ready ? 6'd1 : 6'd0);
		df_count    <= df_count + (ddr_dout_ready ? 6'd1 : 6'd0) - (df_pop ? 6'd1 : 6'd0);
		if (ddr_dout_ready) begin
			df_d[df_w] <= ddr_dout; df_t[df_w] <= tf[tf_r];
			df_w <= df_w + 5'd1; tf_r <= tf_r + 5'd1;
		end
	end
end

// ---------------------------------------------------------------------------------
//  THE LINE BUFFER: four lines of 512 pixels {opaque, rgb}, in four banks by raster X mod 4, so
//  four neighbouring pixels go in at once. A line's slot is cleared (99 clocks, the four banks
//  together) before it is drawn; the one write port does both.
// ---------------------------------------------------------------------------------
reg         bw_we[4];          // the consumer's writes, a bank each
reg   [8:0] bw_a[4];
reg  [23:0] bw_d[4];
reg         clr_we;            // the renderer clearing a slot
reg   [8:0] clr_a;
reg   [1:0] d_bank;            // the display's pixel: its bank
reg  [24:0] lb_q[4];

genvar gb;
generate
	for (gb = 0; gb < 4; gb = gb + 1) begin : bank
		wire [24:0] q;
		ovram #(.AW(9), .DW(25)) lbm
		(
			.clk(clk),
			.we(clr_we | bw_we[gb]),
			.wa(clr_we ? clr_a : bw_a[gb]),
			.wd(clr_we ? 25'd0 : {1'b1, bw_d[gb]}),
			.ra({vic_y[1:0], vic_x[8:2]}),
			.q(q)
		);
		always @(*) lb_q[gb] = q;
	end
endgenerate

// the backdrop as it was when each line was drawn (the copper changes it a line at a time)
reg [23:0] bdl[4];
// and CTRL and KEY: a copper split lands on its own line, not up to three lines early
reg  [3:0] cdl[4];
reg  [3:0] kdl[4];

// the display: the VIC's pixel and ours
reg        d1;                 // the clock after the strobe
reg        d1_in;              // that pixel is in what we draw
reg  [1:0] d_slot;
always @(posedge clk) begin
	d1 <= pix_en;
	if (pix_en) begin
		d_bank <= vic_x[1:0];
		d_slot <= vic_y[1:0];
		d1_in  <= (vic_x < RW) && (vic_y >= FIRST) && (vic_y <= LAST);
	end
	if (d1) begin
		reg [23:0] vc;
		reg [24:0] q;
		reg        op;
		reg  [3:0] c;
		c  = cdl[d_slot];
		vc = c[1] ? vpal[vic_index] : vic_rgb;
		q  = lb_q[d_bank];
		op = d1_in & q[24];
		if (!c[0])                                  rgb <= vc;
		else if (c[2])                              rgb <= op ? q[23:0] : vc;
		else if (c[3] && vic_index == kdl[d_slot])  rgb <= op ? q[23:0] : bdl[d_slot];
		else                                        rgb <= vc;
	end
end

// ---------------------------------------------------------------------------------
//  THE SPRITE TABLE: copied in from VRAM once a frame
// ---------------------------------------------------------------------------------
reg         sat_we;
reg   [6:0] sat_wa;
reg  [63:0] sat_wd;
reg   [6:0] sat_ra;
wire [63:0] sat_q;
ovram #(.AW(7), .DW(64)) satm(.clk(clk), .we(sat_we), .wa(sat_wa), .wd(sat_wd), .ra(sat_ra), .q(sat_q));

// the map entries of the layer being drawn: in four banks (entry i in bank i mod 4), so a
// word's four entries go in at once
reg         ent_we[4];
reg   [3:0] ent_wa[4];
reg  [15:0] ent_wd[4];
wire [15:0] ent_q[4];
reg   [5:0] ti, nt;             // the renderer's tiles: which, how many
generate
	for (gb = 0; gb < 4; gb = gb + 1) begin : entb
		(* ramstyle = "MLAB, no_rw_check" *) reg [15:0] m[16];
		always @(posedge clk) if (ent_we[gb]) m[ent_wa[gb]] <= ent_wd[gb];
		assign ent_q[gb] = m[ti[5:2]];
	end
endgenerate

// ---------------------------------------------------------------------------------
//  THE CONSUMER: answers into map entries, the sprite table, the copper - or pixels, four a clock
// ---------------------------------------------------------------------------------
reg          c_busy;           // in a run of pixels
reg   [63:0] c_d;
reg [TW-1:0] c_t;
reg    [1:0] c_g, c_ng;        // the group of four, and the last group
reg   [15:0] ls_val;
reg          ls_got;
reg   [63:0] cop_word;
reg          cop_got;
reg          p_v[4];
reg    [8:0] p_a[4];
reg    [1:0] p_b[4];
reg    [8:0] slot_base;        // the line being drawn: its slot, as the top of a bank address
reg    [7:0] map_done;
reg          p_spr[4];         // version 2: a sprite's pixel (else a layer's), and which sprite
reg    [1:0] p_m[4];           // version 2: how it mixes
reg    [6:0] p_id[4];
// version 2: THE OWNER BUFFER - beside the line buffer, for each pixel of the line being drawn:
// {drawn, its colour, a layer pixel is there, a sprite pixel is there, which sprite} - a copy
// of the line buffer the drawing side can read, so a see-through pixel can be mixed with what is
// under it. Each pixel written looks at
// what was there first: a sprite over a sprite, a sprite over a layer or a layer over a sprite
// is a collision, kept for the frame.
reg          o_v[4], o_spr[4]; // stage 3, by bank: the pixel written, its writer
reg    [6:0] o_id[4];
reg    [1:0] o_m[4];            // how it mixes
reg   [23:0] o_rgb[4];          // its colour
reg    [8:0] o_a[4];
reg          ow_we[4];
reg    [8:0] ow_a[4];
reg   [33:0] ow_d[4];
reg          ow2_we[4];        // the write before (the RAM gives the old value for two clocks: those
reg    [8:0] ow2_a[4];         // two writes are passed straight on to a pixel at the same place)
reg   [33:0] ow2_d[4];
reg    [8:0] own_ra[4];
wire  [33:0] own_q[4];
reg  [127:0] acc_ss, acc_sl;   // this frame's collisions so far
reg          coll_latch;       // from the renderer: a frame begins
generate
	for (gb = 0; gb < 4; gb = gb + 1) begin : ownb
		ovram #(.AW(9), .DW(34)) om
		(
			.clk(clk),
			.we(clr_we | ow_we[gb]),
			.wa(clr_we ? clr_a : ow_a[gb]),
			.wd(clr_we ? 34'd0 : ow_d[gb]),
			.ra(own_ra[gb]),
			.q(own_q[gb])
		);
	end
endgenerate
always @(*) begin
	integer k, b;
	for (b = 0; b < 4; b = b + 1) own_ra[b] = 9'd0;
	for (k = 0; k < 4; k = k + 1) own_ra[p_b[k]] = p_a[k];
end

assign df_pop = (df_count != 0) && !c_busy;

wire [2:0] c_kind = c_t[2:0];

// the four pixels this clock
reg  [7:0]  c_pix[4];
reg  [7:0]  c_idx[4];
reg signed [16:0] c_x[4];
always @(*) begin
	integer k;
	reg [5:0] c, sc, spx;
	reg [2:0] byt;
	reg [6:0] w7;
	for (k = 0; k < 4; k = k + 1) begin
		c = {2'b00, c_g, k[1:0]};
		sc = 0; byt = 0; spx = 0; w7 = 0;
		if (c_kind == K_TILE && c_t[20]) begin           // version 2: turned and sized
			c_pix[k] = (k[1:0] <= c_t[22:21]) ? c_d[c_t[23 + k*3 +: 3]*8 +: 8] : 8'd0;
			c_idx[k] = c_pix[k];
			c_x[k]   = $signed({{7{c_t[12]}}, c_t[12:3]}) + $signed({11'd0, c});
		end
		else if (c_kind == K_TILE) begin
			sc = c_t[13] ? (6'd7 - c) : c;
			if (c_t[19]) c_pix[k] = c_d[sc[2:0]*8 +: 8];
			else begin
				byt      = {c_t[14], sc[2:1]};
				c_pix[k] = sc[0] ? {4'd0, c_d[byt*8 +: 4]} : {4'd0, c_d[byt*8+4 +: 4]};
			end
			c_idx[k] = c_t[19] ? c_pix[k] : {c_t[18:15], c_pix[k][3:0]};
			c_x[k]   = $signed({{7{c_t[12]}}, c_t[12:3]}) + $signed({11'd0, c});
		end
		else begin   // a sprite word
			if (c_t[27]) c_pix[k] = c_d[c[2:0]*8 +: 8];
			else begin
				byt      = (c_t[20:19] == 2'd0) ? {c_t[22], c[2:1]} : c[3:1];
				c_pix[k] = c[0] ? {4'd0, c_d[byt*8 +: 4]} : {4'd0, c_d[byt*8+4 +: 4]};
			end
			c_idx[k] = c_t[27] ? c_pix[k] : {c_t[26:23], c_pix[k][3:0]};
			spx      = c_t[33:28] + c;                     // the pixel in the sprite's row
			w7       = 7'd8 << c_t[20:19];
			c_x[k]   = $signed({c_t[18], c_t[18:3]}) + $signed({10'd0, c_t[21] ? (w7 - 7'd1 - {1'b0, spx}) : {1'b0, spx}});
		end
	end
end

// four copies of the palette: one for each of the four pixels a clock
reg  [23:0] palq[4];
generate
	for (gb = 0; gb < 4; gb = gb + 1) begin : palc
		wire [23:0] q;
		ovram #(.AW(8), .DW(24), .GREY(1)) palm(.clk(clk), .we(pal_we), .wa(pal_wa), .wd(pal_wd), .ra(c_idx[gb]), .q(q));
		always @(*) palq[gb] = q;
	end
endgenerate

always @(posedge clk) begin
	integer k, b;
	sat_we <= 0;
	for (k = 0; k < 4; k = k + 1) ent_we[k] <= 0;
	if (reset) begin
		c_busy <= 0; df_r <= 0; ls_got <= 0; cop_got <= 0; map_done <= 0;
		for (k = 0; k < 4; k = k + 1) begin p_v[k] <= 0; bw_we[k] <= 0; o_v[k] <= 0; ow_we[k] <= 0; end
		acc_ss <= 0; acc_sl <= 0; coll_ss <= 0; coll_sl <= 0; coll_new <= 0; blt_got <= 0;
	end
	else begin
		// version 2, stage 3: the owner buffer - what was under each pixel just written
		coll_new <= 0;
		begin
			reg [127:0] nss, nsl;
			nss = acc_ss; nsl = acc_sl;
			for (b = 0; b < 4; b = b + 1) begin
				reg [23:0] c, u;
				reg [33:0] oq;
				reg  [8:0] t;
				integer ch;
				// the colour: the pixel's own, or mixed with what is under it (when something is)
				oq = (ow_we[b] && ow_a[b] == o_a[b]) ? ow_d[b] : (ow2_we[b] && ow2_a[b] == o_a[b]) ? ow2_d[b] : own_q[b];
				ow2_we[b] <= ow_we[b] && !clr_we; ow2_a[b] <= ow_a[b]; ow2_d[b] <= ow_d[b];
				u = oq[32:9];
				c = o_rgb[b];
				if (o_m[b] != 2'd0 && oq[33])
					for (ch = 0; ch < 3; ch = ch + 1) begin
						case (o_m[b])
							2'd1: t = ({1'b0, u[ch*8 +: 8]} + {1'b0, o_rgb[b][ch*8 +: 8]}) >> 1;
							2'd2: begin t = {1'b0, u[ch*8 +: 8]} + {1'b0, o_rgb[b][ch*8 +: 8]}; if (t[8]) t = 9'd255; end
							default: t = (u[ch*8 +: 8] > o_rgb[b][ch*8 +: 8]) ? ({1'b0, u[ch*8 +: 8]} - {1'b0, o_rgb[b][ch*8 +: 8]}) : 9'd0;
						endcase
						c[ch*8 +: 8] = t[7:0];
					end
				bw_we[b] <= o_v[b]; bw_a[b] <= o_a[b]; bw_d[b] <= c;
				ow_we[b] <= o_v[b];
				ow_a[b]  <= o_a[b];
				if (o_spr[b]) begin
					ow_d[b] <= {1'b1, c, oq[8], 1'b1, o_id[b]};
					if (o_v[b] && oq[7]) begin nss[o_id[b]] = 1'b1; nss[oq[6:0]] = 1'b1; end
					if (o_v[b] && oq[8]) nsl[o_id[b]] = 1'b1;
				end
				else begin
					ow_d[b] <= {1'b1, c, 1'b1, oq[7:0]};
					if (o_v[b] && oq[7]) nsl[oq[6:0]] = 1'b1;
				end
			end
			if (coll_latch) begin coll_ss <= nss; coll_sl <= nsl; acc_ss <= 0; acc_sl <= 0; coll_new <= 1; end
			else begin acc_ss <= nss; acc_sl <= nsl; end
		end
		for (b = 0; b < 4; b = b + 1) o_v[b] <= 0;
		for (k = 0; k < 4; k = k + 1)
			if (p_v[k]) begin o_v[p_b[k]] <= 1; o_a[p_b[k]] <= p_a[k]; o_spr[p_b[k]] <= p_spr[k]; o_id[p_b[k]] <= p_id[k]; o_m[p_b[k]] <= p_m[k]; o_rgb[p_b[k]] <= palq[k]; end
		if (blt_got_clr) blt_got <= 0;
		// (stage 2, the pixels through the palette: into stage 3 above, which writes the banks)
		for (k = 0; k < 4; k = k + 1) p_v[k] <= 0;
		if (c_busy) begin
			for (k = 0; k < 4; k = k + 1) begin
				p_v[k] <= (c_pix[k] != 0) && (c_x[k] >= 0) && (c_x[k] < RW);
				p_a[k] <= slot_base + {2'd0, c_x[k][8:2]};
				p_b[k] <= c_x[k][1:0];
				p_spr[k] <= (c_kind == K_SPR);
				p_id[k]  <= c_t[40:34];
				p_m[k]   <= c_t[42:41];
			end
			c_g <= c_g + 2'd1;
			if (c_g == c_ng) c_busy <= 0;
		end
		else if (df_pop) begin
			c_d <= df_d[df_r]; c_t <= df_t[df_r]; df_r <= df_r + 5'd1;
			case (df_t[df_r][2:0])
				K_MAP: begin
					for (k = 0; k < 4; k = k + 1)
						if (k >= df_t[df_r][10:9]) begin
							reg [5:0] ei;
							ei = df_t[df_r][8:3] + k[5:0] - {4'd0, df_t[df_r][10:9]};
							ent_we[ei[1:0]] <= 1; ent_wa[ei[1:0]] <= ei[5:2]; ent_wd[ei[1:0]] <= df_d[df_r][k*16 +: 16];
						end
					map_done <= map_done + 8'd1;
`ifdef OCTO_DEBUG
					if (L == 9'd200 && df_t[df_r][8:3] < 6'd8) $display("  MAP i0 %0d lane %0d data %h", df_t[df_r][8:3], df_t[df_r][10:9], df_d[df_r]);
`endif
				end
				K_TILE: begin c_busy <= 1; c_g <= 0; c_ng <= df_t[df_r][20] ? 2'd0 : 2'd1; end
				K_SPR: begin
					c_busy <= 1; c_g <= 0;
					// a word holds 8 pixels of 256 colours, 16 of 16 colours, or 8 (a half) of an 8-wide 16-colour sprite
					c_ng <= (df_t[df_r][27] || df_t[df_r][20:19] == 2'd0) ? 2'd1 : 2'd3;
				end
				K_SAT: begin sat_we <= 1; sat_wa <= df_t[df_r][9:3]; sat_wd <= df_d[df_r]; end
				K_LS:  begin ls_val <= df_d[df_r][df_t[df_r][4:3]*16 +: 16]; ls_got <= 1; end
				K_COP: begin cop_word <= df_d[df_r]; cop_got <= 1; end
				K_VRD: vrd_data <= df_d[df_r][df_t[df_r][5:3]*8 +: 8];
				K_BLT: begin blt_rdata <= df_d[df_r]; blt_got <= 1; end
				default: ;
			endcase
		end
		if (ls_clr)  ls_got  <= 0;
		if (cop_clr) cop_got <= 0;
	end
end

// ---------------------------------------------------------------------------------
//  THE RENDERER: a raster line at a time, up to three ahead of the beam
// ---------------------------------------------------------------------------------
localparam S_WAIT = 0, S_COP = 1, S_COPW = 2, S_COPA = 3, S_SAT = 4, S_PASS = 5,
           S_LAY0 = 6, S_LSW = 7, S_LAY1 = 8, S_MAP = 9, S_MAPW = 10, S_TILE = 11,
           S_SCAN = 12, S_SCAN2 = 13, S_DRAW = 14, S_DRAW1 = 15, S_DRAW2 = 16, S_DRAW3 = 18, S_END = 17, S_CLR = 19,
           S_AFF0 = 20, S_AFF = 21;
// version 2: a turned and sized layer - each pixel's place in the picture, (u, v), 16.16: at the
// line's left (U0, V0) + (DUY, DVY) x the line, then + (DUX, DVX) a pixel along. Up to 4 pixels
// that fall in the same 8 bytes go as one read.
reg  [31:0] af_u, af_v;
reg  [8:0]  af_r;              // the pixel
reg         af_bn;             // a read being gathered: its word, its pixels
reg  [1:0]  af_n;
reg  [20:0] af_w;
reg  [11:0] af_off;
reg  [8:0]  af_r0;

reg  [4:0] st;
reg  [8:0] L;                  // the raster line being drawn
reg  [8:0] nl;                 // lines a frame (measured)
reg  [8:0] prev_y;
reg  [2:0] pass;               // 0 sprites 2, 1 layer 0, 2 sprites 1, 3 layer 1, 4 sprites 0
reg        ls_clr, cop_clr, ls_use;
reg        cop_armed;          // the copper has been started from COPBASE at a raster line 0
wire       cop_disarm = rw_en && (rw_a == 8'h0E || rw_a == 8'h10 || rw_a == 8'h11 || rw_a == 8'h12);
reg [23:0] cop_ptr;
reg  [7:0] sat_i;
reg  [5:0] mi;                 // map entries asked for
reg  [7:0] map_issued;
reg  [2:0] fine;
reg  [2:0] ty;
reg  [7:0] mr;
reg  [8:0] mc0;
(* ramstyle = "MLAB, no_rw_check" *) reg  [8:0] hits[64];           // {priority, sprite}
reg  [6:0] nh;                 // hits on this line
reg        scanned;            // the table has been looked through for this line
reg  [7:0] sj;                 // the sprite asked for
reg        p1_v, p2_v;         // the table's answer on its way, and here
reg  [6:0] p1_i, p2_i;
reg  [6:0] hk;                 // the hit being drawn
reg  [3:0] wk, nw;             // its words
reg [20:0] srow;               // the word of its row
reg        shalf;
reg [63:0] se;                 // its entry
reg  [6:0] sidx;               // version 2: which sprite it is

wire       lay = pass[1];      // pass 1 -> layer 0, pass 3 -> layer 1
wire [1:0] sprio = (pass == 0) ? 2'd2 : (pass == 2) ? 2'd1 : 2'd0;
wire signed [15:0] sy  = $signed({7'd0, L}) - 16'sd51 - $signed({{8{yadj[7]}}, yadj});
wire signed [15:0] sx0 = -16'sd32 - $signed({{8{xadj[7]}}, xadj});    // the x of raster X 0
wire drained = rqf_empty && (outstanding == 0) && (df_count == 0) && !c_busy
               && !p_v[0] && !p_v[1] && !p_v[2] && !p_v[3]
               && !bw_we[0] && !bw_we[1] && !bw_we[2] && !bw_we[3]
               && !o_v[0] && !o_v[1] && !o_v[2] && !o_v[3];

// how far ahead line L is
wire [8:0] ahead = (L >= vic_y) ? (L - vic_y) : (L + nl - vic_y);
wire       may_draw = (ahead >= 9'd1) && (ahead <= 9'd3) && (L[1:0] != vic_y[1:0]);

task push(input [20:0] w, input [TW-1:0] t);
	begin rqf_w[rqf_wp[1:0]] <= w; rqf_t[rqf_wp[1:0]] <= t; rqf_wp <= rqf_wp + 3'd1; end
endtask

always @(posedge clk) begin
	ls_clr  <= 0;
	coll_latch <= 0;
	cop_clr <= 0;
	if (cop_take) cop_w <= 0;
	if (reset) begin
		st <= S_WAIT; L <= 0; nl <= 9'd312; prev_y <= 0; cop_w <= 0; frame <= 0; rqf_wp <= 0; map_issued <= 0; clr_we <= 0; cop_armed <= 0;
		cop_off <= 0; sat_off <= 0; cop_k <= 0; sat_k <= 0; cop_d <= 0; sat_d <= 0;
	end
	else begin
		if (anim_rst) begin cop_off <= 0; sat_off <= 0; cop_k <= 0; sat_k <= 0; cop_d <= 0; sat_d <= 0; end
		prev_y <= vic_y;
		if (vic_y != prev_y && vic_y < prev_y) begin nl <= prev_y + 9'd1; frame <= frame + 8'd1; end

		case (st)
		S_WAIT: begin
			if (ahead == 0 || ahead > 9'd4) L <= (vic_y + 9'd1 == nl) ? 9'd0 : vic_y + 9'd1;   // behind: catch up
			else if (may_draw) begin
				slot_base <= {L[1:0], 7'd0};
				if (L == 0) begin
					cop_ptr <= copbase + cop_off; cop_armed <= 1; sat_fr <= satbase + sat_off;
					// the animation moves on (this frame shows where it was)
					if (copdiv != 0) begin
						if (cop_d + 8'd1 >= copdiv) begin
							cop_d <= 0;
							if (cop_k + 16'd1 >= copsteps) begin cop_k <= 0; cop_off <= 0; end
							else begin cop_k <= cop_k + 16'd1; cop_off <= cop_off + copstep; end
						end
						else cop_d <= cop_d + 8'd1;
					end
					if (satdiv != 0) begin
						if (sat_d + 8'd1 >= satdiv) begin
							sat_d <= 0;
							if (sat_k + 16'd1 >= satsteps) begin sat_k <= 0; sat_off <= 0; end
							else begin sat_k <= sat_k + 16'd1; sat_off <= sat_off + satstep; end
						end
						else sat_d <= sat_d + 8'd1;
					end
				end
				scanned <= 0;
				clr_a <= {L[1:0], 7'd0}; clr_we <= 1;
				if (L == 0) coll_latch <= 1;
				st <= S_CLR;
				sat_i <= 0;
			end
		end

		// the line's slot cleared, 4 pixels a clock
		S_CLR: begin
			if (clr_a[6:0] == 7'd98) begin clr_we <= 0; st <= (copen && cop_armed) ? S_COP : S_SAT; end
			else clr_a <= clr_a + 9'd1;
		end

		// the copper: the entries for this line (and any earlier ones) done in order
		S_COP: if (!rqf_full) begin
			push(cop_ptr[23:3], {{(TW-3){1'b0}}, K_COP});
			st <= S_COPW;
		end
		S_COPW: if (cop_got) begin cop_clr <= 1; st <= S_COPA; end
		S_COPA: if (!cop_w) begin
			reg [31:0] e;
			e = cop_ptr[2] ? cop_word[63:32] : cop_word[31:0];
			if (e[15:0] == 16'hFFFF || e[15:0] > {7'd0, L}) st <= S_SAT;
			else begin
				if (e[23:16] > 8'h04) begin cop_w <= 1; cop_wa <= e[23:16]; cop_wd <= e[31:24]; end
`ifdef OCTO_DEBUG
				if (e[23:16] >= 8'h20) $display("COPPER L %0d ptr %h e %h word %h", L, cop_ptr, e, cop_word);
`endif
				cop_ptr <= cop_ptr + 24'd4;
				st <= cop_ptr[2] ? S_COP : S_COPA;        // the next entry: in the next word, or this one
			end
		end

		// the sprite table, once a frame
		S_SAT: begin
			if (L != 0) begin st <= S_PASS; pass <= 0; end
			else if (!rqf_full) begin
				if (sat_i == 8'd128) begin st <= S_PASS; pass <= 0; end
				else begin
					push(sat_fr[23:3] + {14'd0, sat_i[6:0]}, {{(TW-10){1'b0}}, sat_i[6:0], K_SAT});
					sat_i <= sat_i + 8'd1;
				end
			end
		end

		S_PASS: begin
			if (L < FIRST || L > LAST || !ENABLE || pass == 5) st <= S_END;
			else if (pass[0]) begin
				if (lctrl[lay][0]) st <= S_LAY0; else pass <= pass + 3'd1;
			end
			else if (sprcount == 0) pass <= pass + 3'd1;
			else if (!scanned) begin st <= S_SCAN; sj <= 0; p1_v <= 0; p2_v <= 0; nh <= 0; end
			else st <= S_SCAN2;
		end

		// a layer: the line scroll, the map entries, then the tiles
		S_LAY0: begin
			if (lctrl[lay][3] && lmode[lay][2]) st <= S_AFF0;
			else if (lctrl[lay][2]) begin
				if (!rqf_full) begin
					reg [23:0] la;
					la = lsbase[lay] + {14'd0, L, 1'b0};
					push(la[23:3], {{(TW-5){1'b0}}, la[2:1], K_LS});
					st <= S_LSW;
				end
			end
			else begin ls_use <= 0; st <= S_LAY1; end
		end
		S_LSW: if (ls_got) begin ls_clr <= 1; ls_use <= 1; st <= S_LAY1; end
		S_LAY1: begin
			reg [15:0] vy, vx;
			reg  [1:0] mw, mh;
			mw = lctrl[lay][5:4]; mh = lctrl[lay][7:6];
			vy = sy + scrolly[lay];
			vx = sx0 + scrollx[lay] + (ls_use ? ls_val : 16'd0);
			ty   <= vy[2:0];
			mr   <= vy[10:3] & ((8'd32 << mh) - 8'd1);
			mc0  <= {1'b0, vx[10:3]} & ((9'd32 << mw) - 9'd1);
			fine <= vx[2:0];
			nt   <= (RW + vx[2:0] + 7) >> 3;
			mi   <= 0;
			ti   <= 0;
			st   <= lctrl[lay][3] ? S_TILE : S_MAP;          // version 2: a bitmap layer has no map
		end
		S_MAP: if (!rqf_full) begin
			if (mi >= nt) st <= S_MAPW;
			else begin
				reg  [8:0] mc;
				reg [23:0] ea;
				reg  [1:0] mw;
				mw = lctrl[lay][5:4];
				mc = (mc0 + {3'd0, mi}) & ((9'd32 << mw) - 9'd1);
				ea = mapbase[lay] + (((({16'd0, mr}) << (5 + mw)) + {15'd0, mc}) << 1);
`ifdef OCTO_DEBUG
				if (L == 9'd200 && mi < 6'd8) $display("  ask mi %0d ea %h word %h", mi, ea, ea[23:3]);
`endif
				push(ea[23:3], {{(TW-11){1'b0}}, ea[2:1], mi, K_MAP});
				map_issued <= map_issued + 8'd1;
				mi <= mi + 6'd4 - {4'd0, ea[2:1]};
			end
		end
		S_MAPW: if (map_done == map_issued) begin ti <= 0; st <= S_TILE;
`ifdef OCTO_DEBUG
			if (L == 9'd200) $display("L200 layer %0d lctrl %h nt %0d mc0 %0d mr %0d ty %0d fine %0d ent0 %h ent1 %h ent2 %h ent5 %h", lay, lctrl[lay], nt, mc0, mr, ty, fine, ent_q[0], ent_q[1], ent_q[2], ent_q[1]);
`endif
		end
		S_TILE: if (!rqf_full) begin
			if (ti >= nt) begin pass <= pass + 3'd1; st <= S_PASS; end
			else begin
				reg [15:0] e;
				reg  [2:0] row;
				reg [23:0] ta;
				reg signed [9:0] xb;
				reg  [1:0] mw;
				reg  [8:0] mc;
				e   = ent_q[ti[1:0]];
				row = e[11] ? (3'd7 - ty) : ty;
				ta  = lctrl[lay][1] ? (tilebase[lay] + {4'd0, e[15:12], e[9:0], row, 3'd0})   // (256 colours: the bank bits are more tile number - 16384 tiles)
				                    : (tilebase[lay] + {9'd0, e[9:0], row, 2'd0});
				xb  = $signed({1'b0, ti, 3'd0}) - $signed({7'd0, fine});
				// version 2: a bitmap layer - a byte a pixel, (256 << map width) bytes a row, no map
				mw  = lctrl[lay][5:4];
				mc  = (mc0 + {3'd0, ti}) & ((9'd32 << mw) - 9'd1);
				if (lctrl[lay][3]) begin
					ta = tilebase[lay] + ({13'd0, mr, ty} << (8 + mw)) + {12'd0, mc, 3'd0};
					push(ta[23:3], {lmode[lay][1:0], {(TW-22){1'b0}}, 1'b1, 4'd0, 1'b0, 1'b0, xb, K_TILE});
				end
				else
				push(ta[23:3], {lmode[lay][1:0], {(TW-22){1'b0}}, lctrl[lay][1], e[15:12], ta[2], e[10], xb, K_TILE});
				ti <= ti + 6'd1;
			end
		end

		// the sprites on this line: found once (the table read is two clocks: asked for, then
		// out), then drawn a priority at a time, the last found first
		S_SCAN: begin
			sat_ra <= sj[6:0];
			p1_v   <= (sj < {1'b0, sprcount[7:0]}) && (sj < 8'd128);
			p1_i   <= sj[6:0];
			if (sj < 8'd128) sj <= sj + 8'd1;
			p2_v   <= p1_v;
			p2_i   <= p1_i;
			if (p2_v) begin
				reg signed [15:0] r, X;
				reg [6:0] h, w;
				r = sy - $signed(sat_q[31:16]);
				X = $signed(sat_q[15:0]);
				h = 7'd8 << sat_q[51:50];
				w = 7'd8 << sat_q[49:48];
				if (sat_q[55] && sat_q[61:60] != 2'd3 && r >= 0 && r < $signed({9'd0, h}) && nh < 7'd64
				    && X + $signed({9'd0, w}) > sx0 && X < sx0 + RW)
				begin
					hits[nh[5:0]] <= {sat_q[61:60], p2_i};
					nh <= nh + 7'd1;
				end
			end
			if (!p1_v && !p2_v && sj != 0 && (sj >= {1'b0, sprcount[7:0]} || sj == 8'd128)) begin
				scanned <= 1; st <= S_SCAN2;
			end
		end
		S_SCAN2: begin
			if (nh == 0) begin pass <= pass + 3'd1; st <= S_PASS; end
			else begin hk <= nh - 7'd1; st <= S_DRAW; end
		end
		S_DRAW: begin
			if (hits[hk[5:0]][8:7] == sprio) begin sat_ra <= hits[hk[5:0]][6:0]; sidx <= hits[hk[5:0]][6:0]; st <= S_DRAW1; end
			else if (hk == 0) begin pass <= pass + 3'd1; st <= S_PASS; end
			else hk <= hk - 7'd1;
		end
		S_DRAW1: st <= S_DRAW2;
		S_DRAW2: begin                     // its row: where in VRAM, how many words
			reg signed [15:0] r;
			reg  [6:0] h, rr;
			reg  [2:0] lb2;                // log2 of the bytes a row
			reg [23:0] ra;
			se <= sat_q;
			r   = sy - $signed(sat_q[31:16]);
			h   = 7'd8 << sat_q[51:50];
			rr  = sat_q[53] ? (h - 7'd1 - r[6:0]) : r[6:0];
			lb2 = sat_q[54] ? (3'd3 + {1'b0, sat_q[49:48]}) : (3'd2 + {1'b0, sat_q[49:48]});
			ra  = sprgfx + {3'd0, sat_q[47:32], 5'd0} + ({17'd0, rr} << lb2);
			srow  <= ra[23:3];
			shalf <= ra[2];
			nw    <= (lb2 <= 3'd3) ? 4'd1 : (4'd1 << (lb2 - 3'd3));
			wk    <= 0;
			st    <= S_DRAW3;
		end
		S_DRAW3: if (!rqf_full) begin       // its words
			reg signed [15:0] xb;
			reg [5:0] px0;
			xb  = $signed(se[15:0]) + 16'sd32 + $signed({{8{xadj[7]}}, xadj});
			px0 = se[54] ? {wk[2:0], 3'd0} : {wk[1:0], 4'd0};
			push(srow + {17'd0, wk}, {se[63:62], sidx, px0, se[54], se[59:56], shalf, se[52], se[49:48], xb, K_SPR});
			if (wk + 4'd1 == nw) begin
				if (hk == 0) begin pass <= pass + 3'd1; st <= S_PASS; end
				else begin hk <= hk - 7'd1; st <= S_DRAW; end
			end
			else wk <= wk + 4'd1;
		end

		// version 2: a turned and sized layer, a pixel a clock
		S_AFF0: begin
			af_u <= af_u0 + af_duy * {23'd0, L};
			af_v <= af_v0 + af_dvy * {23'd0, L};
			af_r <= 0; af_bn <= 0;
			st <= S_AFF;
		end
		S_AFF: begin
			reg  [1:0] mw, mh;
			reg [15:0] ui, vi;
			reg        ok, last, flush;
			reg [23:0] a;
			mw = lctrl[lay][5:4]; mh = lctrl[lay][7:6];
			last = (af_r == RW);
			ui = af_u[31:16]; vi = af_v[31:16];
			ok = !last && (!lmode[lay][3] || ((ui >> (8 + mw)) == 16'd0 && (vi >> (8 + mh)) == 16'd0));
			ui = ui & ((16'd256 << mw) - 16'd1);
			vi = vi & ((16'd256 << mh) - 16'd1);
			a  = tilebase[lay] + ({8'd0, vi} << (8 + mw)) + {8'd0, ui};
			flush = af_bn && (!ok || a[23:3] != af_w || af_n == 2'd3);
			if (!flush || !rqf_full) begin
				if (flush)
					push(af_w, {lmode[lay][1:0], {(TW-37){1'b0}}, af_off, af_n, 1'b1, 1'b1, 4'd0, 1'b0, 1'b0, 1'b0, af_r0, K_TILE});
				if (last) begin
					if (!flush || !af_bn) begin pass <= pass + 3'd1; st <= S_PASS; end
					af_bn <= 0;
				end
				else begin
					if (ok) begin
						if (af_bn && !flush) begin
							af_n <= af_n + 2'd1;
							af_off[(af_n + 2'd1)*3 +: 3] <= a[2:0];
						end
						else begin
							af_bn <= 1; af_n <= 0; af_w <= a[23:3]; af_r0 <= af_r;
							af_off <= {9'd0, a[2:0]};
						end
					end
					else af_bn <= 0;
					af_r <= af_r + 9'd1;
					af_u <= af_u + af_dux;
					af_v <= af_v + af_dvx;
				end
			end
		end

		S_END: if (drained && !cop_w) begin
			bdl[L[1:0]] <= backdrop;
			cdl[L[1:0]] <= ctrl[3:0];
			kdl[L[1:0]] <= key;
			L <= (L + 9'd1 == nl) ? 9'd0 : L + 9'd1;
			st <= S_WAIT;
		end
		default: st <= S_WAIT;
		endcase
		// the copper switched on, or moved: it waits for the next raster line 0
		if (cop_disarm) cop_armed <= 0;
	end
end

// ---------------------------------------------------------------------------------
//  THE BLITTER (version 2): works in the VRAM on its own, a byte at a time, with the port
//  when nothing else wants it. COPY (and COPY0: source bytes of 0 left out - see-through)
//  BW x BH bytes from BSRC to BDST, rows BSSTR / BDSTR apart; FILL the same with BFILL; LINE
//  from (LX0,LY0) to (LX1,LY1) in BFILL, in a bitmap at BDST, BDSTR bytes a row, clipped to
//  BW x BH. The source is read a 64-bit word at a time and kept, so a row costs a read per 8.
// ---------------------------------------------------------------------------------
localparam B_IDLE = 0, B_RD = 1, B_RW = 2, B_WR = 3, B_WW = 4, B_NEXT = 5, B_LN = 6, B_LP = 7, B_LW = 8, B_LS = 9;
reg   [3:0] bst;
reg  [23:0] b_sa, b_da, b_rsa, b_rda;
reg  [15:0] b_col, b_row;
reg  [20:0] b_ca;              // the word kept
reg  [63:0] b_cd;
reg         b_cv;
reg   [7:0] b_byte;
reg  signed [16:0] b_x, b_y, b_dx, b_dy, b_err;
reg  signed [1:0]  b_sx, b_sy;
assign blt_busy = bst != B_IDLE;
reg         blt_done_r;
assign blt_done = blt_done_r;
always @(posedge clk) begin
	blt_done_r  <= 0;
	blt_got_clr <= 0;
	if (reset) begin bst <= B_IDLE; blt_rreq <= 0; blt_wreq <= 0; b_cv <= 0; end
	else case (bst)
	B_IDLE: if (blt_go) begin
		b_sa <= bsrc; b_da <= bdst; b_rsa <= bsrc; b_rda <= bdst; b_col <= 0; b_row <= 0; b_cv <= 0;
		if (bop == 2'd3) begin
			b_x <= {lx0[15], lx0}; b_y <= {ly0[15], ly0};
			b_dx <= ($signed(lx1) >= $signed(lx0)) ? ($signed({lx1[15], lx1}) - $signed({lx0[15], lx0})) : ($signed({lx0[15], lx0}) - $signed({lx1[15], lx1}));
			b_dy <= ($signed(ly1) >= $signed(ly0)) ? ($signed({ly0[15], ly0}) - $signed({ly1[15], ly1})) : ($signed({ly1[15], ly1}) - $signed({ly0[15], ly0}));
			b_sx <= ($signed(lx1) >= $signed(lx0)) ? 2'sd1 : -2'sd1;
			b_sy <= ($signed(ly1) >= $signed(ly0)) ? 2'sd1 : -2'sd1;
			bst <= B_LN;
		end
		else if (bw == 0 || bh == 0) blt_done_r <= 1;
		else bst <= (bop == 2'd1) ? B_WR : B_RD;
	end
	// the source byte: from the kept word, or a read
	B_RD: if (b_cv && b_ca == b_sa[23:3]) begin b_byte <= b_cd[b_sa[2:0]*8 +: 8]; bst <= B_WR; end
	      else if (!blt_rreq) begin blt_rreq <= 1; blt_raddr <= b_sa[23:3]; end
	      else if (blt_rack) begin blt_rreq <= 0; bst <= B_RW; end
	B_RW: if (blt_got) begin blt_got_clr <= 1; b_cd <= blt_rdata; b_ca <= b_sa[23:3]; b_cv <= 1; bst <= B_RD; end
	// the destination byte
	B_WR: begin
		reg [7:0] v;
		v = (bop == 2'd1) ? bfill : b_byte;
		if (bop == 2'd2 && v == 8'd0) bst <= B_NEXT;
		else begin
			blt_wreq <= 1; blt_waddr <= b_da; blt_wdata <= v;
			if (b_cv && b_ca == b_da[23:3]) b_cd[b_da[2:0]*8 +: 8] <= v;     // (the kept word stays true)
			bst <= B_WW;
		end
	end
	B_WW: if (blt_wack) begin blt_wreq <= 0; bst <= B_NEXT; end
	B_NEXT: begin
		if (b_col + 16'd1 == bw) begin
			b_col <= 0;
			if (b_row + 16'd1 == bh) begin bst <= B_IDLE; blt_done_r <= 1; end
			else begin
				b_row <= b_row + 16'd1;
				b_rsa <= b_rsa + {{8{bss[15]}}, bss}; b_rda <= b_rda + {{8{bds[15]}}, bds};
				b_sa  <= b_rsa + {{8{bss[15]}}, bss}; b_da  <= b_rda + {{8{bds[15]}}, bds};
				bst <= (bop == 2'd1) ? B_WR : B_RD;
			end
		end
		else begin b_col <= b_col + 16'd1; b_sa <= b_sa + 24'd1; b_da <= b_da + 24'd1; bst <= (bop == 2'd1) ? B_WR : B_RD; end
	end
	// a line (Bresenham): plot, then step
	B_LN: begin b_err <= b_dx + b_dy; bst <= B_LP; end
	B_LP: begin
		if (b_x >= 0 && b_x < $signed({1'b0, bw}) && b_y >= 0 && b_y < $signed({1'b0, bh})) begin
			blt_wreq <= 1; blt_wdata <= bfill;
			blt_waddr <= bdst + b_y[15:0] * bds + {8'd0, b_x[15:0]};
			bst <= B_LW;
		end
		else bst <= B_LS;
	end
	B_LW: if (blt_wack) begin blt_wreq <= 0; bst <= B_LS; end
	B_LS: begin
		reg signed [17:0] e2;
		if (b_x == $signed({lx1[15], lx1}) && b_y == $signed({ly1[15], ly1})) begin bst <= B_IDLE; blt_done_r <= 1; end
		else begin
			e2 = {b_err, 1'b0};
			if (e2 >= b_dy) begin b_x <= b_x + b_sx; end
			if (e2 <= b_dx) begin b_y <= b_y + b_sy; end
			b_err <= b_err + ((e2 >= b_dy) ? b_dy : 17'sd0) + ((e2 <= b_dx) ? b_dx : 17'sd0);
			bst <= B_LP;
		end
	end
	default: bst <= B_IDLE;
	endcase
end

endmodule
