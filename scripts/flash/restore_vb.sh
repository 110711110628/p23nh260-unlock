#!/bin/bash
# 恢复 vendor_boot_a 到已知可用的 TWRP 镜像（twrp_s8native_full.img）
set -uo pipefail
DIR=/root/s8
cd "$DIR" || exit 1
SPD=/usr/local/bin/spd_dump
EXEC=0x65012f48
IMG="$DIR/img/twrp_s8native_full.img"
EXPECT=97e48b4eff5e1c1192d08f0f798030ed702de4808aef55a85254246f28d1cf37
V="$DIR/verify"

[ -f "$IMG" ] || { echo "!! 缺少 $IMG"; exit 1; }
SZ=$(stat -c %s "$IMG")
GOT=$(sha256sum "$IMG" | awk '{print $1}')
echo "镜像 $IMG"
echo "  size=$SZ  sha256=$GOT"
[ "$SZ" = "104857600" ] || { echo "!! 大小不对"; exit 1; }
[ "$GOT" = "$EXPECT" ] || { echo "!! 哈希与预期不符，中止"; exit 1; }

rm -f "$DIR/vb_restore_after.img" "$V/vb_restore_after.img"

echo "===== 守候 BROM $(date +%H:%M:%S) ====="
$SPD --wait 900 --verbose 0 \
  exec_addr $EXEC \
  fdl fdl/fdl1-dl.bin 0x65000800 \
  fdl fdl/fdl2-dl.bin 0xb4fffe00 \
  exec timeout 30000 \
  w vendor_boot_a "$IMG" \
  read_part vendor_boot_a 0 0x6400000 vb_restore_after.img \
  reset
echo "===== spd exit=$? $(date +%H:%M:%S) ====="

[ -f "$DIR/vb_restore_after.img" ] && mv -f "$DIR/vb_restore_after.img" "$V/"
BACK=$(sha256sum "$V/vb_restore_after.img" 2>/dev/null | awk '{print $1}')
echo "EXPECT: $EXPECT"
echo "BACK  : $BACK"
[ "$EXPECT" = "$BACK" ] && echo "VERDICT: restored-ok" || echo "VERDICT: MISMATCH"
