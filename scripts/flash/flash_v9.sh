#!/bin/bash
# 刷 product_v9（静默安装器+存储权限）
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/product_v9.img
SRC=71b5244f7eb1af457ba62d3658f7431cae55f59a49480e78ed661e5215cb2197
SEEK=13498368; COUNT=307072
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"
[ "$(sha256sum $IMG | awk '{print $1}')" = "$SRC" ] || { echo "!! 哈希不符"; exit 1; }
echo "=== 刷入 v9 ==="
$A push "$IMG" /tmp/product_v9.img >/dev/null 2>&1
$A shell "dd if=/tmp/product_v9.img of=/dev/block/by-name/super bs=512 seek=$SEEK count=$COUNT conv=notrunc 2>&1 | tail -1" </dev/null
BACK=$($A shell "dd if=/dev/block/by-name/super of=/tmp/post9.bin bs=512 skip=$SEEK count=$COUNT 2>/dev/null; sha256sum /tmp/post9.bin" </dev/null | awk '{print $1}')
echo "回读: ${BACK:0:16} 期望: ${SRC:0:16}"
[ "$BACK" = "$SRC" ] || { echo "!! 回读失败"; exit 1; }
echo "写入成功 ✓"
echo ""
echo "=== 顺带备份当前 boot_a（Magisk 试验用）==="
$A shell "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a_pre_magisk.img bs=1M count=64 2>/dev/null; ls -la /sdcard/boot_a_pre_magisk.img" </dev/null 2>&1
$A shell "sync; echo SYNCED" </dev/null
echo ""
echo "=== 重启 ==="
$A reboot
echo REBOOTED
