#!/bin/bash
# 刷 boot_a = wrap10（先 permissive 再 exec）
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/img/boot_s8_wrap10.img
EXPECT=e25e6f1a54d80bd396afb077e73c3687   # md5
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"
REAL=$(md5sum $IMG | awk '{print $1}')
echo "镜像 md5: $REAL (期望 $EXPECT)"
[ "$REAL" = "$EXPECT" ] || { echo "!! md5 不符"; exit 1; }
echo "=== 备份当前 boot_a ==="
$A shell "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a_before_wrap10.img bs=1M count=64 2>/dev/null; ls -la /sdcard/boot_a_before_wrap10.img"
echo "=== 刷入 ==="
$A push $IMG /tmp/boot_wrap10.img
$A shell "dd if=/tmp/boot_wrap10.img of=/dev/block/by-name/boot_a bs=1M 2>&1 | tail -1"
echo "=== 回读校验 ==="
BACK=$($A shell "dd if=/dev/block/by-name/boot_a of=/tmp/ba10.img bs=1M count=64 2>/dev/null; md5sum /tmp/ba10.img" | awk '{print $1}')
echo "回读 md5: $BACK"
[ "$BACK" = "$EXPECT" ] && echo "写入成功 ✓" || { echo "!! 回读失败"; exit 1; }
echo "=== sync + reboot ==="
$A shell "sync"
$A reboot
echo REBOOTED
