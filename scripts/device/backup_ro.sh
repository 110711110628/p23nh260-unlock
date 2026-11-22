#!/bin/bash
# 只读备份：vendor_boot_a(100MB) + dtbo_a(8MB) + init_boot_a(8MB)
# 全程只有 read_part，没有任何 w/erase 指令
set -u
DIR=/root/s8
cd "$DIR" || exit 1
SPD=/usr/local/bin/spd_dump
EXEC=0x65012f48
V=$DIR/verify
mkdir -p "$V"

for f in vendor_boot_a_stock.img dtbo_a_stock.img init_boot_a_stock.img; do
  rm -f "$DIR/$f" "$V/$f"
done

if lsusb | grep -q "1782:4d00"; then
  echo "BROM 已在位，立即开始 $(date +%H:%M:%S)"
else
  echo "等待 BROM... $(date +%H:%M:%S)"
fi

$SPD --wait 900 --verbose 0 \
  exec_addr $EXEC \
  fdl fdl/fdl1-dl.bin 0x65000800 \
  fdl fdl/fdl2-dl.bin 0xb4fffe00 \
  exec timeout 30000 \
  read_part vendor_boot_a 0 0x6400000 vendor_boot_a_stock.img \
  read_part dtbo_a 0 0x800000 dtbo_a_stock.img \
  read_part init_boot_a 0 0x800000 init_boot_a_stock.img \
  reset
echo "== spd exit=$? $(date +%H:%M:%S) =="

for f in vendor_boot_a_stock.img dtbo_a_stock.img init_boot_a_stock.img; do
  [ -f "$DIR/$f" ] && mv -f "$DIR/$f" "$V/$f"
done

echo "=== 文件"
ls -l "$V"/*_stock.img 2>/dev/null
echo "=== SHA256"
sha256sum "$V"/*_stock.img 2>/dev/null
echo "=== 非零字节"
for f in vendor_boot_a_stock.img dtbo_a_stock.img init_boot_a_stock.img; do
  [ -f "$V/$f" ] || { echo "  $f 缺失"; continue; }
  printf "  %-28s size=%-10s nonzero=%s\n" "$f" "$(stat -c %s "$V/$f")" "$(tr -d '\000' < "$V/$f" | wc -c)"
done
echo "=== DONE"
