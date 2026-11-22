#!/bin/bash
# 构建 product_v8：v7 + 静默安装器（product priv-app）
set -e
cd /root/s8
echo "=== 1. 挂载 v7 产品镜像 ==="
mkdir -p /mnt/pv7new; umount /mnt/pv7new 2>/dev/null || true
mount -o loop,ro product_v7.img /mnt/pv7new
echo "已挂载"
du -sh /mnt/pv7new

echo ""
echo "=== 2. 复制到可写目录 ==="
rm -rf prod_build_v8 && mkdir -p prod_build_v8
cp -a /mnt/pv7new/. prod_build_v8/
echo "复制完成: $(du -sh prod_build_v8 | cut -f1)"

echo ""
echo "=== 3. 放入静默安装器（priv-app）==="
mkdir -p prod_build_v8/priv-app/S8Installer
cp /root/s8/silent/build2/S8Installer.apk prod_build_v8/priv-app/S8Installer/S8Installer.apk
chmod 644 prod_build_v8/priv-app/S8Installer/S8Installer.apk
chown 0:0 prod_build_v8/priv-app/S8Installer/S8Installer.apk
setfattr -n security.selinux -v "u:object_r:system_file:s0" prod_build_v8/priv-app/S8Installer/S8Installer.apk
setfattr -n security.selinux -v "u:object_r:system_file:s0" prod_build_v8/priv-app/S8Installer 2>/dev/null || true

echo ""
echo "=== 4. 特权权限白名单（product/etc/permissions）==="
mkdir -p prod_build_v8/etc/permissions
cat > prod_build_v8/etc/permissions/privapp-permissions-s8installer.xml <<'XML'
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
chmod 644 prod_build_v8/etc/permissions/privapp-permissions-s8installer.xml
chown 0:0 prod_build_v8/etc/permissions/privapp-permissions-s8installer.xml
setfattr -n security.selinux -v "u:object_r:system_file:s0" prod_build_v8/etc/permissions/privapp-permissions-s8installer.xml

echo ""
echo "=== 5. 校验原有 rc 还在 ==="
cat prod_build_v8/etc/init/s8daemon.rc 2>/dev/null | head -8

echo ""
echo "=== 6. 重建 erofs ==="
rm -f product_v8.img
mkfs.erofs -z lz4hc -T 0 -d 2 product_v8.img prod_build_v8 2>&1 | tail -2
SZ=$(stat -c %s product_v8.img)
[ "$SZ" -le 157220864 ] || { echo "!! 超限 $SZ"; exit 1; }
truncate -s 157220864 product_v8.img
echo "镜像: $(stat -c %s product_v8.img)"
sha256sum product_v8.img
md5sum product_v8.img

echo ""
echo "=== 7. 挂载验证 ==="
mkdir -p /mnt/pv8; umount /mnt/pv8 2>/dev/null || true
mount -o loop,ro product_v8.img /mnt/pv8
ls -la /mnt/pv8/priv-app/S8Installer/ /mnt/pv8/etc/permissions/privapp-permissions-s8installer.xml 2>/dev/null
cat /mnt/pv8/etc/init/s8daemon.rc 2>/dev/null | head -6
umount /mnt/pv8
echo BUILD_PRODUCT_V8_DONE
