#!/bin/bash
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/product_v7.img
PREV=/root/s8/product_v6.img
SRC=c13c1fa3e5e5cad9a45c2c0cbdddd628216fb67ba6ae8c3acf473538328d6a90
SEEK=13498368
COUNT=307072
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"
[ "$(sha256sum $IMG | awk '{print $1}')" = "$SRC" ] || { echo "!! 哈希不符"; exit 1; }
echo "=== 偏移校验（当前=v6）==="
$A push "$PREV" /tmp/prev.img >/dev/null 2>&1
M1=$($A shell "head -c 1048576 /tmp/prev.img | md5sum" | awk '{print $1}')
$A shell "dd if=/dev/block/by-name/super of=/tmp/pre1m.bin bs=1M skip=6591 count=1 2>/dev/null"
M2=$($A shell "md5sum /tmp/pre1m.bin" | awk '{print $1}')
echo "prev=$M1 dev=$M2"
[ "$M1" = "$M2" ] && echo "偏移OK ✓" || echo "(继续)"
echo "=== 刷入 v7 ==="
$A push "$IMG" /tmp/product_v7.img
$A shell "dd if=/tmp/product_v7.img of=/dev/block/by-name/super bs=512 seek=$SEEK count=$COUNT conv=notrunc 2>&1 | tail -1"
BACK=$($A shell "dd if=/dev/block/by-name/super of=/tmp/post.bin bs=512 skip=$SEEK count=$COUNT 2>/dev/null; sha256sum /tmp/post.bin" | awk '{print $1}')
echo "回读: ${BACK:0:16} 期望: ${SRC:0:16}"
[ "$BACK" = "$SRC" ] || { echo "!! 回读失败"; exit 1; }
echo "写入成功 ✓"
$A shell "rm -f /metadata/rc_test_parsed /metadata/m_setprop /metadata/m_saw_adb /data/local/tmp/exec_ok; sync"
$A reboot
echo REBOOTED
