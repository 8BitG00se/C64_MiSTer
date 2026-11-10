// Behavioural stand-in for Altera's scfifo (show-ahead OFF), for the tape check only. (c) 2026 Mong00se
module scfifo #(parameter add_ram_output_register="OFF", intended_device_family="", lpm_numwords=64,
                lpm_showahead="OFF", lpm_type="scfifo", lpm_width=8, lpm_widthu=6,
                overflow_checking="ON", underflow_checking="ON", use_eab="ON")
(
	input aclr, input clock, input [lpm_width-1:0] data, input rdreq, input wrreq,
	output empty, output full, output reg [lpm_width-1:0] q
);
reg [lpm_width-1:0] mem [0:lpm_numwords-1];
reg [lpm_widthu:0] wp = 0, rp = 0;
assign empty = (wp == rp);
assign full  = ((wp - rp) == lpm_numwords);
always @(posedge clock or posedge aclr) begin
	if(aclr) begin wp <= 0; rp <= 0; end
	else begin
		if(wrreq && !full) begin mem[wp[lpm_widthu-1:0]] <= data; wp <= wp + 1'd1; end
		if(rdreq && !empty) begin q <= mem[rp[lpm_widthu-1:0]]; rp <= rp + 1'd1; end
	end
end
endmodule
