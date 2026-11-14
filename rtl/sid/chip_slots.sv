// © 2026 Mong00se
// OCTOPHONIC: MY CHIPS, PER SID (Fix 81) - Neal's own SID chips, measured off his C64 Reloaded MK2
// (chips/, docs/CHIPS.md), any of them on any of the eight SIDs.
//
// Three chips are held at once, loaded from .CHP files by the menu's Load Chip A / B / C:
//   Chip A (file index 2)  model + filter curve (Custom 1 of every pair) + combined waveforms (bank A)
//   Chip B (file index 3)  model + filter curve (Custom 2)               + combined waveforms (bank B)
//   Chip C (file index 6)  model + filter curve (Custom 3); its waveforms are the core's own for that
//                          model (chip_bank.sv has room for two chips' waveforms, not three)
// and each SID picks one of them, or none (the core's own chip, as the Left/Right SIDs menu lines say),
// with two menu bits. Value 0 is what the core did before Fix 81 - SIDs 1 3 5 7 chip A, 2 4 6 8 chip B -
// so saved settings and the two-chip loads of Octophonic Main play as they always did:
//   SIDs 1 3 5 7:  0 chip A  1 chip B  2 chip C  3 the core's own
//   SIDs 2 4 6 8:  0 chip B  1 chip A  2 chip C  3 the core's own
// A SID whose chip has not been loaded (or with My Chips Off) is the core's own.
//
// A .CHP: $0000-$3FFF the combined waveforms (S+T, P+T, P+S, P+S+T), $4000-$47FF the filter curve
// (1024 x 16 bits, low byte first), $4800 the model (0 6581, 1 8580) - writing it turns the chip on.
// A chip is off while it is loading.
module chip_slots
(
	input             clk,

	// the menu's file loads
	input             ioctl_download,
	input             ioctl_wr,
	input       [7:0] ioctl_index,
	input      [24:0] ioctl_addr,
	input       [7:0] ioctl_data,

	input             enable,      // My Chips: On
	input      [15:0] slot_opt,    // two bits a SID (SID 1 the lowest)
	input       [1:0] menu_ver,    // the menu's own models {right, left}
	input       [3:0] menu_cfg,    //   ...and filter curves {right, left}

	// a chip's waveforms into chip_bank
	output reg        chip_we = 0,
	output reg        chip_wbank,
	output reg  [1:0] chip_wtbl,
	output reg [11:0] chip_widx,
	output reg  [7:0] chip_wdata,

	// a chip's filter curve into Custom 1 / 2 / 3 of every pair's sid_tables
	output reg        crv_wr = 0,
	output reg [11:0] crv_addr,
	output reg [15:0] crv_data,

	// each SID's chip (bit n = SID n+1): model, filter curve (2 bits a SID), measured waveforms on,
	// which bank (0 A, 1 B), and its own filter curve in use
	output      [7:0] sid_ver,
	output     [15:0] sid_cfg,
	output      [7:0] chip_on,
	output      [7:0] chip_bk,
	output      [7:0] chip_fc,

	output      [2:0] loaded       // chips A, B, C are in
);

wire       ld   = ioctl_index == 8'd2 || ioctl_index == 8'd3 || ioctl_index == 8'd6;
wire [1:0] ld_c = ioctl_index[2] ? 2'd2 : {1'b0, ioctl_index[0]};

reg  [2:0] chip_loaded = 0;
reg  [2:0] chip_model = 0;
reg        old_dl = 0;
always @(posedge clk) begin
	chip_we <= 0;
	crv_wr  <= 0;
	old_dl  <= ioctl_download;
	if(~old_dl & ioctl_download & ld) chip_loaded[ld_c] <= 0;
	if(ioctl_wr & ld) begin
		if(ioctl_addr < 25'h4000 && !ld_c[1]) begin
			chip_we    <= 1;
			chip_wbank <= ld_c[0];
			chip_wtbl  <= ioctl_addr[13:12];
			chip_widx  <= ioctl_addr[11:0];
			chip_wdata <= ioctl_data;
		end
		if(ioctl_addr[24:11] == 14'h8) begin
			if(ioctl_addr[0]) begin
				crv_data[15:8] <= ioctl_data;
				crv_addr <= {ld_c, ioctl_addr[10:1]};     // sid_tables adds 1024: Custom 1, 2, 3
				crv_wr   <= 1;
			end
			else crv_data[7:0] <= ioctl_data;
		end
		if(ioctl_addr == 25'h4800) begin
			chip_model[ld_c]  <= ioctl_data[0];
			chip_loaded[ld_c] <= 1;
		end
	end
end
assign loaded = chip_loaded;

genvar k;
generate
	for(k = 0; k < 8; k = k + 1) begin :slot
		wire [1:0] o  = slot_opt[k*2 +: 2];
		// which chip: 0 A, 1 B, 2 C (the even SIDs' first two the other way round)
		wire [1:0] c  = o[1] ? 2'd2 : {1'b0, ((k % 2) != 0) ? ~o[0] : o[0]};
		wire       on = enable & (o != 2'd3) & chip_loaded[c];
		assign sid_ver[k]         = on ? chip_model[c] : menu_ver[k % 2];
		assign sid_cfg[k*2 +: 2]  = on ? (c + 2'd1)    : menu_cfg[(k % 2)*2 +: 2];
		assign chip_fc[k]         = on;
		assign chip_on[k]         = on & ~c[1];
		assign chip_bk[k]         = c[0];
	end
endgenerate

endmodule
