-- -----------------------------------------------------------------------------------------------------
--  The CIA TOD 50/60 Hz input - (c) 2026 Mong00se (Exact 50 Hz, Fix 48)
--
--  On a real C64 the TOD clocks come from the mains (50 Hz in PAL lands), not from the CPU crystal. This
--  is the old generator from fpga64_sid_iec, moved out so it can be tested, with one change: in Exact 50 Hz
--  mode clk32 is 31,449,600 Hz, so it divides by that and the TOD still ticks at a true 50.000 Hz (exactly
--  one tick per video frame). Off (Original PAL) and NTSC it is exactly as before.
--  todclk toggles, so it toggles 100 (PAL) / 120 (NTSC) times a second.
-- -----------------------------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity cia_tod_clk is
	port (
		clk32    : in  std_logic;
		reset    : in  std_logic;
		ntscMode : in  std_logic;
		exact50  : in  std_logic;
		todclk   : out std_logic
	);
end entity;

architecture rtl of cia_tod_clk is
signal tod_r : std_logic := '0';
begin

todclk <= tod_r;

process(clk32)
variable sum: integer range 0 to 33000000;
begin
	if rising_edge(clk32) then
		if reset = '1' then
			tod_r <= '0';
			sum := 0;
		elsif ntscMode = '1' then
			sum := sum + 120;
			if sum >= 32727266 then
				sum := sum - 32727266;
				tod_r <= not tod_r;
			end if;
		elsif exact50 = '1' then
			sum := sum + 100;
			if sum >= 31449600 then
				sum := sum - 31449600;
				tod_r <= not tod_r;
			end if;
		else
			sum := sum + 100;
			if sum >= 31527954 then
				sum := sum - 31527954;
				tod_r <= not tod_r;
			end if;
		end if;
	end if;
end process;

end architecture;
