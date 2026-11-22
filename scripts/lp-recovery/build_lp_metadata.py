#!/usr/bin/env python3
# 构建 G12 LP 元数据 v3 —— 严格按 Android 13 liblp metadata_format.h
import struct, hashlib

OUT = '/root/g12diag/super_meta_v3.bin'
SUPER_SIZE = 0x128A00000
METADATA_MAX_SIZE = 65536
METADATA_SLOT_COUNT = 2
LOGICAL_BLOCK_SIZE = 4096
FIRST_LOGICAL_SECTOR = 0x800   # 2048 扇区 = 1MB（关键！）
RESERVED = 0x1000
GEO_SIZE = 0x1000

PARTITIONS = [('system_a',1,0,1,0), ('vendor_a',1,1,1,0), ('product_a',1,2,1,0)]
EXTENTS = [(0x342828,0,0x93800,0), (0xAFDF0,0,0x3E6800,0), (0x92FE8,0,0x800,0)]
GROUPS = [('main',0,0)]
BLOCKDEV = ('super', FIRST_LOGICAL_SECTOR, 0x100000, 0, SUPER_SIZE, 0)

PART_ENT, EXT_ENT, GRP_ENT, BD_ENT = 52, 24, 48, 64
HEADER_SIZE = 256

def build_geometry():
    geo = bytearray(52)
    struct.pack_into('<I', geo, 0, 0x616c4467)
    struct.pack_into('<I', geo, 4, 52)
    struct.pack_into('<I', geo, 40, METADATA_MAX_SIZE)
    struct.pack_into('<I', geo, 44, METADATA_SLOT_COUNT)
    struct.pack_into('<I', geo, 48, LOGICAL_BLOCK_SIZE)
    z = bytearray(geo); z[8:40] = b'\x00'*32
    geo[8:40] = hashlib.sha256(bytes(z)).digest()
    return bytes(geo)

def build_tables():
    t = bytearray()
    for name, attr, fe, ne, grp in PARTITIONS:
        e = bytearray(PART_ENT); e[0:len(name)] = name.encode()
        struct.pack_into('<IIII', e, 36, attr, fe, ne, grp); t += e
    for ns, tt, td, ts in EXTENTS:
        e = bytearray(EXT_ENT)
        struct.pack_into('<Q', e, 0, ns); struct.pack_into('<I', e, 8, tt)
        struct.pack_into('<Q', e, 12, td); struct.pack_into('<I', e, 20, ts); t += e
    for name, flags, maxsz in GROUPS:
        e = bytearray(GRP_ENT); e[0:len(name)] = name.encode()
        struct.pack_into('<I', e, 36, flags); struct.pack_into('<Q', e, 40, maxsz); t += e
    name, first_ls, align, align_off, size, flags = BLOCKDEV
    e = bytearray(BD_ENT)
    struct.pack_into('<Q', e, 0, first_ls); struct.pack_into('<I', e, 8, align)
    struct.pack_into('<I', e, 12, align_off); struct.pack_into('<Q', e, 16, size)
    e[24:24+len(name)] = name.encode(); struct.pack_into('<I', e, 60, flags); t += e
    return bytes(t)

def build_header(tables):
    h = bytearray(HEADER_SIZE)
    struct.pack_into('<I', h, 0, 0x414c5030)
    struct.pack_into('<H', h, 4, 10)   # major
    struct.pack_into('<H', h, 6, 2)    # minor (>=2 → expanded 256 字节 header)
    struct.pack_into('<I', h, 8, HEADER_SIZE)
    # 44: tables_size
    struct.pack_into('<I', h, 44, len(tables))
    # 48: tables_checksum = SHA256(tables)
    h[48:80] = hashlib.sha256(tables).digest()
    # 80: descriptors (offset 相对 header 末尾即 header_start+header_size)
    part_off = 0
    ext_off = len(PARTITIONS)*PART_ENT
    grp_off = ext_off + len(EXTENTS)*EXT_ENT
    bd_off = grp_off + len(GROUPS)*GRP_ENT
    descs = [(part_off,len(PARTITIONS),PART_ENT),
             (ext_off,len(EXTENTS),EXT_ENT),
             (grp_off,len(GROUPS),GRP_ENT),
             (bd_off,1,BD_ENT)]
    for i,(o,n,en) in enumerate(descs):
        struct.pack_into('<III', h, 80+i*12, o, n, en)
    # 128: flags = 0; 132..256 reserved = 0
    # 12: header_checksum = SHA256(header[0:256] with checksum zeroed)
    z = bytearray(h); z[12:44] = b'\x00'*32
    h[12:44] = hashlib.sha256(bytes(z)).digest()
    return bytes(h)

def main():
    geo = build_geometry()
    tables = build_tables()
    header = build_header(tables)

    total_meta = RESERVED + GEO_SIZE*2 + METADATA_MAX_SIZE*2*METADATA_SLOT_COUNT
    print(f"metadata 区大小 = {total_meta} 字节 = {total_meta//512} 扇区 (需 <= first_logical_sector={FIRST_LOGICAL_SECTOR})")
    assert total_meta // 512 <= FIRST_LOGICAL_SECTOR, "元数据区与分区重叠!"

    blob = bytearray(total_meta)
    blob[RESERVED:RESERVED+52] = geo
    blob[RESERVED+GEO_SIZE:RESERVED+GEO_SIZE+52] = geo
    for slot in range(METADATA_SLOT_COUNT):
        base = RESERVED + GEO_SIZE*2 + slot*2*METADATA_MAX_SIZE
        for copy in (base, base+METADATA_MAX_SIZE):
            blob[copy:copy+HEADER_SIZE] = header
            blob[copy+HEADER_SIZE:copy+HEADER_SIZE+len(tables)] = tables
    open(OUT,'wb').write(bytes(blob))
    print(f"已写出 {OUT} ({len(blob)} 字节)")

    # 严格按 reader.cpp 逻辑自验证
    print("\n=== 按 AOSP reader.cpp 逻辑验证 ===")
    d = bytes(blob)
    # 1. geometry
    g = d[RESERVED:RESERVED+52]
    assert struct.unpack_from('<I', g, 0)[0] == 0x616c4467
    z = bytearray(g); z[8:40] = b'\x00'*32
    assert hashlib.sha256(bytes(z)).digest() == bytes(g[8:40]), "geometry checksum 失败"
    mms, sc, lbs = struct.unpack_from('<III', g, 40)
    print(f"  geometry: magic ok, max_size={mms}, slots={sc}, lbs={lbs} ✓")
    # 2. header
    h = d[RESERVED+2*GEO_SIZE:RESERVED+2*GEO_SIZE+HEADER_SIZE]
    assert struct.unpack_from('<I', h, 0)[0] == 0x414c5030
    major, minor = struct.unpack_from('<HH', h, 4)
    hs = struct.unpack_from('<I', h, 8)[0]
    ts = struct.unpack_from('<I', h, 44)[0]
    print(f"  header: magic ok, version={major}.{minor}, header_size={hs}, tables_size={ts}")
    z = bytearray(h); z[12:44] = b'\x00'*32
    assert hashlib.sha256(bytes(z)).digest() == bytes(h[12:44]), "header checksum 失败"
    print("  header_checksum ✓")
    tables_b = d[RESERVED+2*GEO_SIZE+HEADER_SIZE:RESERVED+2*GEO_SIZE+HEADER_SIZE+ts]
    assert hashlib.sha256(tables_b).digest() == bytes(h[48:80]), "tables checksum 失败"
    print("  tables_checksum ✓")
    # 3. 表边界
    for i, nm in enumerate(['partitions','extents','groups','block_devices']):
        o, n, e = struct.unpack_from('<III', h, 80+i*12)
        assert o <= ts and ts - o >= n*e, f"{nm} 表越界"
        print(f"  {nm}: offset={o} num={n} entry={e} ✓")
    # 4. blockdev first_logical_sector
    bd_off = struct.unpack_from('<I', h, 116)[0]
    first_ls = struct.unpack_from('<Q', tables_b, bd_off)[0]
    total_meta_bytes = RESERVED + GEO_SIZE*2 + mms*2*sc
    print(f"  blockdev first_logical_sector={first_ls} (需要 >= {total_meta_bytes//512}) ✓" if first_ls*512 >= total_meta_bytes else "  blockdev 重叠 ✗")
    # 5. 分区/扩展引用
    for i in range(3):
        po = struct.unpack_from('<I', h, 80)[0] + i*52
        name = tables_b[po:po+36].split(b'\0')[0].decode()
        attr, fe, ne, grp = struct.unpack_from('<IIII', tables_b, po+36)
        eo = struct.unpack_from('<I', h, 92)[0] + fe*24
        ns = struct.unpack_from('<Q', tables_b, eo)[0]
        td = struct.unpack_from('<Q', tables_b, eo+12)[0]
        print(f"  {name}: attr={attr} extents={ne} group={grp} -> sectors={ns} data=0x{td:x} ✓")

if __name__ == '__main__':
    main()
