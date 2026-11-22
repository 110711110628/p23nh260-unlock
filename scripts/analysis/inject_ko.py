import struct, hashlib, os, subprocess, shutil, sys

SRC  = os.path.abspath(sys.argv[1])
KO   = os.path.abspath(sys.argv[2])
NAME = os.path.basename(KO)             # 目标文件名（保持原名）
OUT  = os.path.abspath(sys.argv[3])
WORK = sys.argv[4] if len(sys.argv) > 4 else "/root/s8/vbwork"

P = 4096
al = lambda n: (n + P - 1) // P * P
TOTAL = 104857600

d = open(SRC, "rb").read()
assert d[:8] == b"VNDRBOOT"
vrs, = struct.unpack("<I", d[24:28])
dts, = struct.unpack("<I", d[2100:2104])
dtb = d[P + al(vrs):P + al(vrs) + dts]
print(f"源 ramdisk={vrs} dtb={dts} dtb_md5={hashlib.md5(dtb).hexdigest()}")

shutil.rmtree(WORK, ignore_errors=True); os.makedirs(WORK)
open("/tmp/in.lz4","wb").write(d[P:P+vrs])
assert subprocess.run(["lz4","-d","-f","/tmp/in.lz4","/tmp/in.cpio"], capture_output=True).returncode == 0
raw = open("/tmp/in.cpio","rb").read()
os.chdir(WORK)
subprocess.run(["cpio","-id","--quiet"], input=raw, capture_output=True)

shutil.copyfile(KO, os.path.join(WORK, "lib/modules", NAME))
ml = os.path.join(WORK, "lib/modules/modules.load")
s = open(ml).read()
if NAME not in s.split():
    if not s.endswith("\n"): s += "\n"
    s += NAME + "\n"
    open(ml,"w").write(s)
print("modules.load 尾部:", open(ml).read().split()[-3:])

subprocess.run("find . -print0 | cpio --null -o -H newc --owner 0:0 --quiet > /tmp/out.cpio", shell=True, check=True)
subprocess.run(["lz4","-l","-12","-f","/tmp/out.cpio","/tmp/out.lz4"], capture_output=True, check=True)
rd = open("/tmp/out.lz4","rb").read()
print(f"新 ramdisk={len(rd)} (+{len(rd)-vrs})")

hdr = bytearray(d[:P]); struct.pack_into("<I", hdr, 24, len(rd))
out = bytearray(hdr) + rd
out += b"\0" * (al(len(out)) - len(out))
out += dtb
assert len(out) <= TOTAL
out += b"\0" * (TOTAL - len(out))
open(OUT,"wb").write(bytes(out))
print(f"写出 {OUT}\nSHA256 {hashlib.sha256(bytes(out)).hexdigest()}\nsize {len(out)}")
