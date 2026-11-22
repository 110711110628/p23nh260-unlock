#!/usr/bin/env python3
"""把 ramdisk.cpio 里的 init 换掉，重新压成 lz4-legacy，再塞回 boot.img。

用法: repack_boot.py <原 boot.img> <ramdisk.cpio> <新 init 文件> <输出 boot.img>
"""
import sys, struct, subprocess, os, tempfile

PAGE = 4096

def align(n, a=PAGE):
    return (n + a - 1) // a * a

def parse_newc(data):
    """返回 [(header_bytes, name, data, pad_len, raw_entry_bytes)]"""
    out = []
    i = 0
    while i + 110 <= len(data):
        if data[i:i+6] not in (b'070701', b'070702'):
            break
        hdr = data[i:i+110]
        filesize = int(hdr[54:62], 16)
        namesize = int(hdr[94:102], 16)
        name = data[i+110:i+110+namesize-1].decode('utf-8', 'replace')
        dstart = i + 110 + namesize
        dstart = align(dstart, 4)
        dend = dstart + filesize
        next_i = align(dend, 4)
        out.append([hdr, name, data[dstart:dend], next_i - dend, data[i:next_i]])
        i = next_i
        if name == 'TRAILER!!!':
            break
    return out, i

def main():
    src, cpio_path, new_init, dst = sys.argv[1:5]
    img = open(src, 'rb').read()
    assert img[:8] == b'ANDROID!', 'bad magic'
    kernel_size = struct.unpack('<I', img[8:12])[0]
    ramdisk_size = struct.unpack('<I', img[12:16])[0]
    header_size = struct.unpack('<I', img[20:24])[0]
    hv = struct.unpack('<I', img[40:44])[0]
    print(f'header_size={header_size} header_version={hv} kernel={kernel_size} ramdisk={ramdisk_size}')

    k_off = PAGE
    r_off = k_off + align(kernel_size)
    tail_off = r_off + align(ramdisk_size)
    kernel = img[k_off:k_off+kernel_size]
    tail = img[tail_off:].rstrip(b'\0')
    print(f'kernel@0x{k_off:x} ramdisk@0x{r_off:x} tail@0x{tail_off:x} tail_len={len(tail)}')

    cpio = open(cpio_path, 'rb').read()
    entries, consumed = parse_newc(cpio)
    print(f'cpio entries={len(entries)} consumed={consumed} total={len(cpio)}')
    # TRAILER 之后是 0 填充
    trailer_pad = cpio[consumed:]

    init_data = open(new_init, 'rb').read()
    n_init = 0
    buf = bytearray()
    for hdr, name, data, pad, raw in entries:
        if name == 'init':
            h = bytearray(hdr)
            h[54:62] = b'%08X' % len(init_data)
            # 清掉原 checksum 字段占位（newc 用 0）
            buf += bytes(h) + name.encode() + b'\0'
            buf += b'\0' * (align(len(buf), 4) - len(buf))
            buf += init_data
            buf += b'\0' * (align(len(buf), 4) - len(buf))
            n_init += 1
        else:
            buf += raw
    assert n_init == 1, f'init entry count={n_init}'
    buf += trailer_pad
    open('/tmp/new_ramdisk.cpio', 'wb').write(buf)

    # lz4 legacy 压缩（内核 lz4 解压器支持 legacy 帧）
    subprocess.run(['lz4', '-l', '-12', '-f', '/tmp/new_ramdisk.cpio', '/tmp/new_ramdisk.lz4'], check=True,
                   stdout=subprocess.DEVNULL)
    new_rd = open('/tmp/new_ramdisk.lz4', 'rb').read()
    print(f'new ramdisk: cpio={len(buf)} lz4={len(new_rd)} (old {ramdisk_size})')

    head = bytearray(img[:header_size])
    head[12:16] = struct.pack('<I', len(new_rd))

    out = bytearray()
    out += head
    out += b'\0' * (k_off - len(out))
    out += kernel
    out += b'\0' * (align(len(out), PAGE) - len(out))
    out += new_rd
    out += b'\0' * (align(len(out), PAGE) - len(out))
    out += tail
    # boot 分区固定 64MB
    TARGET = 64 * 1024 * 1024
    if len(out) > TARGET:
        raise SystemExit(f'!! 超限 len={len(out)} > {TARGET}, ramdisk={len(new_rd)} '
                         f'(AVB tail 被顶出分区，必须缩小 ramdisk)')
    out += b'\0' * (TARGET - len(out))
    open(dst, 'wb').write(bytes(out))
    print(f'wrote {dst} size={len(out)} ({len(out)/1048576:.1f}MB)')

if __name__ == '__main__':
    main()
