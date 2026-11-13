#!/bin/sh
# Fix 74: the hot-key gate in Verilator (c) 2026 Mong00se
set -e
cd "$(dirname "$0")"
OUT=${1:-/tmp/hotkeys-sim}
mkdir -p "$OUT"
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Mdir "$OUT/obj" --top-module tb -o tb tb.sv ../../rtl/hotkeys.sv
"$OUT/obj/tb" | tee "$OUT/result.txt"
grep -q HOTKEYS_SIM_OK "$OUT/result.txt"
