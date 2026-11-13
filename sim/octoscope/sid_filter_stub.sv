// sim/octoscope: a stand-in for rtl/sid/sid_filter.sv (Verilator can't take its mixed assignments). No filter:
// the three voices and the external input mixed straight, times the volume - a chip's whole output that moves
// every microsecond and follows volume writes, which is all the scope's channels 24-31 need to be checked with.
module sid_filter
(
	input               clk,
	input         [2:0] state,
	input               mode,
	input        [15:0] F0,
	input         [7:0] Res_Filt,
	input         [7:0] Mode_Vol,
	input signed [21:0] voice1,
	input signed [21:0] voice2,
	input signed [21:0] voice3,
	input signed [21:0] ext_in,
	output       [17:0] audio
);
reg signed [23:0] mix;
reg signed [27:0] o;
always @(posedge clk) begin
	mix <= 24'(voice1) + 24'(voice2) + 24'(voice3) - 24'sd655360;
	o   <= (mix >>> 4) * $signed({1'b0, Mode_Vol[3:0]});
end
assign audio = o[21:4];
endmodule
