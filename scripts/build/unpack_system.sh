#!/bin/bash
# 解 system_a.img 并复制出可写目录
set -e
cd /root/s8
echo "=== 1. 镜像信息 ==="
ls -la system_a.img
echo ""
echo "=== 2. 挂载 ==="
mkdir -p /mnt/sysA_ro
umount /mnt/sysA_ro 2>/dev/null || true
mount -o loop,ro system_a.img /mnt/sysA_ro
echo "挂载成功"
du -sh /mnt/sysA_ro
echo ""
echo "=== 3. 复制到可写目录（保留 xattr/权限/链接）==="
rm -rf sysbuild && mkdir -p sysbuild
cp -a /mnt/sysA_ro/. sysbuild/
echo "复制完成"
du -sh sysbuild
echo ""
echo "=== 4. 校验文件数 ==="
echo "原: $(find /mnt/sysA_ro | wc -l)  新: $(find sysbuild | wc -l)"
echo ""
echo "=== 5. 定位安装器 APK ==="
ls -la sysbuild/priv-app/BPackageInstaller/
echo ""
echo "=== 6. 标签抽查 ==="
getfattr -d -m security.selinux sysbuild/bin/init 2>&1 | grep selinux
getfattr -d -m security.selinux sysbuild/priv-app/BPackageInstaller/BPackageInstaller.apk 2>&1 | grep selinux
echo UNPACK_DONE
