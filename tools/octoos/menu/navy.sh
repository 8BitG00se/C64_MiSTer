#!/bin/sh
# OCTOPHONIC: the navy menu core. Run in a Main_MiSTer-style checkout of Menu_MiSTer (at UPSTREAM):
# the three lines that paint the grey noise (comp_v) where Main has no picture up become the
# Octophonic start screen's navy, 28,32,92. Nothing else in the core changes. Stops if the lines
# are not there exactly once each, so a changed upstream can never give a half-patched core.
set -eu
F=menu.sv
for c in R:23:16:28 G:15:8:32 B:7:0:92; do
    ch=${c%%:*}; rest=${c#*:}; hi=${rest%%:*}; rest=${rest#*:}; lo=${rest%%:*}; v=${rest#*:}
    n=$(grep -c "^assign VGA_$ch *= fb_active ? fb_rgb\[$hi:$lo\] *: comp_v;" $F || true)
    [ "$n" = 1 ] || { echo "VGA_$ch line not found once in $F ($n)"; exit 1; }
    sed -i "s/^\(assign VGA_$ch *= fb_active ? fb_rgb\[$hi:$lo\] *: \)comp_v;/\18'd$v;   \/\/ OCTOPHONIC: navy, not the grey noise/" $F
done
grep -n "OCTOPHONIC: navy" $F
[ "$(grep -c 'OCTOPHONIC: navy' $F)" = 3 ] || exit 1
