#!/bin/bash
# 刷入改造后的 system 镜像（11 个 extent）
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/system_new.img
SIZE=3094769664
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"
echo "镜像大小: $(stat -c %s $IMG) (期望 $SIZE)"
[ "$(stat -c %s $IMG)" = "$SIZE" ] || { echo "!! 大小不符"; exit 1; }

echo ""
echo "=== 0. 空间检查 ==="
$A shell "df -h /data 2>/dev/null | tail -1; ls -la /sdcard/system_new.img 2>/dev/null || echo 未存在"

echo ""
echo "=== 1. 推送镜像到 /sdcard（3.09GB，约 1-2 分钟）==="
$A push $IMG /sdcard/system_new.img || { echo "!! 推送失败"; exit 1; }
$A shell "ls -la /sdcard/system_new.img; md5sum /sdcard/system_new.img" 2>&1

echo ""
echo "=== 2. 按 extent 写入 super ==="
EXTENTS="
2048 5710416 0
5712472 1448 5710416
6391328 480 5711864
13498216 152 5712344
13808216 1448 5712496
14279544 1160 5713944
14300640 67144 5715104
6368712 22616 5782248
13805440 2776 5804864
14367784 144 5807640
14784456 236688 5807784
"
echo "$EXTENTS" | while read -r target count skip; do
  [ -z "$target" ] && continue
  echo "  extent target=$target count=$count skip=$skip"
  $A shell "dd if=/sdcard/system_new.img of=/dev/block/by-name/super bs=512 seek=$target skip=$skip count=$count conv=notrunc 2>&1 | tail -1"
done

echo ""
echo "=== 3. 回读校验（首 1MB）==="
$A shell "dd if=/dev/block/by-name/super of=/tmp/sys_chk.bin bs=1M skip=1 count=1 2>/dev/null; md5sum /tmp/sys_chk.bin"
head -c 1048576 $IMG | md5sum
echo "（两个 md5 应一致）"

echo ""
echo "=== 4. sync + reboot ==="
$A shell "sync; echo SYNCED"
$A reboot
echo REBOOTED
