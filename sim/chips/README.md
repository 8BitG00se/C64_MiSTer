# MY CHIPS test

Plays each combined waveform on voice 3 of all 8 SIDs (4 sid_tops, pairs 3-4 one clock behind,
one shared chip_bank) with a chip loaded per side, reads OSC3 back every microsecond and compares
it with the chip's measurement at the oscillator's position, at pulse widths $400, $800 and $C00.

    python3 exp.py <ChipClones.h> cmos65815084 e5084.bin       (one per chip)
    verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-PINCONNECTEMPTY \
      -Wno-DECLFILENAME -Wno-GENUNNAMED -Wno-MULTIDRIVEN --top-module tb tb.sv \
      ../../rtl/sid/chip_bank.sv sid_top_sim.sv ../../rtl/sid/sid_voice.sv sid_tables_stub.sv \
      sid_filter_stub.sv sid_envelope_sim.sv ../../rtl/sid/sid_dac.sv tb.cpp -o tbx
    ./obj_dir/tbx ../../chips/MOS_6581_5084.CHP ../../chips/CSG_8580R5_3591.CHP e5084.bin e3591.bin

sid_top_sim.sv / sid_envelope_sim.sv are the RTL with Quartus-only declarations made Verilator
friendly (wire arrays assigned procedurally / initialised), regenerated with sed (see the commit).
sid_tables and sid_filter are stubbed: the core's own tables answer 0, so every value read is the
chip's. results.txt holds the run's output.
