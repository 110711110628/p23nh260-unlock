#!/bin/bash
# 刷 boot_a = wrap9b（TWRP dd）
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/img/boot_s8_wrap9b.img
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"
echo "=== 镜像信息 ==="
ls -la $IMG
md5sum $IMG
echo ""
echo "=== 备份当前 boot_a 到 /sdcard ==="
$A shell "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a_before_wrap9b.img bs=1M count=64 2>/dev/null; ls -la /sdcard/boot_a_before_wrap9b.img"
echo ""
echo "=== 推送 + 刷入 boot_a ==="
$A push $IMG /tmp/boot_wrap9b.img
$A shell "dd if=/tmp/boot_wrap9b.img of=/dev/block/by-name/boot_a bs=1M 2>&1 | tail -1"
echo ""
echo "=== 回读校验 ==="
$A shell "dd if=/dev/block/by-name/boot_a of=/tmp/ba_chk.img bs=1M count=64 2>/dev/null; md5sum /tmp/ba_chk.img"
echo "期望: $(md5sum $IMG | awk '{print $1}')"
echo ""
echo "=== sync + reboot ==="
$A shell "sync; echo SYNCED"
$A reboot
echo REBOOTED
