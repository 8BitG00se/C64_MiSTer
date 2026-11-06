#!/usr/bin/env python3
"""build.py - Octo Weaver Lite: assemble, make the PLAY players of the demo songs, the .d64, the zip.   By Mong00se (Octophonic 64).
   python3 build.py OUTDIR [N]       N = the build number (default 1)
Makes in OUTDIR:  OCTO WEAVER LITE.PRG   Octo Weaver Disk build N.d64   OCTO WEAVER LITE build N.zip   How to use.txt
Needs acme, c1541 (VICE), python3.  The PLAY file of a song is built here the same way the editor's X key writes it (the program's
memory image from $0801 with the live variables and the gaps zero, the entry word pointing at the PLAY program, the song inside)."""
import os, re, subprocess, sys, tempfile, zipfile
HERE = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, HERE)
import owsong, demos

def run(*a, **k): subprocess.run(a, check=True, **k)

def labels(path):
    L = {}
    for l in open(path):
        m = re.match(r'\s*(\S+)\s*=\s*\$([0-9a-fA-F]+)', l)
        if m: L[m.group(1)] = int(m.group(2), 16)
    return L

def check_tables():
    """ftab.inc / eqtab.inc / sounds.inc / out/default.song must be the ones mktab.py and owsong.py make"""
    with tempfile.TemporaryDirectory() as w:
        import mktab
        mktab.make(os.path.join(w, 'ftab.inc')); mktab.eqtab(os.path.join(w, 'eqtab.inc')); owsong.sounds_inc(os.path.join(w, 'sounds.inc'))
        for n in ('ftab.inc', 'eqtab.inc', 'sounds.inc'):
            if open(os.path.join(w, n)).read() != open(os.path.join(HERE, n)).read(): sys.exit(n + ' is out of date: run mktab.py / owsong.py')
    os.makedirs(os.path.join(HERE, 'out'), exist_ok=True)
    d = owsong.Song('NEW SONG'); owsong.default_sounds(d); open(os.path.join(HERE, 'out', 'default.song'), 'wb').write(d.to_bytes())

def play_image(prg, L, song):
    """NAME PLAY: the editor's memory image $0801 .. front_end, the zero ranges, the entry word = play_start, the song in place"""
    load = prg[0] | prg[1] << 8; mem = bytearray(65536); mem[load:load + len(prg) - 2] = prg[2:]
    SONG = L['SONG']; mem[SONG:SONG + owsong.SONGSIZE] = song
    for a, b in ((0x0812, L['PLAYER']), (L['VARS'], L['VARS_END']), (L['tmute'], L['tmute'] + 8), (L['frame'], L['play_start']), (L['PLAYER_END'], SONG)):
        mem[a:b] = bytes(b - a)
    mem[L['entry']] = L['play_start'] & 255; mem[L['entry'] + 1] = L['play_start'] >> 8
    return bytes([0x01, 0x08]) + bytes(mem[0x0801:L['front_end']])

def owp_image(prg, L, song):
    """NAME.OWP: the player and the song, $1000 .. SONGEND, as a PRG"""
    P = L['PLAYER']; S = L['SONG']; mem = bytearray(65536); load = prg[0] | prg[1] << 8; mem[load:load + len(prg) - 2] = prg[2:]
    mem[S:S + owsong.SONGSIZE] = song
    for a, b in ((L['VARS'], L['VARS_END']), (L['PLAYER_END'], S)): mem[a:b] = bytes(b - a)
    return bytes([P & 255, P >> 8]) + bytes(mem[P:S + owsong.SONGSIZE])

def main():
    out = os.path.abspath(sys.argv[1]); n = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    os.makedirs(out, exist_ok=True); check_tables()
    with tempfile.TemporaryDirectory() as w:
        prg = os.path.join(out, 'OCTO WEAVER LITE.PRG'); lbl = os.path.join(w, 'weaver.lbl')
        run('acme', '-I', HERE, '-f', 'cbm', '-l', lbl, '-o', prg, os.path.join(HERE, 'weaver.asm'), cwd=HERE)
        P = open(prg, 'rb').read(); L = labels(lbl)
        files = []
        for name, fn in demos.SONGS:
            s = fn(); ows = os.path.join(w, name + '.ows'); s.save(ows)
            pl = os.path.join(w, name + ' PLAY'); open(pl, 'wb').write(play_image(P, L, s.to_bytes()))
            fn11 = name.lower()[:11].rstrip()        # the editor's file names: the song name, 11 letters at most
            files.append((ows, fn11 + '.ows,s')); files.append((pl, fn11 + ' play,p'))
        d64 = os.path.join(out, 'Octo Weaver Disk build %d.d64' % n)
        if os.path.exists(d64): os.remove(d64)
        cmd = ['c1541', '-format', 'octo weaver,ow', 'd64', d64, '-write', prg, 'octo weaver lite']
        for src, dst in files: cmd += ['-write', src, dst]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        txt = os.path.join(out, 'How to use.txt')
        run(sys.executable, os.path.join(HERE, 'md2txt.py'), os.path.join(REPO, 'docs', 'OCTOWEAVER.md'), txt)
        z = os.path.join(out, 'OCTO WEAVER LITE build %d.zip' % n)
        if os.path.exists(z): os.remove(z)
        with zipfile.ZipFile(z, 'w', zipfile.ZIP_DEFLATED) as zf:
            for f in (prg, d64, txt): zf.write(f, os.path.basename(f))
    for f in sorted(os.listdir(out)): print('%9d  %s' % (os.path.getsize(os.path.join(out, f)), f))

if __name__ == '__main__':
    main()
