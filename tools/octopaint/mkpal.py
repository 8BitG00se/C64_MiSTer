#!/usr/bin/env python3
# mkpal.py - makes palette.inc, OctoPaint's default 256-colour palette. Original work by Mong00se.
#   0        black (see-through on the canvas, shown black)
#   1-15     a C64-like set (RGB values written out below - chosen here, not copied from anywhere)
#   16-239   14 hue ramps of 16 steps, dark to light (HSV, made below)
#   240-255  a 16-step grey ramp, black to white
# (The spec says "15 hue ramps then a grey ramp": that is 256 entries from entry 16 - 15 ramps and the grey
#  ramp do not fit in 240 places, so it is 14 hue ramps.)
import colorsys, sys

C64 = [  # entry, name, r, g, b
    (1, 'white',       255, 255, 255),
    (2, 'red',         152,  52,  46),
    (3, 'cyan',        118, 206, 200),
    (4, 'purple',      142,  62, 164),
    (5, 'green',        66, 158,  72),
    (6, 'blue',         52,  44, 160),
    (7, 'yellow',      222, 222, 112),
    (8, 'orange',      162, 100,  44),
    (9, 'brown',        98,  68,  16),
    (10, 'light red',  208, 122, 112),
    (11, 'dark grey',   68,  68,  68),
    (12, 'grey',       114, 114, 114),
    (13, 'light green',152, 232, 142),
    (14, 'light blue', 120, 110, 228),
    (15, 'light grey', 176, 176, 176),
]
NHUE = 14

def table():
    pal = [(0, 0, 0)] * 256
    for e, _, r, g, b in C64: pal[e] = (r, g, b)
    for h in range(NHUE):
        for s in range(16):
            if s <= 8: v, sat = 0.12 + 0.88 * s / 8, 1.0
            else:      v, sat = 1.0, 1.0 - 0.85 * (s - 8) / 7
            r, g, b = colorsys.hsv_to_rgb(h / NHUE, sat, v)
            pal[16 + 16 * h + s] = (round(r * 255), round(g * 255), round(b * 255))
    for i in range(16): pal[240 + i] = (i * 17, i * 17, i * 17)
    return pal

if __name__ == '__main__':
    pal = table()
    out = ['; OctoPaint default palette: 256 x (r, g, b). Made by mkpal.py - do not edit by hand.']
    out.append('; UI colours used by the toolbar:')
    out.append('C_UIBG   = %d     ; toolbar background (a dark blue)' % (16 + 16 * 9 + 2))
    out.append('C_BLACK  = 240    ; black that is not see-through (the pointer\'s edge)')
    out.append('C_WHITE  = 255')
    out.append('C_UILINE = 247    ; a mid grey')
    out.append('defpal:')
    for i, (r, g, b) in enumerate(pal):
        out.append('        !byte %3d,%3d,%3d   ; %d' % (r, g, b, i))
    open(sys.argv[1] if len(sys.argv) > 1 else 'palette.inc', 'w').write('\n'.join(out) + '\n')
