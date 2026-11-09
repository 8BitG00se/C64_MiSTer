---------------------------------------------------------------------------------
-- sid_mix.vhd - the Octophonic 64's eight-SID mix (Fix 28: the level).
-- Octophonic 64 and OctoVIC by Mong00se (github.com/8BitG00se). Original project by Mong00se.
--
-- SIDs in left/right pairs, odd SIDs (1, 3, 5, 7) left and even right - but a SID whose partner
-- has not played since the reset is in the middle, on both sides, so a one-SID game sounds as it
-- does on the stock core, a 2SID tune at $D420 is in stereo, and a 4- or 8-SID demo is spread out.
-- A SID that has never played adds nothing (SID 1 always counts). OctoSID FX SIDs add at half.
--
-- THE LEVEL (Fix 28, measured against VICE x64sc's reSID and reSID-fp, sim/level): each side's
-- SIDs are summed (no longer divided by how many play - that made four SIDs a side 12 dB quiet),
-- then, once a microsecond (ce, the SIDs' clock):
--   1 a DC blocker, about 10 Hz (h = sum - DC, DC += h / 2^14): a 6581's offset no longer uses up
--     the headroom (the MiSTer's own DC blocker after the core is at 15 Hz)
--   2 the gain: 1.25 at most, where one SID is as loud as in VICE
--   3 the soft limiter (full level to 3/4 of the range, a quarter above it), and the automatic gain
--     (both sides together): when either side goes past 3/4 of the range it is turned down 1/128
--     every microsecond (6 dB in about 90 us); otherwise it creeps back to 1.25 (an eighth of the
--     way in 0.28 s, all of it in about 6 s) - no pumping.
-- One SID (or one a side) never reaches 3/4, so it is the stock core's sound, only louder; eight
-- SIDs are as loud as they can be without going over. The emulator (octosid.c, mix_us) and
-- sim/level/rtlmodel.py do the same integer maths; sim/level/mixtest.sh checks this file with GHDL.
---------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity sid_mix is
port (
	clk      : in  std_logic;
	reset    : in  std_logic;
	ce       : in  std_logic;                       -- once a microsecond (the SIDs' clock)
	quad     : in  std_logic;                       -- OCTOPHONIC on (4 or 8 SIDs)
	oct      : in  std_logic;                       -- 8 SIDs
	played   : in  std_logic_vector(7 downto 0);    -- each SID played since the reset (and awake)
	fx_mode  : in  std_logic_vector(1 downto 0);    -- OctoSID FX: SID 2 (chorus), SIDs 3-4 (echo)
	sid1_l, sid1_r, sid2_l, sid2_r, sid3_l, sid3_r, sid4_l, sid4_r : in std_logic_vector(17 downto 0);
	out_l    : out signed(17 downto 0);
	out_r    : out signed(17 downto 0)
);
end sid_mix;

architecture rtl of sid_mix is

signal st         : std_logic_vector(2 downto 0) := "000";   -- the step strobes after ce
signal sum_l      : signed(21 downto 0) := (others => '0');  -- the sums
signal sum_r      : signed(21 downto 0) := (others => '0');
signal dc_l, dc_r : signed(37 downto 0) := (others => '0');  -- the DC blockers (the DC times 2^14)
signal h_l, h_r   : signed(23 downto 0) := (others => '0');  -- the sums less their DC
signal y_l, y_r   : signed(21 downto 0) := (others => '0');  -- after the gain
signal g          : unsigned(31 downto 0) := x"28000000";    -- the automatic gain, 1.0 = 2^29 (1.25 at most)
signal mix_l      : signed(17 downto 0) := (others => '0');
signal mix_r      : signed(17 downto 0) := (others => '0');

constant GMAX : unsigned(31 downto 0) := x"28000000";       -- 1.25

-- soft limiter: full level up to 3/4 of the range, then a quarter of anything above it, then the rail
function soft(x : signed(21 downto 0)) return signed is
	constant T  : signed(21 downto 0) := to_signed( 98304, 22);
	constant FS : signed(21 downto 0) := to_signed(131071, 22);
	variable y  : signed(21 downto 0);
begin
	y := x;
	if    x >  T then y :=  T + shift_right(x - T, 2); if y >  FS then y :=  FS; end if;
	elsif x < -T then y := -T + shift_right(x + T, 2); if y < -FS then y := -FS; end if;
	end if;
	return y(17 downto 0);
end function;

-- the gain: (h x gain(31 downto 13)) / 2^16, kept to 22 bits
function amp(h : signed(23 downto 0); gain : unsigned(31 downto 0)) return signed is
	variable p : signed(43 downto 0);
	variable v : signed(27 downto 0);
begin
	p := h * signed('0' & gain(31 downto 13));
	v := resize(shift_right(p, 16), 28);
	if    v >  2097151 then return to_signed( 2097151, 22);
	elsif v < -2097152 then return to_signed(-2097152, 22);
	else                    return v(21 downto 0);
	end if;
end function;

-- past the limiter's knee
function over(y : signed(21 downto 0)) return boolean is
begin
	return y > to_signed(98304, 22) or y < to_signed(-98304, 22);
end function;

begin

process(clk)
	type chip_out is array (0 to 7) of signed(17 downto 0);
	variable o         : chip_out;
	variable sl, sr    : signed(20 downto 0);   -- the program's own SIDs (dry)
	variable fl, fr    : signed(20 downto 0);   -- OctoSID FX: SIDs that only play the effect
	variable hl, hr    : signed(23 downto 0);
	variable pl, fx    : std_logic_vector(7 downto 0);
	variable onl, onr  : boolean;
begin
	if rising_edge(clk) then
		o := (signed(sid1_l), signed(sid1_r), signed(sid2_l), signed(sid2_r),
		      signed(sid3_l), signed(sid3_r), signed(sid4_l), signed(sid4_r));
		sl := (others => '0'); sr := (others => '0'); fl := (others => '0'); fr := (others => '0');
		pl := played; pl(0) := '1';   -- SID 1 always: a digi with no gate is still sound
		fx := (others => '0');
		-- OctoSID FX: its SIDs play - as the effect, on top of the program's sound, not as more SIDs to share the level with
		if fx_mode(0) = '1' and pl(1) = '0' then fx(1) := '1'; end if;
		if fx_mode(1) = '1' and pl(2) = '0' then fx(2) := '1'; end if;
		if fx_mode(1) = '1' and pl(3) = '0' then fx(3) := '1'; end if;
		pl := pl or fx;
		for c in 0 to 7 loop
			-- which side(s): its own, or both when its partner (c xor 1) has not played
			if c mod 2 = 0 then
				onl := true;  onr := pl(c + 1) = '0';
			else
				onr := true;  onl := pl(c - 1) = '0';
			end if;
			-- a pair past the mode, and a SID that has never played, add nothing
			if (c >= 2 and quad = '0') or (c >= 4 and oct = '0') or pl(c) = '0' then
				onl := false; onr := false;
			end if;
			if fx(c) = '1' then
				if onl then fl := fl + resize(o(c), 21); end if;
				if onr then fr := fr + resize(o(c), 21); end if;
			else
				if onl then sl := sl + resize(o(c), 21); end if;
				if onr then sr := sr + resize(o(c), 21); end if;
			end if;
		end loop;

		-- a microsecond's mix in four steps after ce (the SIDs move once a microsecond)
		st <= st(1 downto 0) & ce;
		-- 0: the sums - the dry sound, the effect at half that on top
		if ce = '1' then
			sum_l <= resize(sl, 22) + resize(shift_right(fl, 1), 22);
			sum_r <= resize(sr, 22) + resize(shift_right(fr, 1), 22);
		end if;
		-- 1: less the DC
		if st(0) = '1' then
			hl := resize(sum_l, 24) - resize(shift_right(dc_l, 14), 24);
			hr := resize(sum_r, 24) - resize(shift_right(dc_r, 14), 24);
			h_l <= hl; dc_l <= dc_l + resize(hl, 38);
			h_r <= hr; dc_r <= dc_r + resize(hr, 38);
		end if;
		-- 2: the gain
		if st(1) = '1' then
			y_l <= amp(h_l, g);
			y_r <= amp(h_r, g);
		end if;
		-- 3: the limiter; the automatic gain down fast when past the knee, else slowly back up
		if st(2) = '1' then
			mix_l <= soft(y_l);
			mix_r <= soft(y_r);
			if over(y_l) or over(y_r) then
				g <= g - shift_right(g, 7);
			else
				g <= g + shift_right(GMAX - g, 21);
			end if;
		end if;
		-- a reset (a new program) starts at the full gain
		if reset = '1' then
			g <= GMAX;
		end if;
	end if;
end process;

out_l <= mix_l;
out_r <= mix_r;

end rtl;
