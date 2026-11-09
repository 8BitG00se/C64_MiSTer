-- tb_sid_mix.vhd - runs rtl/sid_mix.vhd on the vectors mixvec.py makes (one line a microsecond:
-- reset quad oct played fx_mode s1l s1r s2l s2r s3l s3r s4l s4r) and writes its out_l out_r for
-- each microsecond. A microsecond is 8 clocks here (the core has 32; the mix needs 4).
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use std.textio.all;

entity tb_sid_mix is
end tb_sid_mix;

architecture sim of tb_sid_mix is
	signal clk, reset, ce, quad, oct : std_logic := '0';
	signal played  : std_logic_vector(7 downto 0) := (others => '0');
	signal fx_mode : std_logic_vector(1 downto 0) := "00";
	type v18 is array (0 to 7) of std_logic_vector(17 downto 0);
	signal s : v18 := (others => (others => '0'));
	signal out_l, out_r : signed(17 downto 0);
begin
	dut : entity work.sid_mix
	port map (clk => clk, reset => reset, ce => ce, quad => quad, oct => oct, played => played, fx_mode => fx_mode,
	          sid1_l => s(0), sid1_r => s(1), sid2_l => s(2), sid2_r => s(3),
	          sid3_l => s(4), sid3_r => s(5), sid4_l => s(6), sid4_r => s(7),
	          out_l => out_l, out_r => out_r);

	process
		file fi : text open read_mode is "vec.txt";
		file fo : text open write_mode is "out.txt";
		variable li, lo : line;
		variable v : integer;
	begin
		while not endfile(fi) loop
			readline(fi, li);
			read(li, v); if v = 1 then reset <= '1'; else reset <= '0'; end if;
			read(li, v); if v = 1 then quad <= '1'; else quad <= '0'; end if;
			read(li, v); if v = 1 then oct <= '1'; else oct <= '0'; end if;
			read(li, v); played <= std_logic_vector(to_unsigned(v, 8));
			read(li, v); fx_mode <= std_logic_vector(to_unsigned(v, 2));
			for c in 0 to 7 loop
				read(li, v); s(c) <= std_logic_vector(to_signed(v, 18));
			end loop;
			for k in 0 to 7 loop
				if k = 0 then ce <= '1'; else ce <= '0'; end if;
				wait for 5 ns; clk <= '1'; wait for 5 ns; clk <= '0';
			end loop;
			write(lo, to_integer(out_l)); write(lo, string'(" ")); write(lo, to_integer(out_r));
			writeline(fo, lo);
		end loop;
		wait;
	end process;
end sim;
