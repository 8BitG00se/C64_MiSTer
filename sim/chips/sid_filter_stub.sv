// for the chip test only
module sid_filter (input clk, input [2:0] state, input mode, input [15:0] F0, input [7:0] Res_Filt, input [7:0] Mode_Vol,
	input signed [21:0] voice1, input signed [21:0] voice2, input signed [21:0] voice3, input signed [21:0] ext_in, output [17:0] audio);
assign audio = 0;
endmodule
