#!/bin/bash
# 把静默安装器 + root 守护进程整合进 system 镜像并重建
set -e
cd /root/s8
SB=/root/s8/sysbuild
echo "=== 1. 检查 APK ==="
ls -la /root/s8/silent/build/S8Installer.apk
APK=/root/s8/silent/build/S8Installer.apk
[ -f "$APK" ] || { echo "APK 未构建"; exit 1; }

echo ""
echo "=== 2. 放入 system/priv-app ==="
mkdir -p "$SB/system/priv-app/S8Installer"
cp "$APK" "$SB/system/priv-app/S8Installer/S8Installer.apk"
chmod 644 "$SB/system/priv-app/S8Installer/S8Installer.apk"
chown 0:0 "$SB/system/priv-app/S8Installer/S8Installer.apk"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$SB/system/priv-app/S8Installer/S8Installer.apk"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$SB/system/priv-app/S8Installer" 2>/dev/null || true

echo ""
echo "=== 3. 特权权限白名单 ==="
cat > "$SB/system/etc/permissions/privapp-permissions-s8installer.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<permissions>
    <privapp-permissions package="com.s8.silentinstaller">
        <permission name="android.permission.INSTALL_PACKAGES"/>
        <permission name="android.permission.DELETE_PACKAGES"/>
        <permission name="android.permission.QUERY_ALL_PACKAGES"/>
        <permission name="android.permission.READ_INSTALL_SESSIONS"/>
        <permission name="android.permission.RECEIVE_BOOT_COMPLETED"/>
        <permission name="android.permission.REQUEST_INSTALL_PACKAGES"/>
    </privapp-permissions>
</permissions>
XML
chmod 644 "$SB/system/etc/permissions/privapp-permissions-s8installer.xml"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$SB/system/etc/permissions/privapp-permissions-s8installer.xml"

echo ""
echo "=== 4. root 守护进程 ==="
cp /root/s8/silent/s8root.sh "$SB/system/etc/s8root.sh"
chmod 755 "$SB/system/etc/s8root.sh"
chown 0:0 "$SB/system/etc/s8root.sh"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$SB/system/etc/s8root.sh"
cp /root/s8/silent/s8root.rc "$SB/system/etc/init/s8root.rc"
chmod 644 "$SB/system/etc/init/s8root.rc"
chown 0:0 "$SB/system/etc/init/s8root.rc"
# rc 文件标签：参照同目录其他 rc
LABEL=$(getfattr -d -m security.selinux "$SB/system/etc/init/usbd.rc" 2>/dev/null | grep -oE '"[^"]*"' | tr -d '"')
[ -n "$LABEL" ] || LABEL="u:object_r:system_file:s0"
setfattr -n security.selinux -v "$LABEL" "$SB/system/etc/init/s8root.rc"
echo "rc 标签: $LABEL"

echo ""
echo "=== 5. 校验放入结果 ==="
ls -la "$SB/system/priv-app/S8Installer/" "$SB/system/etc/s8root.sh" "$SB/system/etc/init/s8root.rc"
getfattr -d -m security.selinux "$SB/system/priv-app/S8Installer/S8Installer.apk" | grep selinux
getfattr -d -m security.selinux "$SB/system/etc/init/s8root.rc" | grep selinux

echo ""
echo "=== 6. 重建 erofs 镜像 ==="
rm -f system_new2.img
time mkfs.erofs -z lz4hc -T 0 -d 2 system_new2.img "$SB" 2>&1 | tail -3
SZ=$(stat -c %s system_new2.img)
TARGET=3094769664
echo "新镜像: $SZ 目标: $TARGET"
[ "$SZ" -le "$TARGET" ] || { echo "!! 超出大小"; exit 1; }
truncate -s $TARGET system_new2.img
sha256sum system_new2.img
md5sum system_new2.img

echo ""
echo "=== 7. 挂载验证 ==="
mkdir -p /mnt/sysnew2; umount /mnt/sysnew2 2>/dev/null || true
mount -o loop,ro system_new2.img /mnt/sysnew2
echo "--- 新增文件 ---"
ls -la /mnt/sysnew2/system/priv-app/S8Installer/ /mnt/sysnew2/system/etc/s8root.sh /mnt/sysnew2/system/etc/init/s8root.rc 2>/dev/null
echo "--- 安装器（补丁版还在）---"
ls -la /mnt/sysnew2/system/priv-app/BPackageInstaller/BPackageInstaller.apk
echo "--- 文件数 ---"
echo "新: $(find /mnt/sysnew2 | wc -l)"
umount /mnt/sysnew2
echo BUILD_SYSTEM2_DONE
