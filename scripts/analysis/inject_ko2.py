import struct, hashlib, os, subprocess, shutil, sys

SRC = "/root/s8/img/twrp_s8native_full.img"
KO  = "/root/s8/bm2/bm2.ko"
OUT = "/root/s8/img/twrp_s8_bm2.img"
P = 4096
al = lambda n: (n + P - 1) // P * P
TOTAL = 104857600

d = open(SRC, "rb").read()
assert d[:8] == b"VNDRBOOT"
vrs, = struct.unpack("<I", d[24:28])
dts, = struct.unpack("<I", d[2100:2104])
rd_off = P
dtb_off = P + al(vrs)
dtb = d[dtb_off:dtb_off + dts]
print(f"源: ramdisk={vrs} dtb={dts} dtb_md5={hashlib.md5(dtb).hexdigest()}")

work = "/root/s8/vbwork2"
shutil.rmtree(work, ignore_errors=True)
os.makedirs(work)
open("/tmp/in.lz4", "wb").write(d[rd_off:rd_off + vrs])
for cmd in (["lz4","-d","-f","/tmp/in.lz4","/tmp/in.cpio"],):
    r = subprocess.run(cmd, capture_output=True)
    assert r.returncode == 0, r.stderr[:200]
raw = open("/tmp/in.cpio","rb").read()
os.chdir(work)
subprocess.run(["cpio","-id","--quiet"], input=raw, capture_output=True)
print("解包条目:", len([x for x in subprocess.run(["find",".","-mindepth","1"],capture_output=True).stdout.decode().split("\n") if x]))

# 注入
shutil.copyfile(KO, os.path.join(work, "lib/modules/bm.ko"))
ml = os.path.join(work, "lib/modules/modules.load")
s = open(ml).read()
if "bm2.ko" not in s:
    if not s.endswith("\n"): s += "\n"
    s += "bm.ko\n"
    open(ml,"w").write(s)
print("modules.load 末尾:", open(ml).read().strip().split("\n")[-3:])

os.chdir(work)
subprocess.run("find . -print0 | cpio --null -o -H newc --owner 0:0 --quiet > /root/s8/bm1.cpio", shell=True, check=True)
subprocess.run(["lz4","-l","-12","-f","/root/s8/bm1.cpio","/root/s8/bm1.lz4"], capture_output=True, check=True)
rd = open("/root/s8/bm1.lz4","rb").read()
print(f"新 ramdisk={len(rd)} (+{len(rd)-vrs})")

hdr = bytearray(d[:P])
struct.pack_into("<I", hdr, 24, len(rd))
out = bytearray(hdr) + rd
out += b"\0" * (al(len(out)) - len(out))
out += dtb
assert len(out) <= TOTAL, f"超限 {len(out)}"
out += b"\0" * (TOTAL - len(out))
open(OUT,"wb").write(bytes(out))
print(f"写出 {OUT}\nSHA256 {hashlib.sha256(bytes(out)).hexdigest()}\nsize {len(out)}")
