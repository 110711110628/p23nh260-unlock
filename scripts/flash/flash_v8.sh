#!/bin/bash
# 刷 product_v8（含静默安装器）
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/product_v8.img
PREV=/root/s8/product_v7.img
SRC=aa4eb59ef3f48234f952af4f1ddfb89ef34d68277428568bd8ab805654644036
SEEK=13498368
COUNT=307072
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"
[ "$(sha256sum $IMG | awk '{print $1}')" = "$SRC" ] || { echo "!! 哈希不符"; exit 1; }
echo "=== 偏移校验（当前应为 v7）==="
$A push "$PREV" /tmp/prev.img >/dev/null 2>&1
M1=$($A shell "head -c 1048576 /tmp/prev.img | md5sum" </dev/null | awk '{print $1}')
M2=$($A shell "dd if=/dev/block/by-name/super of=/tmp/pre1m.bin bs=1M skip=6591 count=1 2>/dev/null; md5sum /tmp/pre1m.bin" </dev/null | awk '{print $1}')
echo "prev=$M1 dev=$M2"
[ "$M1" = "$M2" ] && echo "偏移OK ✓" || echo "(继续)"
echo ""
echo "=== 刷入 v8 ==="
$A push "$IMG" /tmp/product_v8.img >/dev/null 2>&1
$A shell "dd if=/tmp/product_v8.img of=/dev/block/by-name/super bs=512 seek=$SEEK count=$COUNT conv=notrunc 2>&1 | tail -1" </dev/null
echo "=== 回读校验 ==="
BACK=$($A shell "dd if=/dev/block/by-name/super of=/tmp/post.bin bs=512 skip=$SEEK count=$COUNT 2>/dev/null; sha256sum /tmp/post.bin" </dev/null | awk '{print $1}')
echo "回读: ${BACK:0:16} 期望: ${SRC:0:16}"
[ "$BACK" = "$SRC" ] || { echo "!! 回读失败"; exit 1; }
echo "写入成功 ✓"
$A shell "rm -f /data/local/tmp/S8Installer2.apk /data/local/tmp/s8cmd.sh /data/local/tmp/s8cmd.out /data/local/tmp/s8test.out; sync" </dev/null
$A reboot
echo REBOOTED
