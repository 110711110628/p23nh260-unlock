import struct, subprocess, os, hashlib

p = '/root/s8/twrp/twrp_v120.img'
d = open(p, 'rb').read()
print("size:", len(d), "==", 100*1024*1024, ":", len(d) == 100*1024*1024)
print("magic:", d[:16])
# vendor_boot v4 layout
# magic[8] version[4] page_size[4] kernel_addr[4] ramdisk_addr[4]
# vendor_ramdisk_size[4] cmdline[2048] tags_addr[4] name[16] header_size[4] dtb_size[4] dtb_addr[8]
# v4 adds: vendor_ramdisk_table_size[4] vendor_ramdisk_table_entry_num[4]
#         vendor_ramdisk_table_entry_size[4] bootconfig_size[4]
h = d
print("version:", struct.unpack('<I', h[8:12])[0], "page:", struct.unpack('<I', h[12:16])[0])
print("kernel_addr: 0x%x ramdisk_addr: 0x%x" % (struct.unpack('<I',h[16:20])[0], struct.unpack('<I',h[20:24])[0]))
vr = struct.unpack('<I', h[24:28])[0]
cmd = h[28:28+2048].rstrip(b'\0')
print("vendor_ramdisk_size:", vr, hex(vr))
print("cmdline:", cmd[:200])
name = h[28+2048+4:28+2048+4+16].rstrip(b'\0')
print("name:", name)
hs = struct.unpack('<I', h[28+2048+4+16:28+2048+4+16+4])[0]
dtb_size = struct.unpack('<I', h[28+2048+4+16+4:28+2048+4+16+8])[0]
dtb_addr = struct.unpack('<Q', h[28+2048+4+16+8:28+2048+4+16+16])[0]
print("header_size:", hs, "dtb_size:", dtb_size, "dtb_addr: 0x%x" % dtb_addr)
o = 28+2048+4+16+16
vrt_size, vrt_num, vrt_esz, bc_size = struct.unpack('<IIII', h[o:o+16])
print("ramdisk_table:", vrt_size, vrt_num, vrt_esz, "bootconfig:", bc_size)

P = 4096
def al(n): return (n + P - 1)//P*P
off = al(hs)
print("\nsections start 0x%x" % off)
open('/tmp/twrp_vrd.lz4','wb').write(d[off:off+vr])
dtb = d[off+al(vr): off+al(vr)+dtb_size]
open('/tmp/twrp_dtb.img','wb').write(dtb)
print("dtb magic:", dtb[:8], "size", len(dtb))

r = subprocess.run(['lz4','-d','-f','/tmp/twrp_vrd.lz4','/tmp/twrp_vrd.cpio'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
print("lz4 rc:", r.returncode, r.stderr[:120])
if os.path.exists('/tmp/twrp_vrd.cpio'):
    raw = open('/tmp/twrp_vrd.cpio','rb').read()
    print("ramdisk cpio size:", len(raw))
    out = subprocess.run(['cpio','-it'], input=raw, capture_output=True).stdout.decode()
    lines = [l for l in out.split('\n') if l]
    print("entries:", len(lines))
    for kw in ('init','twres','sbin','system/bin/sh','etc/recovery.fstab','lib/modules','init.recovery'):
        hit = [l for l in lines if kw in l][:4]
        print(f"  [{kw}] {len([l for l in lines if kw in l])} -> {hit}")
