-- REWIND simulation: the palette is not what is tested - the testbench takes the VIC's colour index
-- (rgb_index) and colours it itself.                                   (c) 2026 Mong00se
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity fpga64_rgbcolor is
	port (
		palette: in unsigned(2 downto 0);
		index: in unsigned(3 downto 0);
		r: out unsigned(7 downto 0);
		g: out unsigned(7 downto 0);
		b: out unsigned(7 downto 0)
	);
end fpga64_rgbcolor;

architecture sim of fpga64_rgbcolor is
begin
	r <= index & index;
	g <= index & index;
	b <= index & index;
end sim;
