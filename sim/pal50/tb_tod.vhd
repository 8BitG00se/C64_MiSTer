-- Fix 48 check: cia_tod_clk - clk32 ticks per TOD tick (two toggles) in PAL, Exact 50 Hz and NTSC.
-- (c) 2026 Mong00se
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use std.textio.all;

entity tb_tod is
	generic ( NTSC : integer := 0; EXACT : integer := 0; TICKS : integer := 20 );
end entity;

architecture sim of tb_tod is
	signal clk : std_logic := '0';
	signal reset : std_logic := '1';
	signal n, e, tod : std_logic;
	signal done : boolean := false;
begin
	n <= '1' when NTSC = 1 else '0';
	e <= '1' when EXACT = 1 else '0';
	clk <= not clk after 1 ns when not done else '0';
	dut: entity work.cia_tod_clk port map ( clk32 => clk, reset => reset, ntscMode => n, exact50 => e, todclk => tod );
	process
		variable t, first : integer := 0;
		variable cnt : integer := 0;
		variable o : std_logic := '0';
		variable l : line;
	begin
		wait until rising_edge(clk); wait until rising_edge(clk);
		reset <= '0';
		loop
			wait until rising_edge(clk);
			t := t + 1;
			if tod = '1' and o = '0' then
				if cnt = 0 then first := t; end if;
				cnt := cnt + 1;
				exit when cnt = TICKS + 1;
			end if;
			o := tod;
		end loop;
		write(l, string'("TOD ")); write(l, TICKS); write(l, string'(" ticks in ")); write(l, t - first);
		write(l, string'(" clk32")); writeline(output, l);
		done <= true;
		wait;
	end process;
end architecture;
