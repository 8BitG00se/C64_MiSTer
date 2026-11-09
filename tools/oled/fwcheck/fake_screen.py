#!/usr/bin/env python3
# A pretend front screen on a pseudo-terminal, to test oled.sh with no MiSTer: it answers CMDHWINF like the
# Octophonic firmware (or an older one), takes CMDOANI's frames and decodes them as the firmware would, and logs
# every command it got. Then it runs oled.sh through the jobs Octophonic Main gives it and checks what arrived.
#   fake_screen.py OLED_SH FILE1.oled FILE2.oled
import os, sys, pty, time, threading, subprocess, struct, tempfile, tty
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import make_anim as m

sh, f1, f2 = sys.argv[1:4]
master, slave = pty.openpty()
tty.setraw(slave)
dev = os.ttyname(slave)
fw = ['230702-OCTO4']
got = []
buf = bytearray()
lock = threading.Lock()


def reader():
    while True:
        try: d = os.read(master, 65536)
        except OSError: return
        with lock: buf.extend(d)


def take(n, timeout=20):
    t = time.time()
    while time.time() - t < timeout:
        with lock:
            if len(buf) >= n:
                b = bytes(buf[:n]); del buf[:n]; return b
        time.sleep(0.005)
    raise TimeoutError('only %d of %d bytes came' % (len(buf), n))


def line(timeout=20):
    t = time.time()
    while time.time() - t < timeout:
        with lock:
            i = buf.find(b'\n')
            if i >= 0:
                l = bytes(buf[:i]); del buf[:i + 1]; return l.decode('latin1')
        time.sleep(0.005)
    return None


def screen():
    while True:
        l = line(3600)
        if l is None: return
        if l == 'CMDHWINF':
            os.write(master, ('HWESP32DE;%s;\r\n' % fw[0]).encode())
            got.append('HWINF'); continue
        if l.startswith('CMDOANI,'):
            ln, fr, ms, mode = (int(x) for x in l[8:].split(','))
            data = take(ln)
            shown = m.decode(data, fr, mode)                 # raises if the frames don't add up
            got.append('OANI %d frames %d bytes ok' % (fr, ln))
        elif l.startswith('CMDCOR,'):
            take(8192); got.append(l + ' +8192')
        else:
            got.append(l)
        os.write(master, b'ttyack;')


threading.Thread(target=reader, daemon=True).start()
threading.Thread(target=screen, daemon=True).start()

st = tempfile.mkdtemp()
env = dict(os.environ, OCTO_OLED_TTY=dev, OCTO_OLED_STATE=st + '/s', OCTO_OLED_LOG=st + '/oled.log')


def run(*a, wait=True):
    p = subprocess.Popen(['dash', sh] + list(a), env=env)
    if wait: p.wait()
    return p


def settle(n, t=30):
    t0 = time.time()
    while len(got) < n and time.time() - t0 < t: time.sleep(0.05)
    time.sleep(0.3)


ok = True
def check(name, want):
    global ok
    have = list(got); got.clear()
    good = have == want
    ok &= good
    print(('ok    ' if good else 'WRONG ') + name + ': ' + ' | '.join(have) + ('' if good else '   (wanted: ' + ' | '.join(want) + ')'))


h1 = struct.unpack_from('<BBHI', open(f1, 'rb').read(), 8); h2 = struct.unpack_from('<BBHI', open(f2, 'rb').read(), 8)
o1 = 'OANI %d frames %d bytes ok' % (h1[2], h1[3]); o2 = 'OANI %d frames %d bytes ok' % (h2[2], h2[3])
run('boot'); settle(2); check('boot: the logo', ['HWINF', 'CMDOCTO,0'])
run('play', f1); settle(1); check('a program with an animation', [o1])
run('logo'); settle(1); check('CTRL+F12: the logo', ['CMDOCTO,0'])
run('logo'); settle(1, 2); check('the logo again: nothing sent', [])
run('play', f1); settle(1); check('the same program again: held in the screen', ['CMDOANP'])
a = run('play', f2, wait=False); time.sleep(0.2); b = run('logo', wait=False); a.wait(); b.wait(); settle(2)
check('another program, then out at once: the transfer finishes, then the logo', [o2, 'CMDOCTO,0'])
fw[0] = '230702-OCTO3'; os.remove(st + '/s.fw'); os.remove(st + '/s.now')
run('play', f1); settle(2); check('an older screen firmware: the still picture', ['HWINF', 'CMDCOR,PRGSTILL,0 +8192'])
print(open(st + '/oled.log').read())
print('ALL GOOD' if ok else 'SOMETHING WRONG')
sys.exit(0 if ok else 1)
