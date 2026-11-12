// ovram - a simple dual-port RAM in the form Quartus always makes into block RAM: one write
// port, one read port (registered, the old value on a clash), one clock. GREY: start as a
// grey ramp (the palette's power-on contents).
module ovram #(parameter AW = 8, parameter DW = 8, parameter GREY = 0)
(
	input               clk,
	input               we,
	input      [AW-1:0] wa,
	input      [DW-1:0] wd,
	input      [AW-1:0] ra,
	output reg [DW-1:0] q
);
reg [DW-1:0] m[0:(1 << AW) - 1];
integer i;
initial if (GREY) for (i = 0; i < (1 << AW); i = i + 1) m[i] = {3{i[7:0]}};
always @(posedge clk) begin
	if (we) m[wa] <= wd;
	q <= m[ra];
end
endmodule

// SPACE AUDIT: a small RAM with an asynchronous read, for an MLAB (the same as a reg array read
// straight away: a write shows from the next clock)
module ovlab #(parameter AW = 5, parameter DW = 8)
(
	input           clk,
	input           we,
	input  [AW-1:0] wa,
	input  [DW-1:0] wd,
	input  [AW-1:0] ra,
	output [DW-1:0] q
);
(* ramstyle = "MLAB, no_rw_check" *) reg [DW-1:0] m[0:(1 << AW) - 1];
always @(posedge clk) if (we) m[wa] <= wd;
assign q = m[ra];
endmodule
