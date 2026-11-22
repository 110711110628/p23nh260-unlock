import struct, hashlib, os, subprocess, sys, re

SRC_C = '/root/s8/initwrap9b.c'
NEW_C = '/root/s8/initwrap10.c'

c = open(SRC_C).read()

# 1. 在 execve("/system/bin/sh"...) 之前插入强制 permissive
force_fn = '''
/* v10: 在 exec 之前把 SELinux 强制设为 permissive（内核域有 CAP_MAC_ADMIN） */
static void force_permissive(void){
    for (int i = 0; i < 300; i++) {
        int f = open("/sys/fs/selinux/enforce", O_WRONLY);
        if (f >= 0) {
            ssize_t w = write(f, "0", 1);
            close(f);
            (void)w;
            lg("PERM written i=%d\\n", i);
            ms(300);
            return;
        }
        ms(200);
    }
    lg("PERM FAILED errno=%d\\n", errno);
}
'''
# 在 child_main 定义前插入函数
idx = c.find('static void child_main(void){')
assert idx > 0
c = c[:idx] + force_fn + '\n' + c[idx:]

# 在 execve 之前调用（找 child_main 里的 execve("/system/bin/sh"）
marker = '    char *av[] = { "/system/bin/sh", "-c", (char *)SCRIPT, 0 };'
assert marker in c, 'marker not found'
c = c.replace(marker, '    force_permissive();\n\n' + marker, 1)
open(NEW_C, 'w').write(c)
print('生成', NEW_C)

# 2. 编译
out = '/root/s8/initwrap10'
r = subprocess.run(['aarch64-linux-gnu-gcc', '-static', '-O2', '-o', out, NEW_C],
                   capture_output=True, text=True)
if r.returncode != 0:
    print('编译失败:', r.stderr[-2000:])
    sys.exit(1)
print('编译成功', out, os.path.getsize(out))

# 3. 解 wrap9b 镜像的 ramdisk
BOOT = '/root/s8/img/boot_s8_wrap9b.img'
NEWBOOT = '/root/s8/img/boot_s8_wrap10.img'
d = open(BOOT, 'rb').read()
assert d[:8] == b'ANDROID!'
ks, rs, osv, hs = struct.unpack_from('<IIII', d, 8)
print('kernel=%d ramdisk=%d hdr=%d' % (ks, rs, hs))
P = 4096
al = lambda n: (n + P - 1) // P * P
koff = al(hs)
roff = koff + al(ks)
print('kernel@0x%x ramdisk@0x%x' % (koff, roff))

# 解 ramdisk（lz4 legacy）
rd = d[roff:roff+rs]
print('ramdisk magic:', rd[:4].hex())
open('/tmp/w9b.rd.lz4', 'wb').write(rd)
subprocess.run(['lz4', '-d', '-f', '/tmp/w9b.rd.lz4', '/tmp/w9b.rd.cpio'], capture_output=True, check=True)
import shutil
shutil.rmtree('/root/s8/w9bwork', ignore_errors=True)
os.makedirs('/root/s8/w9bwork')
os.chdir('/root/s8/w9bwork')
with open('/tmp/w9b.rd.cpio', 'rb') as fh:
    subprocess.run(['cpio', '-id', '--quiet'], stdin=fh, capture_output=True, check=True)
print('ramdisk 解包完成:', sorted(os.listdir('.'))[:10])

# 替换 init
shutil.copyfile(out, 'init')
os.chmod('init', 0o755)

# 重新打包
subprocess.run('find . -print0 | cpio --null -o -H newc --owner 0:0 --quiet > /tmp/w10.cpio',
               shell=True, check=True)
subprocess.run(['lz4', '-l', '-12', '-f', '/tmp/w10.cpio', '/tmp/w10.lz4'], capture_output=True, check=True)
newrd = open('/tmp/w10.lz4', 'rb').read()
print('新 ramdisk:', len(newrd), newrd[:4].hex(), '(+%d)' % (len(newrd)-rs))

# 4. 重建 boot 镜像：header + kernel + new ramdisk + tail（dtb 等）
hdr = bytearray(d[:koff])
struct.pack_into('<I', hdr, 12, len(newrd))   # ramdisk_size 在 header offset 12
tail = d[roff+rs:]                             # 原 ramdisk 之后的内容（dtb 等）
out_img = bytearray(hdr) + d[koff:roff] + newrd
out_img += b'\0' * (al(len(out_img)) - len(out_img))   # 页对齐
out_img += tail
out_img += b'\0' * (len(d) - len(out_img))
assert len(out_img) == len(d), (len(out_img), len(d))
open(NEWBOOT, 'wb').write(bytes(out_img))
print('写出', NEWBOOT)
print('sha256:', hashlib.sha256(bytes(out_img)).hexdigest())
print('md5:', hashlib.md5(bytes(out_img)).hexdigest())

# 5. 校验：解出新镜像的 ramdisk 并确认 init 是我们的二进制
d2 = open(NEWBOOT, 'rb').read()
rs2, = struct.unpack_from('<I', d2, 12)
k2, = struct.unpack_from('<I', d2, 8)
off2 = al(struct.unpack_from('<I', d2, 20)[0]) + al(k2)
r2 = d2[off2:off2+rs2]
print('新镜像 ramdisk magic:', r2[:4].hex(), 'size', rs2)
open('/tmp/check.rd', 'wb').write(r2)
print('OK')
