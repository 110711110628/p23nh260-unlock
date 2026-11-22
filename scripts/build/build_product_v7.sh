#!/bin/bash
# v7: init 直接 setprop usb.config=adb（绕开 UsbDeviceManager）
set -e
cd /root/s8
rm -rf prod_build && mkdir -p prod_build
cp -a /mnt/prod/. prod_build/
mkdir -p prod_build/etc/init

cat > prod_build/etc/init/s8daemon.rc <<'RCEOF'
# v7: init 直接设 usb 配置 + 标记
on boot
    write /metadata/rc_test_parsed 1
    setprop persist.sys.usb.config adb
    setprop sys.usb.config adb
    write /metadata/m_setprop 1
    exec_background - root root -- /system/bin/sh -c "echo exec_ok > /data/local/tmp/exec_ok"

on property:sys.usb.config=adb
    write /metadata/m_saw_adb 1
RCEOF
chmod 644 prod_build/etc/init/s8daemon.rc

# 保留 s8daemon.sh（虽然没跑，留着无妨）
cp /root/s8/s8daemon.sh prod_build/etc/s8daemon.sh 2>/dev/null || true
chmod 755 prod_build/etc/s8daemon.sh 2>/dev/null || true

setfattr -n security.selinux -v "u:object_r:system_file:s0" prod_build/etc/init/s8daemon.rc
[ -f prod_build/etc/s8daemon.sh ] && setfattr -n security.selinux -v "u:object_r:system_file:s0" prod_build/etc/s8daemon.sh

rm -f product_v7.img
mkfs.erofs -z lz4hc -T 0 -d 2 product_v7.img prod_build 2>&1 | tail -2
SZ=$(stat -c %s product_v7.img)
[ "$SZ" -le 157220864 ] || { echo 超限; exit 1; }
truncate -s 157220864 product_v7.img
mkdir -p /mnt/pv7; umount /mnt/pv7 2>/dev/null || true
mount -o loop,ro product_v7.img /mnt/pv7
echo "--- rc ---"; cat /mnt/pv7/etc/init/s8daemon.rc
umount /mnt/pv7
sha256sum product_v7.img
echo BUILD_V7_DONE
