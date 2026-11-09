#!/usr/bin/env python3
# The example front-screen animations, made from the demos' own frames in the Octophonic 64 emulator.
#   examples.py FRAMES OUT
# FRAMES holds one folder of emulator frames per demo (emusnd.sh with OCTO_DUMP_FROM/STEP/TO, the *_hdmi_*.png ones):
#   nightcity/  frames 200.. every 2nd      dna/  100.. every 2nd      pend/  100.. every 2nd      mona/  100.. every 2nd
# OUT gets "<Demo>.oled" and "<Demo>_preview.gif" for each.
import sys, os, glob, subprocess, tempfile
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
MAKE = os.path.join(HERE, 'make_anim.py')


def frames(d):
    return sorted(glob.glob(os.path.join(d, '*_hdmi_*.png')))


def run(src, out, *opt):
    subprocess.run([sys.executable, MAKE, src, '-o', out] + [str(o) for o in opt], check=True)


def mona(src, out):
    # Mona Lisa: the demo's held views - the title over her hands, her face, her eyes, her smile - one after the
    # other, each brought in by a raster wipe like the demo's own opening (only the rows being wiped change, and a
    # held view costs nothing, so four detailed pictures fit).
    f = frames(src)
    pick = lambda n: Image.open(f[(n - 100) // 2]).convert('RGB')       # emulator frame n (dumped from 100, every 2nd)
    views = [pick(650).crop((70, 196, 326, 260)),                         # MONA LISA / LEONARDO DA VINCI, the hands
             pick(1144).crop((0, 72, 396, 171)),                          # her face
             pick(1480).crop((0, 112, 396, 211)),                         # her eyes
             pick(1820).crop((0, 108, 396, 207))]                         # her smile
    views = [v.resize((256, 64), Image.LANCZOS) for v in views]
    seq = []
    hold, rows = 60, 4                                                    # 2.4 s on each, 16 frames of wipe
    cur = Image.new('RGB', (256, 64))
    for v in views + [views[0]]:
        for r in range(0, 64 + rows, rows):                               # the wipe: new rows above, a bright bar at the edge
            im = cur.copy(); im.paste(v.crop((0, 0, 256, min(r, 64))), (0, 0))
            if r < 64: ImageDraw.Draw(im).rectangle((0, r, 255, min(63, r + 1)), fill=(255, 240, 200))
            seq.append(im)
        cur = v
        seq += [v] * hold
    # the loop: it ends with the first view wiped in again, so start the loop after that first wipe
    first = 64 // rows + 1
    seq = seq[first:]
    with tempfile.TemporaryDirectory() as t:
        for i, im in enumerate(seq): im.save(os.path.join(t, 'm_hdmi_%05d.png' % i))
        run(t, out, '--crop', '0,0,256,64', '--fps', 25, '--steady', 0, '--gamma', 0.85, '--max-kb', 64)


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    o = lambda n: os.path.join(out, n + '.oled')
    # Night City: the city at its own pixel size (1:1), mountains and moon above it, the UFOs flying through;
    # the city scrolls 2 pixels a frame, which the screen does itself (parallax bands), 12.5 frames a second.
    run(os.path.join(src, 'nightcity', '*_hdmi_*.png'), o('Night City'), '--crop', '70,104,256,64', '--from', 300, '--every', 2,
        '--fps', 12.5, '--gamma', 0.75, '--levels', 8, '--steady', 0, '--max-kb', 90)
    # DNA Wave: the helix turning, played forwards then backwards (bounce) so it loops without a jump. On the TV it runs
    # corner to corner; tilted level (shear) the whole helix fits the strip. Its soft glows are left dark (--black).
    run(os.path.join(src, 'dna', '*_hdmi_*.png'), o('DNA Wave'), '--shear', 0.35, '--crop', '0,148,396,128', '--from', 300,
        '--every', 2, '--fps', 12.5, '--bounce', '--gamma', 0.8, '--black', 55, '--levels', 8, '--steady', 0.6, '--max-kb', 64)
    # Pendulum Wave: the row of balls swinging, bounce (a swing backwards is still a swing).
    run(os.path.join(src, 'pend', '*_hdmi_*.png'), o('Pendulum Wave'), '--crop', '0,150,396,99', '--from', 300, '--every', 2,
        '--fps', 12.5, '--bounce', '--gamma', 0.8, '--black', 62, '--levels', 8, '--steady', 0, '--max-kb', 64)
    mona(os.path.join(src, 'mona'), o('Mona Lisa'))


if __name__ == '__main__':
    main()
