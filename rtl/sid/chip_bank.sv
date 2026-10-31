// OCTOPHONIC: CHIP PERSONALITIES - Neal's own SID chips, measured off his C64 Reloaded MK2 and
// loaded from a .CHP file (chips/mkchips.py, docs/CHIPS.md): one chip for the left SIDs (1 3 5 7),
// one for the right (2 4 6 8). This holds their combined waveforms - S+T, P+T, P+S, P+S+T, 4096
// positions each - for all four SID pairs at once. Each pair looks a waveform up on alternate
// clocks; pairs 3 and 4 run one clock behind pairs 1 and 2 (sid_top PHASE), so the two ports of
// one memory serve all four: port A pairs 1 and 3, port B pairs 2 and 4.
module chip_bank
(
	input         clk,
	input         ce_1m,

	// loading (the menu's Load Chip): side 0 left, 1 right; table 0 S+T, 1 P+T, 2 P+S, 3 P+S+T
	input         we,
	input         wside,
	input   [1:0] wtbl,
	input  [11:0] widx,
	input   [7:0] wdata,

	// each pair's lookup (its f_acc_t) and the answers: {P+S+T, P+S, P+T, S+T} for each side
	input  [11:0] acc0, acc1, acc2, acc3,
	output [31:0] ql0, ql1, ql2, ql3,
	output [31:0] qr0, qr1, qr2, qr3
);

// the clock count of pairs 1 and 2 (as sid_top's state): even, they look up; odd, pairs 3 and 4 do
reg [3:0] st;
always @(posedge clk) begin
	if(~&st) st <= st + 1'd1;
	if(ce_1m) st <= 0;
end
wire [11:0] ra = we ? widx : (st[0] ? acc2 : acc0);
wire [11:0] rb = st[0] ? acc3 : acc1;

wire [31:0] qa_l, qb_l, qa_r, qb_r;
genvar s, t;
generate
	for(s = 0; s < 2; s = s + 1) begin :side
		for(t = 0; t < 4; t = t + 1) begin :tbl
			reg [7:0] mem[4096];
			reg [7:0] qa, qb;
			always @(posedge clk) begin
				if(we && wside == s && wtbl == t) mem[ra] <= wdata;
				qa <= mem[ra];
			end
			always @(posedge clk) qb <= mem[rb];
			if(s == 0) begin
				assign qa_l[t*8 +: 8] = qa;
				assign qb_l[t*8 +: 8] = qb;
			end else begin
				assign qa_r[t*8 +: 8] = qa;
				assign qb_r[t*8 +: 8] = qb;
			end
		end
	end
endgenerate

assign ql0 = qa_l; assign ql2 = qa_l; assign ql1 = qb_l; assign ql3 = qb_l;
assign qr0 = qa_r; assign qr2 = qa_r; assign qr1 = qb_r; assign qr3 = qb_r;

endmodule
