# Sound level loop (Fix 28)

Measures the Octophonic 64's sound level against stock VICE x64sc, so the core's mix and the emulator's
can be checked whenever they change.

    sim/level/run.sh OUT

- `gen.py` - the test programs (6502, ACME): `chord1` a full-volume sawtooth chord on SID 1, `tune1` a loud
  one-SID tune pattern, `chord2`/`tune2`/`tune4`/`chord8`/`tune8` the same on 2, 4 and 8 SIDs, `uneven8`
  8 SIDs at volumes 15 15 6 5 6 5 5 6 (like the forum's SWINTH test), `uneven8b` at 12 10 8 6 6 5 4 3.
- `vref.cc` - "stock VICE": VICE's own reSID and reSID-fp libraries with VICE 3.10's default settings
  (6581, PAL, 48 kHz), fed the SID writes the emulator logged (`.sidw`), N SIDs mixed as VICE does
  (odd SIDs left, even right, `sound_audio_mix`).
- `table.py` / `meas.py` - peak and RMS dBFS (DC removed) from half a second after the sound starts.
- `rtlmodel.py` - the new mixer of `rtl/sid_mix.vhd` in Python, integer for integer; with the
  emulator's `OCTO_SIDRAW8=file` dump it checks the emulator's mix bit for bit and prints the automatic
  gain's lowest per half second (the pumping check).
- `corecol.py` - the core's HDMI level from the RTL arithmetic (old mixer and new), from the same dump.
- `mixtest.sh` (run by the GitHub build, before Quartus) - `rtl/sid_mix.vhd` itself in GHDL
  (`tb_sid_mix.vhd`) on 200,000 microseconds of vectors from `mixvec.py` (one SID, eight loud then
  quiet, a reset, OctoSID FX, four-SID mode, OCTOPHONIC off, unpaired SIDs), compared with the same
  integer model, which matches the emulator's mix bit for bit on real dumps.

Results when the fix went in (9 Nov 2026, peak / RMS dBFS):

| test | core before | core after | VICE reSID | VICE reSID-fp |
|---|---|---|---|---|
| chord1 | -9.0 / -18.9 | -6.8 / -17.0 | -7.3 / -16.8 | -7.2 / -17.3 |
| tune1 | -6.2 / -15.4 | -3.8 / -13.6 | -4.7 / -13.6 | -7.4 / -13.2 |
| tune2 | -6.2 / -15.4 | -3.8 / -13.6 | -4.6 / -13.6 | -7.6 / -13.2 |
| tune4 | -6.4 / -15.8 | -1.5 / -11.3 | -1.8 / -9.3 | -3.6 / -8.7 |
| tune8 | -6.6 / -16.5 | -1.1 / -11.1 | -0.3 / -6.0 (saturating) | -1.3 / -5.2 |
| uneven8 | -12.0 / -22.1 | -1.4 / -11.8 | -2.0 / -9.6 | -3.8 / -8.9 |
| DNA Wave (8 SIDs) | -15.2 / -30.8 | -3.2 / -17.1 | -5.0 / -17.4 | -2.9 / -16.2 |
| Night City build 3 | -18.5 / -34.4 | -4.7 / -20.6 | -5.6 / -20.6 | -5.5 / -20.3 |
| SWINTH 8-SID test | -15.5 / -33.8 | -4.9 / -21.5 | -6.1 / -21.0 | -6.1 / -19.9 |
