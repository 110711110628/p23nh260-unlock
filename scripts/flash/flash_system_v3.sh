#!/bin/bash
# 刷 system v3（含特权华为应用市场）
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/system_new3.img
SIZE=3094769664
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "TWRP OK"
[ -f "$IMG" ] || { echo "镜像不存在"; exit 1; }
[ "$(stat -c %s $IMG)" = "$SIZE" ] || { echo "!! 大小不符 $(stat -c %s $IMG)"; exit 1; }
echo "镜像: $SIZE bytes  md5=$(md5sum $IMG | awk '{print $1}')"

echo ""
echo "=== 1. 推送（3.09GB）==="
$A shell "rm -f /sdcard/system_v3.img" </dev/null
$A push $IMG /sdcard/system_v3.img >/dev/null || { echo "推送失败"; exit 1; }
DEVM=$($A shell "md5sum /sdcard/system_v3.img" </dev/null | awk '{print $1}')
SRCM=$(md5sum $IMG | awk '{print $1}')
echo "设备: $DEVM"
echo "服务器: $SRCM"
[ "$DEVM" = "$SRCM" ] || { echo "!! 校验失败"; exit 1; }
echo "推送校验通过 ✓"

echo ""
echo "=== 2. 写入 11 个 extent ==="
dd_extent() {
  local target=$1 count=$2 skip=$3
  echo "  -> target=$target count=$count skip=$skip"
  $A shell "dd if=/sdcard/system_v3.img of=/dev/block/by-name/super bs=512 seek=$target skip=$skip count=$count conv=notrunc 2>&1 | tail -1" </dev/null
}
dd_extent 2048 5710416 0
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
echo "=== 3. 逐段回读校验 ==="
FAIL=0
check_extent() {
  local target=$1 count=$2 skip=$3
  local dev_md5 img_md5
  dev_md5=$($A shell "dd if=/dev/block/by-name/super bs=512 skip=$target count=$count 2>/dev/null | md5sum" </dev/null | awk '{print $1}')
  img_md5=$(dd if=$IMG bs=512 skip=$skip count=$count 2>/dev/null | md5sum | awk '{print $1}')
  if [ "$dev_md5" = "$img_md5" ]; then echo "  ✓ target=$target"; else echo "  ✗ target=$target"; FAIL=1; fi
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
if [ "$FAIL" = "1" ]; then echo "!! 校验失败，不重启"; exit 1; fi
echo "=== 4. sync + reboot ==="
$A shell "rm -f /sdcard/system_v3.img; sync; echo SYNCED" </dev/null
$A reboot
echo REBOOTED
