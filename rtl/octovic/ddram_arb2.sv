// =====================================================================================
//  ddram_arb2 - two Avalon masters on the one DDR3 port: A (the drives) and B (OctoVIC).
//
//  The port belongs to one of them at a time. It changes hands only when the owner has
//  nothing asked and nothing still coming back, so every answer (DOUT_READY) is the owner's.
//  If the other one has waited 256 clocks, the owner is held off until its reads are in,
//  and then the port changes hands - neither can starve the other.
// =====================================================================================
module ddram_arb2
(
	input             clk,
	input             reset,

	input      [28:0] a_addr,
	input       [7:0] a_burstcnt,
	input             a_rd,
	input             a_we,
	input      [63:0] a_din,
	input       [7:0] a_be,
	output            a_busy,
	output            a_ready,

	input      [28:0] b_addr,
	input       [7:0] b_burstcnt,
	input             b_rd,
	input             b_we,
	input      [63:0] b_din,
	input       [7:0] b_be,
	output            b_busy,
	output            b_ready,

	output     [28:0] addr,
	output      [7:0] burstcnt,
	output            rd,
	output            we,
	output     [63:0] din,
	output      [7:0] be,
	input             busy,
	input             ready
);

reg       owner;               // 0 A, 1 B
reg       hold;                // the owner made to wait (the other has waited long enough)
reg [8:0] pend;                // beats still to come back to the owner
reg [7:0] waited;

wire o_rd = owner ? b_rd : a_rd;
wire o_we = owner ? b_we : a_we;
wire x_req = owner ? (a_rd | a_we) : (b_rd | b_we);

assign addr     = owner ? b_addr     : a_addr;
assign burstcnt = owner ? b_burstcnt : a_burstcnt;
assign din      = owner ? b_din      : a_din;
assign be       = owner ? b_be       : a_be;
assign rd       = o_rd & ~hold;
assign we       = o_we & ~hold;

assign a_busy  = owner | hold | busy;
assign b_busy  = ~owner | hold | busy;
assign a_ready = ~owner & ready;
assign b_ready =  owner & ready;

always @(posedge clk) begin
	if (reset) begin
		owner <= 0; hold <= 0; pend <= 0; waited <= 0;
	end
	else begin
		pend <= pend + ((rd & ~busy) ? {1'b0, burstcnt} : 9'd0) - (ready ? 9'd1 : 9'd0);
		waited <= x_req ? ((waited == 8'hFF) ? waited : waited + 8'd1) : 8'd0;
		if (x_req && waited == 8'hFF) hold <= 1;
		// hand over: the owner idle (or held) and nothing of its still to come
		if (x_req && (hold || !(o_rd | o_we)) && pend == 0 && !(ready) && !((rd | we) & ~busy)) begin
			owner <= ~owner; hold <= 0; waited <= 0;
		end
	end
end

endmodule
