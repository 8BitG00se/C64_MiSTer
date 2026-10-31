-- -----------------------------------------------------------------------
--
--                                 FPGA 64
--
--     A fully functional commodore 64 implementation in a single FPGA
--
-- -----------------------------------------------------------------------
-- Peter Wendrich (pwsoft@syntiac.com)
-- http://www.syntiac.com/fpga64.html
-- -----------------------------------------------------------------------
--
-- System runs on 32 Mhz
-- The VIC-II runs in 4 cycles of first 16 cycles.
-- The CPU runs in the last 16 cycles. Effective cpu speed is 1 Mhz.
-- 
-- -----------------------------------------------------------------------
-- Dar 08/03/2014 
--
-- Based on fpga64_cone
-- add external selection for 15KHz(TV)/31KHz(VGA)
-- add external selection for power on NTSC(60Hz)/PAL(50Hz)
-- add external conection in/out for IEC signal
-- add sid entity 
-- -----------------------------------------------------------------------
-- 
-- Alexey Melnikov 2021
-- 
-- add dma engine
-- implement up to 4x turbo of C128 and smart types.
-- add user port signals
-- various fixes and tweaks
-- 
-- -----------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.ALL;
use IEEE.numeric_std.all;

-- -----------------------------------------------------------------------

entity fpga64_sid_iec is
port(
	clk32       : in  std_logic;
	reset_n     : in  std_logic;
	bios        : in  std_logic_vector(1 downto 0);
	
	pause       : in  std_logic := '0';
	pause_out   : out std_logic;

	-- keyboard interface (use any ordinairy PS2 keyboard)
	ps2_key     : in  std_logic_vector(10 downto 0);
	kbd_reset   : in  std_logic := '0';
	shift_mod   : in  std_logic_vector(1 downto 0);

	-- external memory
	ramAddr     : out unsigned(15 downto 0);
	ramDin      : in  unsigned(7 downto 0);
	ramDout     : out unsigned(7 downto 0);
	ramCE       : out std_logic;
	ramWE       : out std_logic;

	io_cycle    : out std_logic;
	ext_cycle   : out std_logic;
	refresh     : out std_logic;

	cia_mode    : in  std_logic;
	turbo_mode  : in  std_logic_vector(1 downto 0);
	turbo_speed : in  std_logic_vector(1 downto 0);

	-- VGA/SCART interface
	vic_variant : in  std_logic_vector(1 downto 0);
	ntscMode    : in  std_logic;
	hsync       : out std_logic;
	vsync       : out std_logic;
	palette     : in  unsigned(2 downto 0);
	r           : out unsigned(7 downto 0);
	g           : out unsigned(7 downto 0);
	b           : out unsigned(7 downto 0);

	-- cartridge port
	game        : in  std_logic;
	exrom       : in  std_logic;
	io_rom      : in  std_logic;
	io_ext      : in  std_logic;
	io_data     : in  unsigned(7 downto 0);
	irq_n       : in  std_logic;
	nmi_n       : in  std_logic;
	nmi_ack     : out std_logic;
	romL        : out std_logic;
	romH        : out std_logic;
	UMAXromH 	: out std_logic;
	IOE			: out std_logic;
	IOF			: out std_logic;
	freeze_key  : out std_logic;
	mod_key     : out std_logic;
	tape_play   : out std_logic;
	tape_rew    : out std_logic;
	tape_stop   : out std_logic;
	tape_ff     : out std_logic;
	tape_reset_counter : out std_logic;

	-- dma access
	dma_req     : in  std_logic := '0';
	dma_cycle   : out std_logic;
	dma_addr    : in  unsigned(15 downto 0) := (others => '0');
	dma_dout    : in  unsigned(7 downto 0) := (others => '0');
	dma_din     : out unsigned(7 downto 0);
	dma_we      : in  std_logic := '0';
	irq_ext_n   : in  std_logic := '1';

	-- joystick interface
	joyA        : in  std_logic_vector(6 downto 0);
	joyB        : in  std_logic_vector(6 downto 0);
	pot1        : in  std_logic_vector(7 downto 0);
	pot2        : in  std_logic_vector(7 downto 0);
	pot3        : in  std_logic_vector(7 downto 0);
	pot4        : in  std_logic_vector(7 downto 0);

	--SID
	audio_l     : out std_logic_vector(17 downto 0);
	audio_r     : out std_logic_vector(17 downto 0);
	sid_filter  : in  std_logic_vector(1 downto 0);
	sid_ver     : in  std_logic_vector(1 downto 0);
	sid_mode    : in  unsigned(2 downto 0);
	sid_cfg     : in  std_logic_vector(3 downto 0);
	sid_fc_off_l: in  std_logic_vector(12 downto 0);
	sid_fc_off_r: in  std_logic_vector(12 downto 0);
	sid_ld_clk  : in  std_logic;
	sid_ld_addr : in  std_logic_vector(11 downto 0);
	sid_ld_data : in  std_logic_vector(15 downto 0);
	sid_ld_wr   : in  std_logic;
	sid_digifix : in  std_logic;
	-- OCTOPHONIC: '1' four SIDs - $D400, $D420, $D500, $D520 (the Ultimate 64's layout)
	sid_quad    : in  std_logic := '0';
	-- OCTOPHONIC: '1' (with sid_quad) eight SIDs - A7 picks two more pairs:
	-- $D480, $D4A0, $D580, $D5A0 (the layout 8-SID music such as The Tuneful Eight uses)
	sid_oct     : in  std_logic := '0';
	-- OCTOPHONIC: OctoSID FX from the menu (b0 chorus, b1 echo) - see rtl/octovic/sid_fx.sv
	sid_fx_osd  : in  std_logic_vector(1 downto 0) := "00";

	-- OCTOPHONIC: OctoVIC's VRAM, in the DDR3 (docs/OCTOVIC.md)
	ogx_ddr_addr       : out std_logic_vector(28 downto 0);
	ogx_ddr_burstcnt   : out std_logic_vector(7 downto 0);
	ogx_ddr_rd         : out std_logic;
	ogx_ddr_we         : out std_logic;
	ogx_ddr_din        : out std_logic_vector(63 downto 0);
	ogx_ddr_be         : out std_logic_vector(7 downto 0);
	ogx_ddr_busy       : in  std_logic := '1';
	ogx_ddr_dout       : in  std_logic_vector(63 downto 0) := (others => '0');
	ogx_ddr_dout_ready : in  std_logic := '0';
	
	-- USER
	pb_i        : in  unsigned(7 downto 0);
	pb_o        : out unsigned(7 downto 0);
	pa2_i       : in  std_logic;
	pa2_o       : out std_logic;
	pc2_n_o     : out std_logic;
	flag2_n_i   : in  std_logic;
	sp2_i       : in  std_logic;
	sp2_o       : out std_logic;
	sp1_i       : in  std_logic;
	sp1_o       : out std_logic;
	cnt2_i      : in  std_logic;
	cnt2_o      : out std_logic;
	cnt1_i      : in  std_logic;
	cnt1_o      : out std_logic;

	-- IEC
	iec_data_o	: out std_logic;
	iec_data_i	: in  std_logic;
	iec_clk_o	: out std_logic;
	iec_clk_i	: in  std_logic;
	iec_atn_o	: out std_logic;
	
	c64rom_addr : in  std_logic_vector(13 downto 0);
	c64rom_data : in  std_logic_vector(7 downto 0);
	c64rom_wr   : in  std_logic;

	cass_motor  : out std_logic;
	cass_write  : out std_logic;
	cass_sense  : in  std_logic;
	cass_read   : in  std_logic
);
end fpga64_sid_iec;

-- -----------------------------------------------------------------------

architecture rtl of fpga64_sid_iec is
-- System state machine
type sysCycleDef is (
	CYCLE_EXT0, CYCLE_EXT1, CYCLE_EXT2, CYCLE_EXT3,
	CYCLE_DMA0, CYCLE_DMA1, CYCLE_DMA2, CYCLE_DMA3,
	CYCLE_EXT4, CYCLE_EXT5, CYCLE_EXT6, CYCLE_EXT7,
	CYCLE_VIC0, CYCLE_VIC1, CYCLE_VIC2, CYCLE_VIC3,
	CYCLE_CPU0, CYCLE_CPU1, CYCLE_CPU2, CYCLE_CPU3,
	CYCLE_CPU4, CYCLE_CPU5, CYCLE_CPU6, CYCLE_CPU7,
	CYCLE_CPU8, CYCLE_CPU9, CYCLE_CPUA, CYCLE_CPUB,
	CYCLE_CPUC, CYCLE_CPUD, CYCLE_CPUE, CYCLE_CPUF
);

signal sysCycle     : sysCycleDef := sysCycleDef'low;
signal preCycle     : sysCycleDef := sysCycleDef'low;
signal sysEnable    : std_logic;
signal rfsh_cycle   : unsigned(1 downto 0);

signal dma_active   : std_logic;

signal phi0_cpu     : std_logic;
signal cpuHasBus    : std_logic;

signal baLoc        : std_logic;
signal ba_dma       : std_logic;
signal aec          : std_logic;

signal enableCpu    : std_logic;
signal enableVic    : std_logic;
signal enablePixel  : std_logic;
signal enableSid    : std_logic;

signal irq_cia1     : std_logic;
signal irq_cia2     : std_logic;
signal irq_vic      : std_logic;
signal octo_irq     : std_logic;   -- OCTOPHONIC: OctoVIC 2's interrupt

signal systemWe     : std_logic;
signal pulseWr_io   : std_logic;
signal systemAddr   : unsigned(15 downto 0);

signal cs_io        : std_logic;
signal cs_vic       : std_logic;
signal cs_sid       : std_logic;
signal cs_color     : std_logic;
signal cs_cia1      : std_logic;
signal cs_cia2      : std_logic;
signal cs_ram       : std_logic;
signal cpuWe        : std_logic;
signal cpuWe_pre    : std_logic;
signal cpuAddr      : unsigned(15 downto 0);
signal cpuAddr_pre  : unsigned(15 downto 0);
signal cpuDi        : unsigned(7 downto 0);
signal cpuDo        : unsigned(7 downto 0);
signal cpuDo_pre    : unsigned(7 downto 0);
signal cpuIO        : unsigned(7 downto 0);
signal io_data_i    : unsigned(7 downto 0);
signal ioe_i        : std_logic;
signal iof_i        : std_logic;

signal io_enable    : std_logic;
signal cpu_cyc      : std_logic;
signal cpu_cyc_s    : std_logic_vector(1 downto 0);
signal turbo_m      : std_logic_vector(2 downto 0);

signal reset        : std_logic := '1';

-- CIA signals
signal enableCia_p  : std_logic;
signal enableCia_n  : std_logic;
signal cia1Do       : unsigned(7 downto 0);
signal cia2Do       : unsigned(7 downto 0);
signal cia1_pai     : unsigned(7 downto 0);
signal cia1_pao     : unsigned(7 downto 0);
signal cia1_pbi     : unsigned(7 downto 0);
signal cia1_pbo     : unsigned(7 downto 0);
signal cia2_pai     : unsigned(7 downto 0);
signal cia2_pao     : unsigned(7 downto 0);
signal cia2_pbi     : unsigned(7 downto 0);
signal cia2_pbo     : unsigned(7 downto 0);
signal cia2_pbe     : unsigned(7 downto 0);

signal todclk       : std_logic;

-- video
signal vicColorIndex: unsigned(3 downto 0);
-- OCTOPHONIC: OctoVIC
signal vicRasterX   : unsigned(9 downto 0);
signal vicRasterY   : unsigned(8 downto 0);
signal pal_r        : unsigned(7 downto 0);
signal pal_g        : unsigned(7 downto 0);
signal pal_b        : unsigned(7 downto 0);
signal octo_unlock  : std_logic := '0';
signal octo_stage   : std_logic := '0';
signal cs_octo      : std_logic;
signal cs_sid_s     : std_logic;
-- OctoSID FX: SID 1 spread over SIDs 2-4 (the menu, or OctoVIC's register $C0)
signal sidfx_reg    : std_logic_vector(1 downto 0);
signal sidfx_mode   : std_logic_vector(1 downto 0);
signal fx_we        : std_logic;
signal fx_tgt       : std_logic_vector(1 downto 0);
signal fx_addr      : std_logic_vector(4 downto 0);
signal fx_data      : std_logic_vector(7 downto 0);
signal fx1, fx2, fx3 : std_logic;
signal p1_addr, p2_addr : unsigned(4 downto 0);
signal p1_data, p2_data : unsigned(7 downto 0);
signal octo_do      : std_logic_vector(7 downto 0);
signal pulseRd_io   : std_logic;
signal octo_rgb     : std_logic_vector(23 downto 0);
signal vicBus       : unsigned(7 downto 0);
signal vicDi        : unsigned(7 downto 0);
signal vicDiAec     : unsigned(7 downto 0);
signal vicAddr      : unsigned(15 downto 0);
signal vicData      : unsigned(7 downto 0);
signal lastVicDi    : unsigned(7 downto 0);
signal vicAddr1514  : unsigned(1 downto 0);
signal colorData    : unsigned(3 downto 0);
signal colorDataAec : unsigned(3 downto 0);
signal turbo_en     : std_logic;
signal turbo_state  : std_logic;

-- SID signals
signal sid_do       : unsigned(7 downto 0);
signal sid_rd       : unsigned(7 downto 0);
signal sid_sel_l    : std_logic;
signal sid_sel_r    : std_logic;
signal sid_sel_ln   : std_logic;
signal sid_sel_rn   : std_logic;
-- OCTOPHONIC: the second pair, SIDs 3 and 4
signal sid2_do      : unsigned(7 downto 0);
signal sid2_sel_l   : std_logic;
signal sid2_sel_r   : std_logic;
signal sid1_aud_l   : std_logic_vector(17 downto 0);
signal sid1_aud_r   : std_logic_vector(17 downto 0);
signal sid2_aud_l   : std_logic_vector(17 downto 0);
signal sid2_aud_r   : std_logic_vector(17 downto 0);
-- OCTOPHONIC: the third and fourth pairs, SIDs 5 to 8
signal sid_a7       : std_logic;
signal sid_played   : std_logic_vector(7 downto 0);
signal mix_l, mix_r : signed(17 downto 0);
signal sid3_do      : unsigned(7 downto 0);
signal sid3_sel_l   : std_logic;
signal sid3_sel_r   : std_logic;
signal sid4_do      : unsigned(7 downto 0);
signal sid4_sel_l   : std_logic;
signal sid4_sel_r   : std_logic;
signal sid3_aud_l   : std_logic_vector(17 downto 0);
signal sid3_aud_r   : std_logic_vector(17 downto 0);
signal sid4_aud_l   : std_logic_vector(17 downto 0);
signal sid4_aud_r   : std_logic_vector(17 downto 0);
signal pot_x1       : std_logic_vector(7 downto 0);
signal pot_y1       : std_logic_vector(7 downto 0);
signal pot_x2       : std_logic_vector(7 downto 0);
signal pot_y2       : std_logic_vector(7 downto 0);

component sid_top
	port (
		reset         : in  std_logic;
		clk           : in  std_logic;
		ce_1m         : in  std_logic;

		cs            : in  std_logic_vector(1 downto 0);
		we            : in  std_logic;
		addr          : in  unsigned(4 downto 0);
		data_in       : in  unsigned(7 downto 0);
		data_out      : out unsigned(7 downto 0);

		pot_x_l       : in  std_logic_vector(7 downto 0) := (others => '0');
		pot_y_l       : in  std_logic_vector(7 downto 0) := (others => '0');
		pot_x_r       : in  std_logic_vector(7 downto 0) := (others => '0');
		pot_y_r       : in  std_logic_vector(7 downto 0) := (others => '0');

		audio_l       : out std_logic_vector(17 downto 0);
		audio_r       : out std_logic_vector(17 downto 0);

		ext_in_l      : in  std_logic_vector(17 downto 0);
		ext_in_r      : in  std_logic_vector(17 downto 0);

		fc_offset_l   : in  std_logic_vector(12 downto 0);
		fc_offset_r   : in  std_logic_vector(12 downto 0);

		filter_en     : in  std_logic_vector(1 downto 0);
		mode          : in  std_logic_vector(1 downto 0);
		cfg           : in  std_logic_vector(3 downto 0);

		ld_clk        : in  std_logic;
		ld_addr       : in  std_logic_vector(11 downto 0);
		ld_data       : in  std_logic_vector(15 downto 0);
		ld_wr         : in  std_logic
  );
end component;

component sid_fx
	port (
		clk      : in  std_logic;
		reset    : in  std_logic;
		ce_1m    : in  std_logic;
		mode     : in  std_logic_vector(1 downto 0);
		cpu_wr   : in  std_logic;
		sid1_wr  : in  std_logic;
		addr     : in  std_logic_vector(4 downto 0);
		data     : in  std_logic_vector(7 downto 0);
		busy1    : in  std_logic;
		busy2    : in  std_logic;
		inj_we   : out std_logic;
		inj_tgt  : out std_logic_vector(1 downto 0);
		inj_addr : out std_logic_vector(4 downto 0);
		inj_data : out std_logic_vector(7 downto 0)
	);
end component;

component octovic
port (
	clk            : in  std_logic;
	reset          : in  std_logic;
	cs             : in  std_logic;
	wr             : in  std_logic;
	rd             : in  std_logic;
	addr           : in  std_logic_vector(7 downto 0);
	din            : in  std_logic_vector(7 downto 0);
	dout           : out std_logic_vector(7 downto 0);
	pix_en         : in  std_logic;
	vic_x          : in  std_logic_vector(9 downto 0);
	vic_y          : in  std_logic_vector(8 downto 0);
	vic_index      : in  std_logic_vector(3 downto 0);
	vic_rgb        : in  std_logic_vector(23 downto 0);
	rgb            : out std_logic_vector(23 downto 0);
	ddr_addr       : out std_logic_vector(28 downto 0);
	ddr_burstcnt   : out std_logic_vector(7 downto 0);
	ddr_rd         : out std_logic;
	ddr_we         : out std_logic;
	ddr_din        : out std_logic_vector(63 downto 0);
	ddr_be         : out std_logic_vector(7 downto 0);
	ddr_busy       : in  std_logic;
	ddr_dout       : in  std_logic_vector(63 downto 0);
	ddr_dout_ready : in  std_logic;
	irq            : out std_logic
);
end component;

component mos6526
	PORT (
		clk           : in  std_logic;
		mode          : in  std_logic := '0'; -- 0 - 6526 "old", 1 - 8521 "new"
		phi2_p        : in  std_logic;
		phi2_n        : in  std_logic;
		res_n         : in  std_logic;
		cs_n          : in  std_logic;
		rw            : in  std_logic; -- '1' - read, '0' - write
		rs            : in  unsigned(3 downto 0);
		db_in         : in  unsigned(7 downto 0);
		db_out        : out unsigned(7 downto 0);
		pa_in         : in  unsigned(7 downto 0);
		pa_out        : out unsigned(7 downto 0);
		pa_oe         : out unsigned(7 downto 0);
		pb_in         : in  unsigned(7 downto 0);
		pb_out        : out unsigned(7 downto 0);
		pb_oe         : out unsigned(7 downto 0);
		flag_n        : in  std_logic;
		pc_n          : out std_logic;
		tod           : in  std_logic;
		sp_in         : in  std_logic;
		sp_out        : out std_logic;
		cnt_in        : in  std_logic;
		cnt_out       : out std_logic;
		irq_n         : out std_logic
	);
end component; 

begin

-- -----------------------------------------------------------------------
-- Local signal to outside world
-- -----------------------------------------------------------------------

io_cycle <= '1' when
	(sysCycle >= CYCLE_EXT0 and sysCycle <= CYCLE_EXT3) or
	(sysCycle >= CYCLE_EXT4 and sysCycle <= CYCLE_EXT7 and rfsh_cycle /= "00")  else '0';

-- -----------------------------------------------------------------------
-- System state machine, controls bus accesses
-- and triggers enables of other components
-- -----------------------------------------------------------------------

sysCycle <= preCycle when sysEnable = '1' else CYCLE_EXT4;
pause_out <= not sysEnable;

process(clk32)
begin
	if rising_edge(clk32) then
		preCycle <= sysCycleDef'succ(preCycle);
		if preCycle = sysCycleDef'high then
			preCycle <= sysCycleDef'low;
			if sysEnable = '1' then
				rfsh_cycle <= rfsh_cycle + 1;
			end if;
		end if;
		
		refresh <= '0';
		if preCycle = sysCycleDef'pred(CYCLE_EXT4) and rfsh_cycle = "00" then
			sysEnable <= not pause;
			refresh <= '1';
		end if;
	end if;
end process;

process(clk32)
begin
	if rising_edge(clk32) then
		if preCycle = sysCycleDef'high then
			reset <= not reset_n;
		end if;
	end if;
end process;

-- PHI0/2-clock emulation
process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = sysCycleDef'pred(CYCLE_CPU0) then
			phi0_cpu <= '1';
			if baLoc = '1' or (cpuWe = '1' and dma_active = '0') or (ba_dma = '1' and dma_active = '1') then
				cpuHasBus <= '1';
			end if;
		end if;
		if sysCycle = sysCycleDef'high then
			phi0_cpu <= '0';
			cpuHasBus <= '0';
		end if;
	end if;
end process;

process(clk32)
begin
	if rising_edge(clk32) then
		enableVic <= '0';
		enableCia_n <= '0';
		enableCia_p <= '0';
		enableSid <= '0';

		case sysCycle is
		when CYCLE_VIC2 =>
			enableVic <= '1';
		when CYCLE_CPUE =>
			enableVic <= '1';
		when CYCLE_CPUC =>
			enableCia_n <= '1';
		when CYCLE_CPUF =>
			enableCia_p <= '1';
			enableSid <= '1';
		when others =>
			null;
		end case;
	end if;
end process;

-- -----------------------------------------------------------------------
-- Color RAM
-- -----------------------------------------------------------------------
colorram: entity work.spram
generic map (
	DATA_WIDTH => 4,
	ADDR_WIDTH => 10
)
port map (
	clk => clk32,
	we => cs_color and pulseWr_io,
	addr => systemAddr(9 downto 0),
	data => cpuDo(3 downto 0),
	q => colorData
);

-- -----------------------------------------------------------------------
-- PLA and bus-switches
-- -----------------------------------------------------------------------
buslogic: entity work.fpga64_buslogic
port map (
	clk => clk32,
	reset => reset,
	bios => bios,

	cpuHasBus => cpuHasBus,
	aec => aec,

	bankSwitch => cpuIO(2 downto 0),

	game => game,
	exrom => exrom,
	io_rom => io_rom,
	io_ext => io_ext or sid_sel_r or sid2_sel_l or sid2_sel_r or sid3_sel_l or sid3_sel_r or sid4_sel_l or sid4_sel_r,
	io_data => io_data_i,

	ramData => ramDin,

	cpuWe => cpuWe,
	cpuAddr => cpuAddr,
	cpuData => cpuDo,
	vicAddr => vicAddr,
	vicData => vicData,
	sidData => sid_rd,
	colorData => colorData,
	cia1Data => cia1Do,
	cia2Data => cia2Do,
	lastVicData => lastVicDi,

	systemWe => systemWe,
	systemAddr => systemAddr,
	dataToCpu => cpuDi,
	dataToVic => vicDi,

	io_enable => io_enable,

	cs_vic => cs_vic,
	cs_sid => cs_sid,
	cs_color => cs_color,
	cs_cia1 => cs_cia1,
	cs_cia2 => cs_cia2,
	cs_ram => cs_ram,
	cs_ioE => ioe_i,
	cs_ioF => iof_i,
	cs_romL => romL,
	cs_romH => romH,
	cs_UMAXromH => UMAXromH,

	c64rom_addr => c64rom_addr,
	c64rom_data => c64rom_data,
	c64rom_wr => c64rom_wr
);

IOE <= ioe_i;
IOF <= iof_i;
cs_io <= cs_vic or cs_sid or cs_color or cs_cia1 or cs_cia2 or ioe_i or iof_i;

process(clk32)
begin
	if rising_edge(clk32) then
		pulseWr_io <= '0';
		if cpuWe = '1' then
			if sysCycle = CYCLE_CPUC then
				pulseWr_io <= '1';
			end if;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- VIC-II video interface chip
-- -----------------------------------------------------------------------
process(clk32)
begin
	if rising_edge(clk32) then
		if phi0_cpu = '1' then
			if cpuWe = '1' and cs_vic = '1' then
				vicBus <= cpuDo;
			else
				vicBus <= x"FF";
			end if;
		end if;
	end if;
end process;

-- In the first three cycles after BA went low, the VIC reads
-- $ff as character pointers and
-- as color information the lower 4 bits of the opcode after the access to $d011.
vicDiAec <= vicBus when aec = '0' else vicDi;
colorDataAec <= cpuDi(3 downto 0) when aec = '0' else colorData;

vic: entity work.video_vicii_656x
generic map (
	registeredAddress => true,
	emulateRefresh => true,
	emulateLightpen => true,
	emulateGraphics => true
)			
port map (
	clk => clk32,
	reset => reset,
	enaPixel => enablePixel,
	enaData => enableVic,
	phi => phi0_cpu,
	
	baSync => '0',
	ba => baLoc,
	ba_dma => ba_dma,

	mode6569 => (not ntscMode),
	mode6567old => '0',
	mode6567R8 => ntscMode,
	mode6572 => '0',
	variant => vic_variant,

	turbo_en => turbo_en,
	turbo_state => turbo_state,
	
	cs => cs_vic,
	we => cpuWe,
	lp_n => cia1_pbi(4),

	aRegisters => cpuAddr(5 downto 0),
	diRegisters => cpuDo,
	di => vicDiAec,
	diColor => colorDataAec,
	do => vicData,

	vicAddr => vicAddr(13 downto 0),
	addrValid => aec,
	
	hsync => hSync,
	vsync => vSync,
	colorIndex => vicColorIndex,
	rasterXo => vicRasterX,
	rasterYo => vicRasterY,

	irq_n => irq_vic
);

c64colors: entity work.fpga64_rgbcolor
port map (
	palette => palette,
	index => vicColorIndex,
	r => pal_r,
	g => pal_g,
	b => pal_b
);

-- OCTOPHONIC: OctoVIC (docs/OCTOVIC.md). Hidden until $4F then $38 are written to $D03F (an
-- unused VIC register); then $D600-$D6FF are its registers instead of SID mirrors.
process(clk32)
begin
	if rising_edge(clk32) then
		if reset = '1' then
			octo_unlock <= '0'; octo_stage <= '0';
		elsif pulseWr_io = '1' and cs_vic = '1' and cpuAddr(5 downto 0) = "111111" then
			if cpuDo = x"4F" then
				octo_stage <= '1';
			elsif cpuDo = x"38" and octo_stage = '1' then
				octo_unlock <= '1'; octo_stage <= '0';
			else
				octo_unlock <= '0'; octo_stage <= '0';
			end if;
		end if;
	end if;
end process;

cs_octo  <= cs_sid and octo_unlock and cpuAddr(9) and not cpuAddr(8);
cs_sid_s <= cs_sid and not cs_octo;

-- OCTOSID FX (rtl/octovic/sid_fx.sv): its register, OctoVIC's $C0 (b0 chorus, b1 echo); on
-- with the menu's setting or the register's; only with 4 or 8 SIDs (it plays on SIDs 2-4)
process(clk32)
begin
	if rising_edge(clk32) then
		if reset = '1' then
			sidfx_reg <= "00";
		elsif pulseWr_io = '1' and cs_octo = '1' and cpuAddr(7 downto 0) = x"C0" then
			sidfx_reg <= std_logic_vector(cpuDo(1 downto 0));
		end if;
	end if;
end process;
sidfx_mode <= (sid_fx_osd or sidfx_reg) when sid_quad = '1' else "00";

fx : sid_fx
port map (
	clk      => clk32,
	reset    => reset,
	ce_1m    => enableSid,
	mode     => sidfx_mode,
	cpu_wr   => pulseWr_io,
	sid1_wr  => pulseWr_io and sid_sel_l,
	addr     => std_logic_vector(cpuAddr(4 downto 0)),
	data     => std_logic_vector(cpuDo),
	busy1    => sid_sel_l or sid_sel_r,
	busy2    => sid2_sel_l or sid2_sel_r,
	inj_we   => fx_we,
	inj_tgt  => fx_tgt,
	inj_addr => fx_addr,
	inj_data => fx_data
);
fx1 <= fx_we when fx_tgt = "01" else '0';     -- SID 2
fx2 <= fx_we when fx_tgt = "10" else '0';     -- SID 3
fx3 <= fx_we when fx_tgt = "11" else '0';     -- SID 4
p1_addr <= unsigned(fx_addr) when fx1 = '1' else cpuAddr(4 downto 0);
p1_data <= unsigned(fx_data) when fx1 = '1' else cpuDo;
p2_addr <= unsigned(fx_addr) when (fx2 or fx3) = '1' else cpuAddr(4 downto 0);
p2_data <= unsigned(fx_data) when (fx2 or fx3) = '1' else cpuDo;

-- a read of OctoVIC: its side effects (VDATA moving on) want a pulse - the clock the 6510
-- really takes the byte (not while the VIC holds it with RDY, when it would read again)
pulseRd_io <= enableCpu and not dma_active and baLoc and not cpuWe;

octo: octovic
port map (
	clk            => clk32,
	reset          => reset,
	cs             => cs_octo,
	wr             => pulseWr_io,
	rd             => pulseRd_io,
	addr           => std_logic_vector(cpuAddr(7 downto 0)),
	din            => std_logic_vector(cpuDo),
	dout           => octo_do,
	pix_en         => enablePixel,
	vic_x          => std_logic_vector(vicRasterX),
	vic_y          => std_logic_vector(vicRasterY),
	vic_index      => std_logic_vector(vicColorIndex),
	vic_rgb        => std_logic_vector(pal_r & pal_g & pal_b),
	rgb            => octo_rgb,
	ddr_addr       => ogx_ddr_addr,
	ddr_burstcnt   => ogx_ddr_burstcnt,
	ddr_rd         => ogx_ddr_rd,
	ddr_we         => ogx_ddr_we,
	ddr_din        => ogx_ddr_din,
	ddr_be         => ogx_ddr_be,
	ddr_busy       => ogx_ddr_busy,
	ddr_dout       => ogx_ddr_dout,
	ddr_dout_ready => ogx_ddr_dout_ready,
	irq            => octo_irq
);

r <= unsigned(octo_rgb(23 downto 16));
g <= unsigned(octo_rgb(15 downto 8));
b <= unsigned(octo_rgb(7 downto 0));

process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = CYCLE_VIC3 then
			lastVicDi <= vicDi;
		end if;
	end if;
end process;

-- VIC bank to address lines
-- 
-- The glue logic on a C64C will generate a glitch during 10 <-> 01
-- generating 00 (in other words, bank 3) for one cycle.
--
-- When using the data direction register to change a single bit 0->1
-- (in other words, decreasing the video bank number by 1 or 2),
-- the bank change is delayed by one cycle. This effect is unstable.
process(clk32)
begin
	if rising_edge(clk32) then
		if phi0_cpu = '0' and enableVic = '1' then
			vicAddr1514 <= not cia2_pao(1 downto 0);
		end if;
	end if;
end process;

-- emulate only the first glitch (enough for Undead from Emulamer)
vicAddr(15 downto 14) <= "11" when ((vicAddr1514 xor not cia2_pao(1 downto 0)) = "11") and (cia2_pao(0) /= cia2_pao(1)) else not unsigned(cia2_pao(1 downto 0));

-- Pixel timing
process(clk32)
begin
	if rising_edge(clk32) then
		enablePixel <= '0';
		if sysCycle = CYCLE_VIC2
		or sysCycle = CYCLE_EXT2
		or sysCycle = CYCLE_DMA2
		or sysCycle = CYCLE_EXT6
		or sysCycle = CYCLE_CPU2
		or sysCycle = CYCLE_CPU6
		or sysCycle = CYCLE_CPUA
		or sysCycle = CYCLE_CPUE then
			enablePixel <= '1';
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- SID
-- -----------------------------------------------------------------------

--	Right SID Port: Same,DE00,D420,D500,DF00

sid_sel_ln <= cs_sid_s when sid_mode(2 downto 1) /= 1 else (cs_sid_s and ((not sid_mode(0) and not cpuAddr(5)) or (sid_mode(0) and not cpuAddr(8))));
sid_sel_rn <= sid_sel_ln when sid_mode = 0 else ioe_i when sid_mode = 1 else iof_i when sid_mode = 4 else (cs_sid_s and not sid_sel_ln);

-- OCTOPHONIC (four SIDs): A5 picks the left or right of a pair, A8 the pair -
-- $D400 SID 1, $D420 SID 2, $D500 SID 3, $D520 SID 4. Off, the core is as it was.
-- Eight SIDs: A7 as well - $D480 SID 5, $D4A0 SID 6, $D580 SID 7, $D5A0 SID 8 (four,
-- A7 is ignored: those addresses mirror SIDs 1 to 4, as before).
sid_a7     <= cpuAddr(7) and sid_oct;
sid_sel_l  <= sid_sel_ln when sid_quad = '0' else (cs_sid_s and not cpuAddr(5) and not cpuAddr(8) and not sid_a7);
sid_sel_r  <= sid_sel_rn when sid_quad = '0' else (cs_sid_s and     cpuAddr(5) and not cpuAddr(8) and not sid_a7);
sid2_sel_l <= '0'        when sid_quad = '0' else (cs_sid_s and not cpuAddr(5) and     cpuAddr(8) and not sid_a7);
sid2_sel_r <= '0'        when sid_quad = '0' else (cs_sid_s and     cpuAddr(5) and     cpuAddr(8) and not sid_a7);
sid3_sel_l <= '0'        when sid_quad = '0' else (cs_sid_s and not cpuAddr(5) and not cpuAddr(8) and     sid_a7);
sid3_sel_r <= '0'        when sid_quad = '0' else (cs_sid_s and     cpuAddr(5) and not cpuAddr(8) and     sid_a7);
sid4_sel_l <= '0'        when sid_quad = '0' else (cs_sid_s and not cpuAddr(5) and     cpuAddr(8) and     sid_a7);
sid4_sel_r <= '0'        when sid_quad = '0' else (cs_sid_s and     cpuAddr(5) and     cpuAddr(8) and     sid_a7);

io_data_i <= io_data when io_ext = '1' else
             sid4_do when (sid4_sel_l or sid4_sel_r) = '1' else
             sid3_do when (sid3_sel_l or sid3_sel_r) = '1' else
             sid2_do when (sid2_sel_l or sid2_sel_r) = '1' else
             sid_do  when sid_sel_r = '1' else (others => '1');

-- A READ of SIDs 3 to 8 (OCTOPHONIC): the bus logic hands the processor sidData for all of
-- $D400-$D7FF (io_data only for $DE00/$DF00), so sidData is the SID picked, not always the
-- first pair - before this, SIDs 3 to 8 read back SID 2's last byte, their OSC3 and ENV3
-- never moved, and a SID finder (the OCTOPHONIC launcher's) saw three SIDs of eight.
sid_rd <= unsigned(octo_do) when cs_octo = '1' else
          sid4_do when (sid4_sel_l or sid4_sel_r) = '1' else
          sid3_do when (sid3_sel_l or sid3_sel_r) = '1' else
          sid2_do when (sid2_sel_l or sid2_sel_r) = '1' else
          sid_do;

-- THE SOUND. Off: the first pair as it was. Octophonic: SIDs in left/right pairs, odd SIDs
-- (1, 3, 5, 7) left and even right - but a SID whose partner has not played since the reset
-- is in the middle, on both sides, so a one-SID game in 8 SIDs mode sounds as it does on the
-- stock core, a 2SID tune at $D420 is in stereo, and a 4- or 8-SID demo is spread out.
-- "Played" is a gate opened (a control register written with bit 0 set) or a volume set -
-- a game clearing the whole SID area with zeros does not count; SID 1 always counts. Each side is divided by how many SIDs
-- play into it (1, 2, up to 4, up to 8), so nothing overflows and one SID is never quiet.
process(clk32)
begin
	if rising_edge(clk32) then
		if reset = '1' then
			sid_played <= (others => '0');
		elsif pulseWr_io = '1'
		      and ((cpuDo(0) = '1' and (cpuAddr(4 downto 0) = "00100" or cpuAddr(4 downto 0) = "01011" or cpuAddr(4 downto 0) = "10010"))
		           or (cpuAddr(4 downto 0) = "11000" and cpuDo(3 downto 0) /= "0000")) then
			if sid_sel_l  = '1' then sid_played(0) <= '1'; end if;
			if sid_sel_r  = '1' then sid_played(1) <= '1'; end if;
			if sid2_sel_l = '1' then sid_played(2) <= '1'; end if;
			if sid2_sel_r = '1' then sid_played(3) <= '1'; end if;
			if sid3_sel_l = '1' then sid_played(4) <= '1'; end if;
			if sid3_sel_r = '1' then sid_played(5) <= '1'; end if;
			if sid4_sel_l = '1' then sid_played(6) <= '1'; end if;
			if sid4_sel_r = '1' then sid_played(7) <= '1'; end if;
		end if;
	end if;
end process;

process(clk32)
	type chip_out is array (0 to 7) of signed(17 downto 0);
	variable o         : chip_out;
	variable sl, sr    : signed(20 downto 0);
	variable nl, nr    : integer range 0 to 8;
	variable onl, onr  : boolean;
	variable pl        : std_logic_vector(7 downto 0);
begin
	if rising_edge(clk32) then
		o := (signed(sid1_aud_l), signed(sid1_aud_r), signed(sid2_aud_l), signed(sid2_aud_r),
		      signed(sid3_aud_l), signed(sid3_aud_r), signed(sid4_aud_l), signed(sid4_aud_r));
		sl := (others => '0'); sr := (others => '0'); nl := 0; nr := 0;
		pl := sid_played; pl(0) := '1';         -- SID 1 always: a digi with no gate is still sound
		if sidfx_mode(0) = '1' then pl(1) := '1'; end if;                  -- OctoSID FX: its SIDs play
		if sidfx_mode(1) = '1' then pl(2) := '1'; pl(3) := '1'; end if;
		for c in 0 to 7 loop
			-- which side(s): its own, or both when its partner (c xor 1) has not played
			if c mod 2 = 0 then
				onl := true;  onr := pl(c + 1) = '0';
			else
				onr := true;  onl := pl(c - 1) = '0';
			end if;
			-- a pair past the mode, and a SID that has never played, add nothing
			if (c >= 2 and sid_quad = '0') or (c >= 4 and sid_oct = '0') or pl(c) = '0' then
				onl := false; onr := false;
			end if;
			if onl then sl := sl + resize(o(c), 21); nl := nl + 1; end if;
			if onr then sr := sr + resize(o(c), 21); nr := nr + 1; end if;
		end loop;
		if    nl <= 1 then mix_l <= sl(17 downto 0);
		elsif nl = 2  then mix_l <= sl(18 downto 1);
		elsif nl <= 4 then mix_l <= sl(19 downto 2);
		else               mix_l <= sl(20 downto 3);
		end if;
		if    nr <= 1 then mix_r <= sr(17 downto 0);
		elsif nr = 2  then mix_r <= sr(18 downto 1);
		elsif nr <= 4 then mix_r <= sr(19 downto 2);
		else               mix_r <= sr(20 downto 3);
		end if;
	end if;
end process;

audio_l <= sid1_aud_l when sid_quad = '0' else std_logic_vector(mix_l);
audio_r <= sid1_aud_r when sid_quad = '0' else std_logic_vector(mix_r);

pot_x1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot1;
pot_y1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot2;
pot_x2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot3;
pot_y2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot4;

sid : sid_top
port map (
	reset => reset,
	clk => clk32,
	ce_1m => enableSid,
	we => pulseWr_io or fx1,
	cs => (sid_sel_r or fx1) & sid_sel_l,
	addr => p1_addr,
	data_in => p1_data,
	data_out => sid_do,
	pot_x_l => pot_x1 and pot_x2,
	pot_y_l => pot_y1 and pot_y2,

	audio_l => sid1_aud_l,
	audio_r => sid1_aud_r,

	ext_in_l(17) => sid_ver(0) and sid_digifix,
	ext_in_l(16 downto 0) => (others => '0'),

	ext_in_r(17) => sid_ver(1) and sid_digifix,
	ext_in_r(16 downto 0) => (others => '0'),

	filter_en => sid_filter,
	mode    => sid_ver,
	cfg     => sid_cfg,
	
	fc_offset_l => sid_fc_off_l,
	fc_offset_r => sid_fc_off_r,

	ld_clk  => sid_ld_clk,
	ld_addr => sid_ld_addr,
	ld_data => sid_ld_data,
	ld_wr   => sid_ld_wr
);

-- OCTOPHONIC: SIDs 3 and 4 - a second pair, the same as the first (its own
-- waveform tables and filter), the same types and filters as SIDs 1 and 2
sid2 : sid_top
port map (
	reset => reset or not sid_quad,
	clk => clk32,
	ce_1m => enableSid,
	we => pulseWr_io or fx2 or fx3,
	cs => (sid2_sel_r or fx3) & (sid2_sel_l or fx2),
	addr => p2_addr,
	data_in => p2_data,
	data_out => sid2_do,
	pot_x_l => pot_x1 and pot_x2,
	pot_y_l => pot_y1 and pot_y2,

	audio_l => sid2_aud_l,
	audio_r => sid2_aud_r,

	ext_in_l(17) => sid_ver(0) and sid_digifix,
	ext_in_l(16 downto 0) => (others => '0'),

	ext_in_r(17) => sid_ver(1) and sid_digifix,
	ext_in_r(16 downto 0) => (others => '0'),

	filter_en => sid_filter,
	mode    => sid_ver,
	cfg     => sid_cfg,
	
	fc_offset_l => sid_fc_off_l,
	fc_offset_r => sid_fc_off_r,

	ld_clk  => sid_ld_clk,
	ld_addr => sid_ld_addr,
	ld_data => sid_ld_data,
	ld_wr   => sid_ld_wr
);

-- OCTOPHONIC: SIDs 5 and 6 ($D480, $D4A0)
sid3 : sid_top
port map (
	reset => reset or not sid_oct,
	clk => clk32,
	ce_1m => enableSid,
	we => pulseWr_io,
	cs => sid3_sel_r & sid3_sel_l,
	addr => cpuAddr(4 downto 0),
	data_in => cpuDo,
	data_out => sid3_do,
	pot_x_l => pot_x1 and pot_x2,
	pot_y_l => pot_y1 and pot_y2,

	audio_l => sid3_aud_l,
	audio_r => sid3_aud_r,

	ext_in_l(17) => sid_ver(0) and sid_digifix,
	ext_in_l(16 downto 0) => (others => '0'),

	ext_in_r(17) => sid_ver(1) and sid_digifix,
	ext_in_r(16 downto 0) => (others => '0'),

	filter_en => sid_filter,
	mode    => sid_ver,
	cfg     => sid_cfg,
	
	fc_offset_l => sid_fc_off_l,
	fc_offset_r => sid_fc_off_r,

	ld_clk  => sid_ld_clk,
	ld_addr => sid_ld_addr,
	ld_data => sid_ld_data,
	ld_wr   => sid_ld_wr
);

-- OCTOPHONIC: SIDs 7 and 8 ($D580, $D5A0)
sid4 : sid_top
port map (
	reset => reset or not sid_oct,
	clk => clk32,
	ce_1m => enableSid,
	we => pulseWr_io,
	cs => sid4_sel_r & sid4_sel_l,
	addr => cpuAddr(4 downto 0),
	data_in => cpuDo,
	data_out => sid4_do,
	pot_x_l => pot_x1 and pot_x2,
	pot_y_l => pot_y1 and pot_y2,

	audio_l => sid4_aud_l,
	audio_r => sid4_aud_r,

	ext_in_l(17) => sid_ver(0) and sid_digifix,
	ext_in_l(16 downto 0) => (others => '0'),

	ext_in_r(17) => sid_ver(1) and sid_digifix,
	ext_in_r(16 downto 0) => (others => '0'),

	filter_en => sid_filter,
	mode    => sid_ver,
	cfg     => sid_cfg,
	
	fc_offset_l => sid_fc_off_l,
	fc_offset_r => sid_fc_off_r,

	ld_clk  => sid_ld_clk,
	ld_addr => sid_ld_addr,
	ld_data => sid_ld_data,
	ld_wr   => sid_ld_wr
);

-- -----------------------------------------------------------------------
-- CIAs
-- -----------------------------------------------------------------------
cia1: mos6526
port map (
	clk => clk32,
	mode => cia_mode,
	phi2_p => enableCia_p,
	phi2_n => enableCia_n,
	res_n => not reset,
	cs_n => not cs_cia1,
	rw => not cpuWe,

	rs => cpuAddr(3 downto 0),
	db_in => cpuDo,
	db_out => cia1Do,

	pa_in => cia1_pai,
	pa_out => cia1_pao,
	pb_in => cia1_pbi,
	pb_out => cia1_pbo,

	flag_n => cass_read,
	sp_in => sp1_i,
	sp_out => sp1_o,
	cnt_in => cnt1_i,
	cnt_out => cnt1_o,

	tod => todclk,

	irq_n => irq_cia1
);

cia2: mos6526
port map (
	clk => clk32,
	mode => cia_mode,
	phi2_p => enableCia_p,
	phi2_n => enableCia_n,
	res_n => not reset,
	cs_n => not cs_cia2,
	rw => not cpuWe,

	rs => cpuAddr(3 downto 0),
	db_in => cpuDo,
	db_out => cia2Do,

	pa_in => cia2_pai and cia2_pao,
	pa_out => cia2_pao,
	pb_in => (pb_i and not cia2_pbe) or (cia2_pbo and cia2_pbe),
	pb_out => cia2_pbo,
	pb_oe => cia2_pbe,

	flag_n => flag2_n_i,
	pc_n => pc2_n_o,

	sp_in => sp2_i,
	sp_out => sp2_o,
	cnt_in => cnt2_i,
	cnt_out => cnt2_o,

	tod => todclk,

	irq_n => irq_cia2
);

serialBus: process(clk32)
begin
	if rising_edge(clk32) then
		if sysCycle = CYCLE_EXT5 then
			cia2_pai(7) <= iec_data_i and not cia2_pao(5);
			cia2_pai(6) <= iec_clk_i and not cia2_pao(4);
		end if;
	end if;
end process;

cia2_pai(5 downto 0) <= "111" & pa2_i & "11";

iec_data_o <= not cia2_pao(5);
iec_clk_o  <= not cia2_pao(4);
iec_atn_o  <= not cia2_pao(3);

pb_o  <= cia2_pbo;
pa2_o <= cia2_pao(2);

process(clk32)
variable sum: integer range 0 to 33000000;
begin
	if rising_edge(clk32) then
		if reset = '1' then
			todclk <= '0';
			sum := 0;
		elsif ntscMode = '1' then
			sum := sum + 120;
			if sum >= 32727266 then
				sum := sum - 32727266;
				todclk <= not todclk;
			end if;
		else
			sum := sum + 100;
			if sum >= 31527954 then
				sum := sum - 31527954;
				todclk <= not todclk;
			end if;
		end if;
	end if;
end process;

-- -----------------------------------------------------------------------
-- 6510 CPU / DMA
-- -----------------------------------------------------------------------
cpu: entity work.cpu_6510
port map (
	clk => clk32,
	reset => reset,
	enable => enableCpu and not dma_active,
	nmi_n => irq_cia2 and nmi_n,
	nmi_ack => nmi_ack,
	irq_n => irq_cia1 and irq_vic and irq_n and irq_ext_n and not octo_irq,   -- OCTOPHONIC: OctoVIC 2's interrupt too
	rdy => baLoc,

	di => cpuDi,
	addr => cpuAddr_pre,
	do => cpuDo_pre,
	we => cpuWe_pre,

	diIO => cpuIO(7) & cpuIO(6) & cpuIO(5) & cass_sense & cpuIO(3) & "111",
	doIO => cpuIO
);

cass_motor <= cpuIO(5);
cass_write <= cpuIO(3);

ramDout <= cpuDo;
ramAddr <= systemAddr;
ramWE   <= systemWe when sysCycle >= CYCLE_CPU0 else '0';
ramCE   <= cs_ram when sysCycle = CYCLE_VIC0 or cpu_cyc = '1' else '0';
cpu_cyc <= '1' when 
				(sysCycle = CYCLE_CPU0 and turbo_m(0) = '1' and cs_ram = '1' ) or
				(sysCycle = CYCLE_CPU4 and turbo_m(1) = '1' and cs_ram = '1' ) or
				(sysCycle = CYCLE_CPU8 and turbo_m(2) = '1' and cs_ram = '1' ) or
				(sysCycle = CYCLE_CPUC and (io_enable = '1'  or cs_ram = '1')) else '0';
				
process(clk32)
begin
	if rising_edge(clk32) then
		cpu_cyc_s <= cpu_cyc_s(0) & cpu_cyc;
		enableCpu <= cpu_cyc_s(1);
		io_enable <= io_enable and not enableCpu;

		if sysCycle = CYCLE_EXT0 then
			io_enable <= '1';
		end if;

		-- 2 points to register DMA request before CPU cycles.
		if sysCycle = CYCLE_EXT1 or sysCycle = CYCLE_EXT5 then
			dma_active <= dma_req;
			turbo_en <= turbo_mode(0);
			turbo_m <= "000";
			if cs_io = '0' and dma_req = '0' and ((turbo_mode(0) and turbo_state) = '1' or turbo_mode(1) = '1') then
				case turbo_speed is
					when "00" => turbo_m <= "010";
					when "01" => turbo_m <= "110";
					when "10" => turbo_m <= "111";
					when "11" => turbo_m <= "111"; -- unused
				end case;
			end if;
		end if;
	end if;
end process;

cpuAddr <= cpuAddr_pre when dma_active = '0' else dma_addr;
cpuDo   <= cpuDo_pre   when dma_active = '0' else dma_dout;
cpuWe   <= cpuWe_pre   when dma_active = '0' else dma_we;

ext_cycle <= '1' when (sysCycle >= CYCLE_DMA0 and sysCycle <= CYCLE_DMA3) else '0';
dma_cycle <= '1' when (sysCycle >= CYCLE_CPU0 and sysCycle <= CYCLE_CPUF) and cpuHasBus = '1' and dma_active = '1' else '0';
dma_din   <= cpuDi;

-- -----------------------------------------------------------------------
-- Keyboard
-- -----------------------------------------------------------------------
Keyboard: entity work.fpga64_keyboard
port map (
	clk => clk32,
	
	reset => kbd_reset,
	ps2_key => ps2_key,

	joyA => not unsigned(joyA(6 downto 0)),
	joyB => not unsigned(joyB(6 downto 0)),
	pai => cia1_pao,
	pbi => cia1_pbo,
	pao => cia1_pai,
	pbo => cia1_pbi,
	
	shift_mod => shift_mod,

	restore_key => freeze_key,
	tape_play => tape_play,
	tape_rew => tape_rew,
	tape_stop => tape_stop,
	tape_ff => tape_ff,
	tape_reset_counter => tape_reset_counter,
	mod_key => mod_key,
	backwardsReadingEnabled => '1'
);

end architecture;
