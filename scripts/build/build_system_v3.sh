#!/bin/bash
# 系统镜像 v3：加入华为应用市场（system/priv-app）+ INSTALL_PACKAGES 白名单
set -e
cd /root/s8
SB=/root/s8/sysbuild
APK=/root/s8/apks/hwyysc.apk

echo "=== 0. 检查 ==="
[ -f "$APK" ] || { echo "APK 不存在"; exit 1; }
ls -la "$APK"
ls -d "$SB" || { echo "sysbuild 不存在"; exit 1; }

echo ""
echo "=== 1. 删除旧的无效 S8Installer 副本（节省空间）==="
rm -rf "$SB/system/priv-app/S8Installer" 2>/dev/null || true
# 同时删除 system/etc 里旧的 s8root 脚本？保留（root 守护要用）
ls -la "$SB/system/priv-app/" | head -5

echo ""
echo "=== 2. 放入华为应用市场 ==="
mkdir -p "$SB/system/priv-app/HuaweiAppGallery"
cp "$APK" "$SB/system/priv-app/HuaweiAppGallery/HuaweiAppGallery.apk"
chmod 644 "$SB/system/priv-app/HuaweiAppGallery/HuaweiAppGallery.apk"
chown 0:0 "$SB/system/priv-app/HuaweiAppGallery/HuaweiAppGallery.apk"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$SB/system/priv-app/HuaweiAppGallery/HuaweiAppGallery.apk"
ls -la "$SB/system/priv-app/HuaweiAppGallery/"

echo ""
echo "=== 3. 特权权限白名单 ==="
cat > "$SB/system/etc/permissions/privapp-permissions-huawei.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<permissions>
    <privapp-permissions package="com.huawei.appmarket">
        <permission name="android.permission.INSTALL_PACKAGES"/>
        <permission name="android.permission.DELETE_PACKAGES"/>
        <permission name="android.permission.QUERY_ALL_PACKAGES"/>
        <permission name="android.permission.READ_INSTALL_SESSIONS"/>
        <permission name="android.permission.RECEIVE_BOOT_COMPLETED"/>
        <permission name="android.permission.REQUEST_INSTALL_PACKAGES"/>
        <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
        <permission name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    </privapp-permissions>
</permissions>
XML
chmod 644 "$SB/system/etc/permissions/privapp-permissions-huawei.xml"
chown 0:0 "$SB/system/etc/permissions/privapp-permissions-huawei.xml"
setfattr -n security.selinux -v "u:object_r:system_file:s0" "$SB/system/etc/permissions/privapp-permissions-huawei.xml"

echo ""
echo "=== 4. 重建镜像 ==="
rm -f system_new3.img
time mkfs.erofs -z lz4hc -T 0 -d 2 system_new3.img "$SB" 2>&1 | tail -3
SZ=$(stat -c %s system_new3.img)
TARGET=3094769664
echo "镜像: $SZ  分区: $TARGET  余量: $((TARGET-SZ))"
if [ "$SZ" -gt "$TARGET" ]; then echo "!! 超出分区大小"; exit 1; fi
truncate -s $TARGET system_new3.img
sha256sum system_new3.img
md5sum system_new3.img

echo ""
echo "=== 5. 挂载验证 ==="
mkdir -p /mnt/sysnew3; umount /mnt/sysnew3 2>/dev/null || true
mount -o loop,ro system_new3.img /mnt/sysnew3
ls -la /mnt/sysnew3/system/priv-app/HuaweiAppGallery/ 2>/dev/null
ls -la /mnt/sysnew3/system/etc/permissions/privapp-permissions-huawei.xml 2>/dev/null
ls -la /mnt/sysnew3/system/priv-app/BPackageInstaller/BPackageInstaller.apk 2>/dev/null
echo "文件数: $(find /mnt/sysnew3 | wc -l)"
umount /mnt/sysnew3
echo BUILD_SYSTEM_V3_DONE
