#!/bin/sh
# OctoVIC register map test (see regmap.cpp). Needs Verilator 5.
cd "$(dirname "$0")/../.." && R=$PWD && mkdir -p /tmp/regmap && cd /tmp/regmap &&
verilator -Wno-fatal --cc --exe --build -O1 -j 4 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY \
  --top-module octovic $R/rtl/octovic/octovic.sv $R/rtl/octovic/ovram.sv $R/sim/regmap/regmap.cpp -o regmap >/tmp/regmap/build.txt 2>&1 \
  || { tail -20 /tmp/regmap/build.txt; exit 1; }
./obj_dir/regmap
