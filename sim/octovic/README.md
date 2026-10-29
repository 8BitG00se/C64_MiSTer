# OctoVIC's check

OctoVIC (rtl/octovic/octovic.sv) on its own in Verilator, cycle by cycle, against ref.py (the
spec, docs/OCTOVIC.md, in Python): every pixel of every frame compared.

    verilator --cc --exe -O3 -Wno-WIDTH -Wno-fatal --top-module octovic ../../rtl/octovic/octovic.sv tb.cpp -o tb --Mdir obj
    make -C obj -f Voctovic.mk
    python3 run.py [seed] [DDR3 busy %] [latency min] [latency max]     # PASS / FAIL
    STRESS=48 python3 run.py 7 30 4 60                                  # 48 sprites 64x64 on the same lines

tb.cpp gives OctoVIC the VIC's timing, a pattern for the VIC's picture, the register writes of
the scene (one a microsecond, as the 6510 would) and a DDR3 that is busy and answers late at
random. run.py builds a scene from the seed (tiles, maps, line scroll, 48 sprites of every size,
the copper, the data port), runs both, and saves frame.png (and wrong.png if anything differs).
