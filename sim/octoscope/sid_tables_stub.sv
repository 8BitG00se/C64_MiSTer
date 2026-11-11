// sim/octoscope: a stand-in for rtl/sid/sid_tables.sv (its big constant tables don't go through Verilator).
// The scope's checks don't need the chips' combined waveforms (they read 0) or a true filter curve (F0 follows Fc
// in a straight line) - the voices' DAC, envelope and oscillator, which the scope takes, are the real sid_voice's.
module sid_tables #(parameter MULTI_FILTERS = 1)
(
	input             clock,
	input             mode,
	input      [11:0] acc_t,
	output reg  [7:0] _st_out,
	output reg  [7:0] p_t_out,
	output reg  [7:0] ps__out,
	output reg  [7:0] pst_out,
	input       [1:0] cfg,
	input      [10:0] Fc,
	input      [12:0] Fc_offset,
	output     [15:0] F0,
	input             ld_clk,
	input      [11:0] ld_addr,
	input      [15:0] ld_data,
	input             ld_wr,
	input             chipf
);
always @(posedge clock) begin _st_out <= 0; p_t_out <= 0; ps__out <= 0; pst_out <= 0; end
assign F0 = {1'b0, Fc, 4'd0} + 16'd200;
endmodule
