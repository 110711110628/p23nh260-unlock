#!/usr/bin/env python3
# 精确扫描 super，验证 ext4 超级块，定位逻辑分区
import struct, os

P = '/root/g12diag/super_full.img'
SIZE = os.path.getsize(P)
print("文件:", P, SIZE, "bytes")

def valid_ext4(sb):
    """验证 ext4 superblock（1024 字节）"""
    if len(sb) < 1024:
        return None
    magic, = struct.unpack_from('<H', sb, 0x38)
    if magic != 0xEF53:
        return None
    log_bs, = struct.unpack_from('<I', sb, 0x18)
    if log_bs > 6:
        return None
    bs = 1024 << log_bs
    blocks_lo, = struct.unpack_from('<I', sb, 0x04)
    blocks_hi, = struct.unpack_from('<I', sb, 0x150) if len(sb) >= 0x154 else (0,)
    blocks_hi = struct.unpack_from('<I', sb, 0x150)[0]
    blocks = blocks_lo | (blocks_hi << 32)
    if blocks <= 0 or blocks > 0x200000000:
        return None
    label = sb[0x78:0x88].split(b'\0')[0].decode('latin1', 'replace')
    state, = struct.unpack_from('<H', sb, 0x3a)
    return dict(block_size=bs, blocks=blocks, size_bytes=blocks * bs, label=label, state=state)

hits = []
CHUNK = 8 * 1024 * 1024
with open(P, 'rb') as f:
    off = 0
    while True:
        f.seek(off)
        data = f.read(CHUNK + 0x800)
        if not data:
            break
        i = 0
        while True:
            j = data.find(b'\x53\xef', i)
            if j < 0:
                break
            # 超级块位置 = j - 0x38（magic 在 sb 偏移 0x38）
            sb_off = off + j - 0x38
            if sb_off >= 1024 and (sb_off - 1024) % 1024 == 0:
                f.seek(sb_off)
                sb = f.read(1024)
                v = valid_ext4(sb)
                if v:
                    part_start = sb_off - 1024
                    hits.append((part_start, v))
            i = j + 1
        off += CHUNK
        if len(hits) > 60:
            break

print(f"\n合法 ext4 超级块: {len(hits)} 个")
for start, v in hits:
    print(f"  start=0x{start:x} ({start/MB if False else start})  block={v['block_size']}  size={v['size_bytes']/1048576:.1f}MB  label={v['label']!r}  state={v['state']}")

# 输出分区边界（去重、按 start 排序）
print("\n按 start 排序:")
for start, v in sorted(hits, key=lambda x: x[0]):
    end = start + v['size_bytes']
    print(f"  0x{start:010x} .. 0x{end:010x}  ({v['size_bytes']/1048576:9.1f}MB)  label={v['label']!r}")
