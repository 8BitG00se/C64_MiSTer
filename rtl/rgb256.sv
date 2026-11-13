// C64RGB 256 - the recolour unit (Fix 60)                        (c) 2026 Mong00se
//
// LEVEL 1 recolour packs: the same pixels, new colours. Each pixel's colour depends only on what the
// core knows while drawing it - the VIC-II colour index (0-15), the raster line, the screen area (the
// 8x8 cell of the 40x25 window it falls in), the char code (screen byte) under it, or the sprite that
// drew it. Spec: docs/RGB256.md. Built only into the C64RGB 256 core (`define RGB256).
//
//   class  = cell table[cell] if not 0, else char table[char code]     (graphics pixels, 0-13)
//   group  = sprite n: $F0+n   border: $E0+band   graphics: class*16+band   (band = line table[line])
//   slot   = remap[group*16 + colour index]                            (0-255: the pack's 256 colours)
//   RGB    = palette p [slot]                                          (8 palettes of 256 RGB colours)
//
// Pipeline (clk = the C64's clk32; the VIC holds a pixel for 4 clocks): the tag is latched with the
// colour at E0; E1 the cell/char/line tables, E2 the remap, E3 the palette - out after E3, steady
// until the next pixel's E3. So the picture comes out 3 clocks (under one pixel) after the stock one.
//
// The pack comes in over ioctl (Main's file loader), its first 14336 bytes, laid out as the file is:
//   $0000 header ("RGB256PK", version, palettes)   $0100 line table (512)   $0300 char table (256)
//   $0400 cell table (1024; 1000 = outside the window)   $0800 remap (4096)   $1800 palettes (8x256x4: R,G,B,0)

module rgb256
(
	input             clk,

	// the pack (ioctl, Main's loader)
	input             ld_download,     // ioctl_download for the pack's index
	input             ld_wr,
	input      [24:0] ld_addr,
	input       [7:0] ld_data,

	// the VIC's pixel (rtl/video_vicII_656x.vhd pixTag)
	input       [3:0] index,
	input      [28:0] tag,
	// LEVEL 2 (Build 14, rtl/remaster.sv): this pixel's slot is given (a tile's or a sprite frame's
	// pixel); valid in the pixel's remap clock (two clocks after its index and tag)
	input             ovr,
	input       [7:0] ovr_slot,

	input       [2:0] palette,         // which of the pack's palettes
	output reg  [3:0] npal = 0,        // how many the pack has (0: no pack)
	output     [23:0] rgb,
	output            loaded           // a whole, good pack is in
);

localparam [9:0] X0 = 10'd32;          // the raster X of the 40-column window's first pixel (as tagged)
localparam [8:0] Y0 = 9'd51;           // the raster line of the 25-row window's first line

// ------------------------------------------------------------------ the loader
reg        good = 0;                   // the last pack loaded whole and with its magic
reg        magic_ok;
reg [13:0] top;                        // how far the download got
reg        old_dl = 0;
reg  [7:0] lat_r, lat_g;
reg  [3:0] npal_l;
assign loaded = good;

wire       wr = ld_download & ld_wr & (ld_addr < 25'h3800);   // (Build 14: a version 2 pack goes on after $37FF - Level 2, read from the DDR3)
wire [13:0] a = ld_addr[13:0];

function [7:0] magic(input [2:0] i);
	case (i)
		0: magic = "R"; 1: magic = "G"; 2: magic = "B"; 3: magic = "2";
		4: magic = "5"; 5: magic = "6"; 6: magic = "P"; default: magic = "K";
	endcase
endfunction

always @(posedge clk) begin
	old_dl <= ld_download;
	if (ld_download & ~old_dl) begin
		// Build 12: a pack already in stays on while the next streams in over it (Main re-sends the pack
		// for each grading or gradient change - no flash of the stock colours); a bad one ends it below
		magic_ok <= 1;
		top      <= 0;
	end
	if (wr) begin
		if (a > top) top <= a;
		if (a < 14'd8 && ld_data != magic(a[2:0])) magic_ok <= 0;
		if (a == 14'd9) npal_l <= (ld_data == 0) ? 4'd1 : (ld_data > 8) ? 4'd8 : ld_data[3:0];
		if (a[1:0] == 2'd0) lat_r <= ld_data;
		if (a[1:0] == 2'd1) lat_g <= ld_data;
	end
	if (~ld_download & old_dl) begin
		good <= magic_ok && (top == 14'h37FF);
		npal <= (magic_ok && (top == 14'h37FF)) ? npal_l : 4'd0;
	end
end

// ------------------------------------------------------------------ the tables
// line table: 512 x 4 (band 0-15 for each raster line)
(* ramstyle = "M10K, no_rw_check" *) reg [3:0] band_m [512];
// char table: 256 x 4 (class 0-13 for each char code)
(* ramstyle = "M10K, no_rw_check" *) reg [3:0] char_m [256];
// cell table: 1024 x 4 (class for each cell of the window; 1000: outside it; 0 = use the char's)
(* ramstyle = "M10K, no_rw_check" *) reg [3:0] cell_m [1024];
// remap: 4096 x 8 (group*16 + colour -> slot)
(* ramstyle = "M10K, no_rw_check" *) reg [7:0] remap_m [4096];
// palettes: 2048 x 24 (palette*256 + slot -> RGB)
(* ramstyle = "M10K, no_rw_check" *) reg [23:0] pal_m [2048];

always @(posedge clk) if (wr && a >= 14'h0100 && a < 14'h0300) band_m[a[8:0] - 9'h100] <= ld_data[3:0];
always @(posedge clk) if (wr && a[13:8] == 6'h03) char_m[a[7:0]] <= ld_data[3:0];
always @(posedge clk) if (wr && a[13:10] == 4'h1) cell_m[a[9:0]] <= ld_data[3:0];
always @(posedge clk) if (wr && a >= 14'h0800 && a < 14'h1800) remap_m[a[12:0] - 13'h0800] <= ld_data;
wire [11:0] pent = a[13:2] - 12'h600;
always @(posedge clk) if (wr && a >= 14'h1800 && a[1:0] == 2'd2) pal_m[pent[10:0]] <= {lat_r, lat_g, ld_data};

// ------------------------------------------------------------------ the pipeline
// E0 -> E1: the cell, the char code and the line address their tables
wire  [1:0] kind = tag[28:27];
wire  [7:0] code = tag[26:19];
wire  [9:0] tx   = tag[18:9];
wire  [8:0] ty   = tag[8:0];
wire  [9:0] dx   = tx - X0;
wire  [8:0] dy   = ty - Y0;
wire        inwin = (tx >= X0) && (dx < 10'd320) && (ty >= Y0) && (dy < 9'd200);
wire  [9:0] cellno = inwin ? {dy[7:3], 5'd0} + {2'd0, dy[7:3], 3'd0} + {4'd0, dx[8:3]} : 10'd1000;   // row*32 + row*8 + column

reg   [3:0] q_band, q_char, q_cell;
reg   [3:0] s1_idx;
reg   [1:0] s1_kind;
reg   [2:0] s1_spr;
always @(posedge clk) begin
	q_band  <= band_m[ty];
	q_char  <= char_m[code];
	q_cell  <= cell_m[cellno];
	s1_idx  <= index;
	s1_kind <= kind;
	s1_spr  <= code[2:0];
end

// E1 -> E2: the group and the colour address the remap
wire  [3:0] cls0  = (q_cell != 4'd0) ? q_cell : q_char;
wire  [3:0] cls   = (cls0 > 4'd13) ? 4'd13 : cls0;
wire  [7:0] group = (s1_kind == 2'd1) ? {5'b11110, s1_spr} :
                    (s1_kind == 2'd2) ? {4'hE, q_band} :
                                        {cls, q_band};
// (Build 14 fix: the remap read must stay a plain registered read - `rm_q <= remap_m[...]` - so
// Quartus puts the 4096-byte table in block RAM. Build 14 first wrote `ovr ? ovr_slot : remap_m[...]`
// in that register; the mux on the RAM's output stopped the inference and the table was built from
// ~16,500 logic cells. The Level 2 override is now picked AFTER the registers: same clock, same result.)
reg   [7:0] rm_q;
reg         ovr_q;
reg   [7:0] ovs_q;
reg   [1:0] s2_kind;
always @(posedge clk) begin
	rm_q    <= remap_m[{group, s1_idx}];
	ovr_q   <= ovr;
	ovs_q   <= ovr_slot;
	s2_kind <= s1_kind;
end
wire  [7:0] q_slot = ovr_q ? ovs_q : rm_q;

// E2 -> E3: the slot addresses the palette
reg  [23:0] q_rgb;
reg   [1:0] s3_kind;
always @(posedge clk) begin
	q_rgb   <= pal_m[{palette, q_slot}];
	s3_kind <= s2_kind;
end

assign rgb = (s3_kind == 2'd3) ? 24'd0 : q_rgb;

endmodule
