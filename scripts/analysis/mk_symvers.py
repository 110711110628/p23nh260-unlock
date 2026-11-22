#!/usr/bin/env python3
"""从设备原厂 161 个 .ko 的 __versions 段合并出权威 CRC 表 -> Module.symvers"""
import struct, os, sys, collections

D = sys.argv[1] if len(sys.argv) > 1 else "/root/s8/vb8/lib/modules"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/root/s8/Module.symvers.dev"

def sections(d):
    e_shoff, = struct.unpack("<Q", d[0x28:0x30])
    e_shentsize, = struct.unpack("<H", d[0x3a:0x3c])
    e_shnum, = struct.unpack("<H", d[0x3c:0x3e])
    e_shstrndx, = struct.unpack("<H", d[0x3e:0x40])
    b = e_shoff + e_shstrndx*e_shentsize
    so, = struct.unpack("<Q", d[b+0x18:b+0x20])
    ss, = struct.unpack("<Q", d[b+0x20:b+0x28])
    st = d[so:so+ss]
    out = {}
    for i in range(e_shnum):
        b = e_shoff + i*e_shentsize
        no, = struct.unpack("<I", d[b:b+4])
        off, = struct.unpack("<Q", d[b+0x18:b+0x20])
        sz, = struct.unpack("<Q", d[b+0x20:b+0x28])
        e = st.find(b"\0", no)
        out[st[no:e].decode("utf-8","replace")] = (off, sz)
    return out

def versions(path):
    d = open(path,"rb").read()
    s = sections(d)
    if "__versions" not in s: return {}
    off, sz = s["__versions"]
    r = {}
    for i in range(0, sz, 64):
        c = d[off+i:off+i+64]
        if len(c) < 64: break
        crc, = struct.unpack("<Q", c[:8])
        nm = c[8:64].split(b"\0")[0].decode("utf-8","replace")
        if nm: r[nm] = crc & 0xffffffff
    return r

allc = {}
conflict = collections.defaultdict(set)
mods = sorted(f for f in os.listdir(D) if f.endswith(".ko"))
for f in mods:
    v = versions(os.path.join(D,f))
    for k, crc in v.items():
        if k in allc and allc[k] != crc:
            conflict[k].add(allc[k]); conflict[k].add(crc)
        allc[k] = crc

print(f"扫描 {len(mods)} 个模块，符号 {len(allc)} 个")
print(f"CRC 冲突的符号: {len(conflict)} {list(conflict)[:5]}")
ml = allc.get("module_layout")
print(f"module_layout = {hex(ml) if ml else 'MISSING'}  （设备真值应为 0xa7fc3460）")
for probe in ("kallsyms_lookup_name","register_kprobe","unregister_kprobe","kprobe_register",
              "do_exit","vfs_read","kern_path","filp_open","iterate_dir","__stack_chk_fail"):
    print(f"  {probe:26s} {hex(allc[probe]) if probe in allc else '-'}")

lines = [f"0x{c:08x}\t{k}\tvmlinux\tEXPORT_SYMBOL" for k,c in sorted(allc.items())]
open(OUT,"w").write("\n".join(lines)+"\n")
print(f"写出 {OUT}  {len(lines)} 条")
