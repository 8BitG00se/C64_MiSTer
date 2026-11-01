// OCTOPHONIC OS - the mailbox between the 6502 and Main (docs/OCTOOS.md).
//
// The 6502 sees 16 registers at $D6F0-$D6FF (the OctoVIC page, so OctoVIC must be unlocked):
//   F0 CMD     write: the command - it also sets STATUS to 1 (busy) and rings Main's bell
//   F1 STATUS  read: 0 idle, 1 busy, 2 done, $80+n error n
//   F2/F3 ADDR, F4/F5 LEN, F6 ARG, F7 VALUE   read/write, for the command and its answer
//   F8 NAME    write: the next character of the name (up to 32); read: how many there are
//   F9         write: empty the name
//   FA/FB RESULT   read: what the command gives back
//   FC VERSION read: 1
// Main reaches it through hps_io's EXT_BUS with three commands of its own:
//   70 poll    the reply word is $6F00 + pending
//   71 read    after the reply word, each word reads the next byte: the 16 registers, then the name
//   72 write   each word {register, value} writes a register; writing STATUS ends the request
// No block RAM: the name is kept in logic.

module octo_os
(
	input             clk,
	input             reset,

	input             cs,          // the 6502 is at $D6F0-$D6FF
	input             wr,
	input       [3:0] addr,
	input       [7:0] din,
	output reg  [7:0] dout,

	input             io_enable,   // hps_io's command link
	input             io_strobe,
	input      [15:0] io_din,
	output            ext_act,
	output     [15:0] ext_dout
);

reg  [7:0] r_cmd, r_status, r_addrl, r_addrh, r_lenl, r_lenh, r_arg, r_val, r_resl, r_resh;
(* ramstyle = "logic" *) reg [7:0] name [0:31];
reg  [5:0] nlen;
reg        pending;

reg        h_act, h_first;
reg  [7:0] h_cmd;
reg  [5:0] h_ptr;
reg [15:0] h_out;

assign ext_act  = h_act;
assign ext_dout = h_out;

wire [5:0] h_nidx = h_ptr - 6'd16;           // which name character h_ptr is at

function [7:0] regbyte(input [5:0] i);
	if (i[5] | i[4]) regbyte = (h_nidx < nlen) ? name[h_nidx[4:0]] : 8'd0;
	else case (i[3:0])
		4'h0: regbyte = r_cmd;    4'h1: regbyte = r_status;
		4'h2: regbyte = r_addrl;  4'h3: regbyte = r_addrh;
		4'h4: regbyte = r_lenl;   4'h5: regbyte = r_lenh;
		4'h6: regbyte = r_arg;    4'h7: regbyte = r_val;
		4'h8: regbyte = {2'b00, nlen};
		4'hA: regbyte = r_resl;   4'hB: regbyte = r_resh;
		4'hC: regbyte = 8'h01;
		default: regbyte = 8'h00;
	endcase
endfunction

always @(*) begin
	case (addr)
		4'h0: dout = r_cmd;    4'h1: dout = r_status;
		4'h2: dout = r_addrl;  4'h3: dout = r_addrh;
		4'h4: dout = r_lenl;   4'h5: dout = r_lenh;
		4'h6: dout = r_arg;    4'h7: dout = r_val;
		4'h8: dout = {2'b00, nlen};
		4'hA: dout = r_resl;   4'hB: dout = r_resh;
		4'hC: dout = 8'h01;
		default: dout = 8'hFF;
	endcase
end

always @(posedge clk) begin
	if (reset) begin
		{r_cmd, r_status, r_addrl, r_addrh, r_lenl, r_lenh, r_arg, r_val, r_resl, r_resh} <= 0;
		nlen    <= 0;
		pending <= 0;
	end
	else if (cs && wr) begin
		case (addr)
			4'h0: begin r_cmd <= din; r_status <= 8'h01; pending <= 1; end
			4'h2: r_addrl <= din;  4'h3: r_addrh <= din;
			4'h4: r_lenl  <= din;  4'h5: r_lenh  <= din;
			4'h6: r_arg   <= din;  4'h7: r_val   <= din;
			4'h8: if (!nlen[5]) begin name[nlen[4:0]] <= din; nlen <= nlen + 1'd1; end
			4'h9: nlen <= 0;
			default: ;
		endcase
	end

	// Main's side
	if (~io_enable) begin
		h_act   <= 0;
		h_first <= 1;
		h_out   <= 0;
	end
	else if (io_strobe) begin
		h_first <= 0;
		if (h_first) begin
			h_cmd <= io_din[7:0];
			h_ptr <= 0;
			if (io_din == 16'h70 || io_din == 16'h71 || io_din == 16'h72) begin
				h_act <= 1;
				h_out <= {8'h6F, 7'd0, pending};
			end
		end
		else if (h_act) begin
			if (h_cmd == 8'h71) begin
				h_out <= {8'h00, regbyte(h_ptr)};
				h_ptr <= h_ptr + 1'd1;
			end
			if (h_cmd == 8'h72) begin
				h_out <= 0;
				case (io_din[11:8])
					4'h1: begin r_status <= io_din[7:0]; pending <= 0; end
					4'h4: r_lenl <= io_din[7:0];  4'h5: r_lenh <= io_din[7:0];
					4'h6: r_arg  <= io_din[7:0];  4'h7: r_val  <= io_din[7:0];
					4'hA: r_resl <= io_din[7:0];  4'hB: r_resh <= io_din[7:0];
					default: ;
				endcase
			end
		end
	end
end

endmodule
