#!/bin/bash
# 补写 system 剩余 10 个 extent（用显式 dd，避免 stdin 被 adb 吃掉）
set -uo pipefail
A="/usr/bin/adb"
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"

dd_extent() {
  local target=$1 count=$2 skip=$3
  echo "  -> target=$target count=$count skip=$skip"
  $A shell "dd if=/sdcard/system_new.img of=/dev/block/by-name/super bs=512 seek=$target skip=$skip count=$count conv=notrunc 2>&1 | tail -1" </dev/null
}

echo "=== 补写 10 个 extent ==="
dd_extent 5712472 1448 5710416
dd_extent 6391328 480 5711864
dd_extent 13498216 152 5712344
dd_extent 13808216 1448 5712496
dd_extent 14279544 1160 5713944
dd_extent 14300640 67144 5715104
dd_extent 6368712 22616 5782248
dd_extent 13805440 2776 5804864
dd_extent 14367784 144 5807640
dd_extent 14784456 236688 5807784

echo ""
echo "=== 精确校验：每个 extent 回读 md5 对比镜像切片 ==="
check_extent() {
  local target=$1 count=$2 skip=$3
  local dev_md5 img_md5
  dev_md5=$($A shell "dd if=/dev/block/by-name/super bs=512 skip=$target count=$count 2>/dev/null | md5sum" </dev/null | awk '{print $1}')
  img_md5=$(dd if=/root/s8/system_new.img bs=512 skip=$skip count=$count 2>/dev/null | md5sum | awk '{print $1}')
  if [ "$dev_md5" = "$img_md5" ]; then
    echo "  ✓ target=$target  $dev_md5"
  else
    echo "  ✗ target=$target  dev=$dev_md5 img=$img_md5"
  fi
}
check_extent 2048 5710416 0
check_extent 5712472 1448 5710416
check_extent 6391328 480 5711864
check_extent 13498216 152 5712344
check_extent 13808216 1448 5712496
check_extent 14279544 1160 5713944
check_extent 14300640 67144 5715104
check_extent 6368712 22616 5782248
check_extent 13805440 2776 5804864
check_extent 14367784 144 5807640
check_extent 14784456 236688 5807784

echo ""
echo "=== sync ==="
$A shell "sync; echo SYNCED" </dev/null
echo DONE
