#!/bin/bash
# 回滚 product 到原始镜像（TWRP 内 dd）
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/product_a.img
SEEK=13498368
COUNT=307072
SRC=$(sha256sum "$IMG" | awk '{print $1}')

if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "回滚源: $IMG"
echo "SHA256: $SRC"

echo "=== 1. 推送原镜像 ==="
$A push "$IMG" /tmp/product_a.img || exit 1

echo "=== 2. 写入 ==="
$A shell "dd if=/tmp/product_a.img of=/dev/block/by-name/super bs=512 seek=$SEEK count=$COUNT conv=notrunc 2>&1 | tail -2"

echo "=== 3. 回读校验 ==="
$A shell "dd if=/dev/block/by-name/super of=/tmp/pchk.bin bs=512 skip=$SEEK count=$COUNT 2>/dev/null; sha256sum /tmp/pchk.bin"
echo "期望: $SRC"

echo "=== 4. sync + reboot ==="
$A shell "sync"
$A reboot
echo ROLLBACK_REBOOTED
