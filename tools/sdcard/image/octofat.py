#!/usr/bin/env python3
# OCTOPHONIC FUSION - writes the card image: Mr. Fusion's own start of the card (its MBR boot code,
# the gap, and the 0xA2 bootloader partition, copied byte for byte) and then a fresh FAT16 data
# partition holding a folder tree. Python's standard library only - no mtools, no mkfs, no mount.
#
#   octofat.py BASE.img TREE OUT.img [LABEL]
#
# The layout is Mr. Fusion's (builder/scripts/entrypoint.sh): partition 1 type 0x0b from sector
# 10240 (the data, FAT16 as its mkfs.vfat makes it), partition 2 type 0xa2 at 2048, 8192 sectors (the
# bootloader the DE10-Nano's boot ROM finds by its type). Partition 1 is sized to the tree plus room
# for a wpa_supplicant.conf or samba.sh dropped on from the PC. Long file names are written (VFAT),
# so the names are exactly as in the tree.
import os, struct, sys, time

SEC = 512
P1_START = 10240
P2_START, P2_SIZE = 2048, 8192
SPARE = 24 * 1024 * 1024          # free room on the data partition after the files


def fat_time(t):
    tm = time.gmtime(t)
    d = ((tm.tm_year - 1980) << 9) | (tm.tm_mon << 5) | tm.tm_mday
    s = (tm.tm_hour << 11) | (tm.tm_min << 5) | (tm.tm_sec // 2)
    return d, s


class Node:
    def __init__(self, name, path, isdir):
        self.name, self.path, self.isdir = name, path, isdir
        self.children = []
        self.size = 0 if isdir else os.path.getsize(path)
        self.cluster = 0
        self.nclus = 0


def walk(path, name=''):
    n = Node(name, path, os.path.isdir(path))
    if n.isdir:
        for e in sorted(os.listdir(path), key=lambda s: s.lower()):
            n.children.append(walk(os.path.join(path, e), e))
    return n


BAD = set('"*+,/:;<=>?[\\]|')


def short_names(names):
    """8.3 names for one folder: (short 11 bytes, needs a long name entry) per name, no clashes."""
    used, out = set(), []
    for nm in names:
        up = nm.upper()
        base, ext = (up.rsplit('.', 1) + [''])[:2] if '.' in up[1:] else (up, '')
        ok83 = (nm == up and 1 <= len(base) <= 8 and len(ext) <= 3 and not (set(up) & BAD) and ' ' not in up
                and up.count('.') <= 1 and all(32 < ord(c) < 127 for c in up))
        if ok83:
            sn = base.ljust(8) + ext.ljust(3)
            if sn not in used:
                used.add(sn); out.append((sn.encode('ascii'), False)); continue
        clean = lambda s: ''.join(c if (c.isalnum() and ord(c) < 127) or c in '!#$%&\'()-@^_`{}~' else '_' for c in s.replace(' ', '').replace('.', ''))
        b, e = clean(base)[:8] or '_', clean(ext)[:3]
        for i in range(1, 100000):
            tail = '~%d' % i
            sn = (b[:8 - len(tail)] + tail).ljust(8) + e.ljust(3)
            if sn not in used:
                used.add(sn); out.append((sn.encode('ascii'), True)); break
    return out


def lfn_entries(name, short):
    csum = 0
    for c in short:
        csum = (((csum & 1) << 7) + (csum >> 1) + c) & 0xFF
    u = name.encode('utf-16-le')
    chars = [u[i:i + 2] for i in range(0, len(u), 2)]
    if len(chars) % 13:                    # a NUL after the name, then 0xFFFF - unless it fills them
        chars.append(b'\0\0')
        while len(chars) % 13: chars.append(b'\xff\xff')
    parts = [chars[i:i + 13] for i in range(0, len(chars), 13)]
    ents = []
    for i, p in enumerate(parts):
        seq = i + 1
        if i == len(parts) - 1: seq |= 0x40
        e = bytes([seq]) + b''.join(p[0:5]) + bytes([0x0F, 0, csum]) + b''.join(p[5:11]) + b'\0\0' + b''.join(p[11:13])
        ents.append(e)
    return list(reversed(ents))


def dirent(short, attr, cluster, size, mtime):
    d, t = fat_time(mtime)
    return short + struct.pack('<BBBHHHHHHHI', attr, 0, 0, t, d, d, 0, t, d, cluster & 0xFFFF, size)


def dir_bytes(node, parent_cluster, mtime, label=None):
    ents = []
    if label is not None:
        ents.append(label.upper().ljust(11)[:11].encode('ascii') + struct.pack('<BBBHHHHHHHI', 0x08, 0, 0, 0, 0, 0, 0, *fat_time(mtime)[::-1], 0, 0))
    else:
        ents.append(dirent(b'.          ', 0x10, node.cluster, 0, mtime))
        ents.append(dirent(b'..         ', 0x10, parent_cluster, 0, mtime))
    for ch, (sn, needlfn) in zip(node.children, short_names([c.name for c in node.children])):
        if needlfn: ents.extend(lfn_entries(ch.name, sn))
        ents.append(dirent(sn, 0x10 if ch.isdir else 0x20, ch.cluster, 0 if ch.isdir else ch.size, mtime))
    return b''.join(ents)


def count_entries(node):
    n = 2
    for ch, (sn, needlfn) in zip(node.children, short_names([c.name for c in node.children])):
        n += 1 + (((len(ch.name.encode('utf-16-le')) // 2) + 12) // 13 if needlfn else 0)
    return n


def build(base, tree, out, label='OCTOFUSION'):
    mtime = int(os.environ.get('SOURCE_DATE_EPOCH', time.time()))
    root = walk(tree)
    data_bytes = 0
    def need(n):
        nonlocal data_bytes
        for c in n.children:
            if c.isdir:
                data_bytes += count_entries(c) * 32 + 8192
                need(c)
            else:
                data_bytes += c.size + 8192
    need(root)
    total = (data_bytes + SPARE) // SEC + 2048
    spc = 1
    while total // spc > 65000: spc *= 2
    if total // spc < 4200: total = 4200 * spc + 2048      # FAT16 needs at least 4085 clusters
    clus = SEC * spc
    res, nfat, rootents = 4, 2, 512
    rootsecs = rootents * 32 // SEC
    nclus_est = total // spc
    fatsecs = ((nclus_est + 2) * 2 + SEC - 1) // SEC
    first_data = res + nfat * fatsecs + rootsecs
    nclus = (total - first_data) // spc
    assert 4085 <= nclus <= 65524, nclus

    # allocate: folders first (breadth), then files, each contiguous
    nxt = [2]
    def alloc(nbytes):
        n = max(1, (nbytes + clus - 1) // clus)
        c = nxt[0]; nxt[0] += n
        return c, n
    order = []
    def visit(n):
        for c in n.children:
            if c.isdir:
                c.cluster, c.nclus = alloc(count_entries(c) * 32)
            order.append(c)
        for c in n.children:
            if c.isdir: visit(c)
    visit(root)
    for c in order:
        if not c.isdir and c.size:
            c.cluster, c.nclus = alloc(c.size)
    assert nxt[0] - 2 <= nclus, 'the tree does not fit'
    if count_entries(root) - 1 > rootents: raise SystemExit('too many entries in the root folder')

    fat = bytearray(fatsecs * SEC)
    struct.pack_into('<HH', fat, 0, 0xFFF8, 0xFFFF)
    for c in order:
        if c.nclus:
            for i in range(c.nclus):
                v = 0xFFFF if i == c.nclus - 1 else c.cluster + i + 1
                struct.pack_into('<H', fat, (c.cluster + i) * 2, v)

    vol_id = int.from_bytes(os.urandom(4), 'little') if not os.environ.get('SOURCE_DATE_EPOCH') else mtime & 0xFFFFFFFF
    bs = bytearray(SEC)
    bs[0:3] = b'\xEB\x3C\x90'
    bs[3:11] = b'MSWIN4.1'
    struct.pack_into('<HBHBHHBHHHII', bs, 11, SEC, spc, res, nfat, rootents,
                     total if total < 65536 else 0, 0xF8, fatsecs, 63, 255, P1_START, total if total >= 65536 else 0)
    struct.pack_into('<BBBI', bs, 36, 0x80, 0, 0x29, vol_id)
    bs[43:54] = label.upper().ljust(11)[:11].encode('ascii')
    bs[54:62] = b'FAT16   '
    bs[510:512] = b'\x55\xAA'

    with open(base, 'rb') as f:
        head = bytearray(f.read(P1_START * SEC))
    if len(head) != P1_START * SEC: raise SystemExit('the base image is too short')
    # the partition table: 1 = the data (0x0b, as Mr. Fusion's), 2 = the bootloader (0xa2, kept)
    def pent(boot, typ, start, size):
        return struct.pack('<B3sB3sII', boot, b'\xFE\xFF\xFF', typ, b'\xFE\xFF\xFF', start, size)
    t1 = struct.unpack_from('<II', head, 446 + 8); t2 = struct.unpack_from('<II', head, 462 + 8)
    if head[446 + 4] != 0x0B or head[462 + 4] != 0xA2 or t2 != (P2_START, P2_SIZE) or t1[0] != P1_START:
        raise SystemExit('the base image is not laid out as Mr. Fusion\'s (p1 0x0b at 10240, p2 0xa2 at 2048+8192)')
    head[446:462] = pent(0, 0x0B, P1_START, total)
    head[462:478] = pent(0, 0xA2, P2_START, P2_SIZE)
    head[478:510] = bytes(32)
    head[510:512] = b'\x55\xAA'

    with open(out, 'wb') as o:
        o.write(head)
        o.write(bs)
        o.write(bytes((res - 1) * SEC))
        for _ in range(nfat): o.write(fat)
        rootdir = dir_bytes(root, 0, mtime, label=label)
        o.write(rootdir.ljust(rootsecs * SEC, b'\0'))
        base_off = (P1_START + first_data) * SEC
        def put(c, data):
            o.seek(base_off + (c.cluster - 2) * clus)
            o.write(data)
        # folders and files
        def write_dir(n, parent_cluster):
            for c in n.children:
                if c.isdir:
                    put(c, dir_bytes(c, parent_cluster, mtime).ljust(c.nclus * clus, b'\0'))
                    write_dir(c, c.cluster)
                elif c.size:
                    o.seek(base_off + (c.cluster - 2) * clus)
                    with open(c.path, 'rb') as f:
                        while True:
                            b = f.read(1 << 20)
                            if not b: break
                            o.write(b)
        write_dir(root, 0)
        o.truncate((P1_START + total) * SEC)
    print('image: %s  (%d MB; data partition FAT16, %d clusters of %d KB, %d used)' %
          (out, (P1_START + total) * SEC >> 20, nclus, clus // 1024, nxt[0] - 2))


if __name__ == '__main__':
    if len(sys.argv) < 4: raise SystemExit(__doc__ or 'octofat.py BASE.img TREE OUT.img [LABEL]')
    build(sys.argv[1], sys.argv[2], sys.argv[3], *(sys.argv[4:5]))
