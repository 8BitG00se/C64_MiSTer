-- Fix 48 check: the VIC-II's frame length in clk32 ticks, PAL and NTSC, driven exactly the way
-- fpga64_sid_iec drives it (32 clk32 ticks a C64 cycle; enaData at VIC2/CPUE, pixels every 4 ticks,
-- phi high in the CPU half). Prints clk32 ticks per line and per frame between vsync rising edges.
-- (c) 2026 Mong00se
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use std.textio.all;

entity tb_vic is
	generic ( NTSC : integer := 0 );
end entity;

architecture sim of tb_vic is
	signal clk    : std_logic := '0';
	signal step   : unsigned(4 downto 0) := (others => '0');
	signal phi, enaData, enaPixel : std_logic := '0';
	signal reset  : std_logic := '1';
	signal hs, vs : std_logic;
	signal ntscm, palm : std_logic;
	signal done   : boolean := false;
begin
	ntscm <= '1' when NTSC = 1 else '0';
	palm  <= not ntscm;
	clk <= not clk after 15 ns when not done else '0';

	-- the fpga64_sid_iec sequencer (registered enables, as there)
	process(clk) begin
		if rising_edge(clk) then
			step <= step + 1;
			enaData  <= '0'; enaPixel <= '0';
			if step = 14 or step = 30 then enaData <= '1'; end if;
			if step(1 downto 0) = "10" then enaPixel <= '1'; end if;
			if step = 15 then phi <= '1'; end if;
			if step = 31 then phi <= '0'; end if;
		end if;
	end process;

	vic: entity work.video_vicii_656x
	generic map ( registeredAddress => true, emulateRefresh => true, emulateLightpen => true, emulateGraphics => true )
	port map (
		clk => clk, reset => reset, enaPixel => enaPixel, enaData => enaData, phi => phi,
		baSync => '0', ba => open, ba_dma => open,
		mode6569 => palm, mode6567old => '0', mode6567R8 => ntscm, mode6572 => '0', variant => "00",
		turbo_en => '0', turbo_state => open,
		cs => '0', we => '0', lp_n => '1',
		aRegisters => (others => '0'), diRegisters => (others => '0'),
		di => (others => '0'), diColor => (others => '0'), do => open,
		vicAddr => open, addrValid => open,
		hSync => hs, vSync => vs, colorIndex => open, rasterXo => open, rasterYo => open,
		debugX => open, debugY => open, vicRefresh => open, irq_n => open
	);

	process
		variable t, lastv, lasth : integer := 0;
		variable nv, nh : integer := 0;
		variable ovs, ohs : std_logic := '0';
		variable l : line;
	begin
		for i in 1 to 64 loop wait until rising_edge(clk); end loop;
		reset <= '0';
		loop
			wait until rising_edge(clk);
			t := t + 1;
			if hs = '1' and ohs = '0' then
				if nh >= 2 and nh < 6 then
					write(l, string'("LINE ")); write(l, t - lasth); writeline(output, l);
				end if;
				lasth := t; nh := nh + 1;
			end if;
			if vs = '1' and ovs = '0' then
				if nv >= 1 then
					write(l, string'("FRAME ")); write(l, t - lastv); writeline(output, l);
				end if;
				lastv := t; nv := nv + 1;
				exit when nv = 4;
			end if;
			ovs := vs; ohs := hs;
		end loop;
		done <= true;
		wait;
	end process;
end architecture;
