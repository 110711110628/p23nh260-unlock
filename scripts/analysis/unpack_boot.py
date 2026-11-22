#!/usr/bin/env python3
# 解 Android boot image (header v3/v4)，提取 ramdisk 并识别压缩格式
import struct, sys, os, subprocess

P = sys.argv[1] if len(sys.argv) > 1 else '/root/s8/img/boot_s8_wrap6.img'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/root/s8/ramdisk'

d = open(P, 'rb').read()
if d[:8] != b'ANDROID!':
    print('not an android boot image'); sys.exit(1)

kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from('<IIII', d, 8)
hv = struct.unpack_from('<I', d, 40)[0]
cmdline = d[44:44+1536].split(b'\x00')[0].decode('utf8', 'replace')
print(f'header_version={hv} header_size={header_size}')
print(f'kernel_size={kernel_size} ramdisk_size={ramdisk_size}')
print(f'cmdline={cmdline!r}')

def align(x, a=4096):
    return (x + a - 1) // a * a

cands = []
base = align(header_size)
cands.append(('hdr_align', base + kernel_size))
cands.append(('hdr_align_align', base + align(kernel_size)))
cands.append(('hdr_raw', header_size + kernel_size))

def magic_at(off):
    if off + 8 > len(d):
        return None
    m = d[off:off+8]
    if m[:3] == b'\x1f\x8b\x08':
        return 'gzip'
    if m[:4] == b'\x04\x22\x4d\x18':
        return 'lz4'
    if m[:4] == b'\x02\x21\x4c\x18':
        return 'lz4legacy'
    if m[:6] == b'\xfd7zXZ\x00':
        return 'xz'
    if m[:4] == b'\x28\xb5\x2f\xfd':
        return 'zstd'
    if m[:6] in (b'070701', b'070702'):
        return 'cpio'
    if m[:2] == b'BZ':
        return 'bzip2'
    return None

chosen = None
for name, off in cands:
    m = magic_at(off)
    print(f'  候选 {name}: offset={off} magic={m}')
    if m and not chosen:
        chosen = (name, off, m)

if not chosen:
    print('!! 候选位置都没有压缩/cpio magic，做全盘扫描')
    for m, sig, label in [
        (lambda o: d[o:o+3] == b'\x1f\x8b\x08', 3, 'gzip'),
        (lambda o: d[o:o+4] == b'\x04\x22\x4d\x18', 4, 'lz4'),
        (lambda o: d[o:o+6] == b'070701', 6, 'cpio'),
    ]:
        hits = []
        i = 0
        while True:
            i = d.find(sig, i)
            if i < 0: break
            hits.append(i)
            i += 1
            if len(hits) > 6: break
        if hits:
            print(f'  {label} @ {hits[:6]}')
    sys.exit(2)

name, off, kind = chosen
print(f'==> 采用 {name} offset={off} type={kind}')
size = ramdisk_size if ramdisk_size and off + ramdisk_size <= len(d) else len(d) - off
blob = d[off:off+size]
raw = OUT + '.bin'
open(raw, 'wb').write(blob)
print(f'ramdisk blob -> {raw} ({len(blob)} bytes)')

if kind == 'gzip':
    subprocess.run(['sh', '-c', f'gzip -dc {raw} > {OUT}.cpio 2>/dev/null'], check=False)
elif kind in ('lz4', 'lz4legacy'):
    subprocess.run(['sh', '-c', f'lz4 -dc {raw} > {OUT}.cpio 2>/dev/null || lz4cat {raw} > {OUT}.cpio 2>/dev/null'], check=False)
elif kind == 'cpio':
    subprocess.run(['sh', '-c', f'cp {raw} {OUT}.cpio'], check=False)

cp = OUT + '.cpio'
if os.path.exists(cp) and os.path.getsize(cp) > 0:
    print(f'unpacked cpio -> {cp} ({os.path.getsize(cp)} bytes)')
    print('=== cpio 内容 ===')
    subprocess.run(['sh', '-c', f'cpio -itv < {cp} 2>/dev/null | head -60'], check=False)
else:
    print('!! 未能解出 cpio')
