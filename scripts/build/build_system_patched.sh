#!/bin/bash
# 替换 system 镜像里的安装器 + 重建镜像
set -e
cd /root/s8
SB=/root/s8/sysbuild
APKDIR=$SB/system/priv-app/BPackageInstaller
NEW=/root/s8/patcher/BPackageInstaller_new.apk

echo "=== 1. 确认路径 ==="
ls -la "$APKDIR/"
echo "原 APK 标签:"
getfattr -d -m security.selinux "$APKDIR/BPackageInstaller.apk" 2>&1 | grep selinux

echo ""
echo "=== 2. 备份原 APK ==="
cp "$APKDIR/BPackageInstaller.apk" /root/s8/patcher/BPackageInstaller_orig.apk
ls -la /root/s8/patcher/BPackageInstaller_orig.apk

echo ""
echo "=== 3. 原地替换（保留 inode/xattr/owner/mode）==="
cat "$NEW" > "$APKDIR/BPackageInstaller.apk"
ls -la "$APKDIR/BPackageInstaller.apk"
getfattr -d -m security.selinux "$APKDIR/BPackageInstaller.apk" 2>&1 | grep selinux

echo ""
echo "=== 4. 确认替换的是补丁版（BPK 头）==="
od -An -tx1 -N4 "$APKDIR/BPackageInstaller.apk"

echo ""
echo "=== 5. 重建 erofs 镜像（lz4hc）==="
rm -f system_new.img
mkdir -p /tmp/mklog
time mkfs.erofs -z lz4hc -T 0 -d 2 system_new.img "$SB" 2>&1 | tail -4
SZ=$(stat -c %s system_new.img)
TARGET=3094769664
echo "新镜像: $SZ  目标: $TARGET"
if [ "$SZ" -gt "$TARGET" ]; then echo "!! 超出目标大小"; exit 1; fi
truncate -s $TARGET system_new.img
ls -la system_new.img

echo ""
echo "=== 6. 特性对比（必须与原来一致）==="
python3 - <<'PY'
import struct
def feat(p):
    d=open(p,'rb').read(4096); sb=d[1024:]
    return struct.unpack_from('<I', sb, 8)[0], struct.unpack_from('<I', sb, 80)[0]
a=feat('/root/s8/system_a.img'); b=feat('/root/s8/system_new.img')
print("原: compat=0x%x incompat=0x%x" % a)
print("新: compat=0x%x incompat=0x%x" % b)
print("incompat 一致:", a[1]==b[1])
PY

echo ""
echo "=== 7. 挂载验证（安装器存在且可解析）==="
mkdir -p /mnt/sysnew; umount /mnt/sysnew 2>/dev/null || true
mount -o loop,ro /root/s8/system_new.img /mnt/sysnew
ls -la /mnt/sysnew/system/priv-app/BPackageInstaller/ 2>/dev/null
python3 /root/s8/bpk_converter.py info /mnt/sysnew/system/priv-app/BPackageInstaller/BPackageInstaller.apk 2>&1 | head -6
echo "--- 文件数 ---"
echo "新: $(find /mnt/sysnew | wc -l)  原: $(find /mnt/sysA_ro | wc -l)"
umount /mnt/sysnew

echo ""
sha256sum system_new.img
echo BUILD_SYSTEM_DONE
