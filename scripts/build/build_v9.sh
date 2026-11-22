#!/bin/bash
# v9: 静默安装器加存储权限 + 重建 product
set -e
cd /root/s8/silent
echo "=== 1. 改 manifest 加存储权限 ==="
python3 - <<'PY'
p='/root/s8/silent/AndroidManifest.xml'
s=open(p).read()
add='''    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
'''
if 'MANAGE_EXTERNAL_STORAGE' not in s:
    s=s.replace('    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
                '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />\n'+add, 1)
    open(p,'w').write(s)
    print("已加存储权限")
else:
    print("已有存储权限")
PY
echo ""
echo "=== 2. 重新构建 APK ==="
bash build_apk2.sh 2>&1 | tail -8
echo ""
echo "=== 3. 重建 product（v9）==="
rm -rf /root/s8/prod_build_v9 && mkdir -p /root/s8/prod_build_v9
cp -a /mnt/pv7new/. /root/s8/prod_build_v9/ 2>/dev/null || true
mkdir -p /root/s8/prod_build_v9/priv-app/S8Installer
cp build2/S8Installer.apk /root/s8/prod_build_v9/priv-app/S8Installer/S8Installer.apk
chmod 644 /root/s8/prod_build_v9/priv-app/S8Installer/S8Installer.apk
chown 0:0 /root/s8/prod_build_v9/priv-app/S8Installer/S8Installer.apk
setfattr -n security.selinux -v "u:object_r:system_file:s0" /root/s8/prod_build_v9/priv-app/S8Installer/S8Installer.apk
mkdir -p /root/s8/prod_build_v9/etc/permissions
cat > /root/s8/prod_build_v9/etc/permissions/privapp-permissions-s8installer.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<permissions>
    <privapp-permissions package="com.s8.silentinstaller">
        <permission name="android.permission.INSTALL_PACKAGES"/>
        <permission name="android.permission.DELETE_PACKAGES"/>
        <permission name="android.permission.QUERY_ALL_PACKAGES"/>
        <permission name="android.permission.READ_INSTALL_SESSIONS"/>
        <permission name="android.permission.RECEIVE_BOOT_COMPLETED"/>
        <permission name="android.permission.REQUEST_INSTALL_PACKAGES"/>
        <permission name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
        <permission name="android.permission.READ_EXTERNAL_STORAGE"/>
        <permission name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    </privapp-permissions>
</permissions>
XML
chmod 644 /root/s8/prod_build_v9/etc/permissions/privapp-permissions-s8installer.xml
chown 0:0 /root/s8/prod_build_v9/etc/permissions/privapp-permissions-s8installer.xml
setfattr -n security.selinux -v "u:object_r:system_file:s0" /root/s8/prod_build_v9/etc/permissions/privapp-permissions-s8installer.xml
rm -f /root/s8/product_v9.img
mkfs.erofs -z lz4hc -T 0 -d 2 /root/s8/product_v9.img /root/s8/prod_build_v9 2>&1 | tail -2
truncate -s 157220864 /root/s8/product_v9.img
sha256sum /root/s8/product_v9.img
md5sum /root/s8/product_v9.img
echo BUILD_V9_DONE
