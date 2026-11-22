#!/bin/bash
# 备份原厂 vendor_boot_a → 刷 TWRP v1.2.0 → 回读校验
set -u
DIR=/root/s8
cd "$DIR" || exit 1
SPD=/usr/local/bin/spd_dump
EXEC=0x65012f48
SZ=0x6400000                      # 100MB
V=$DIR/verify
mkdir -p "$V"
STOCK=$V/vendor_boot_a_stock.img
AFTER=$V/vendor_boot_a_after_twrp.img
rm -f "$STOCK" "$AFTER" vendor_boot_a_stock.img vendor_boot_a_after_twrp.img

echo "== 源镜像 =="
ls -l twrp/twrp_v120.img
TWRP_SHA=$(sha256sum twrp/twrp_v120.img | awk '{print $1}')
echo "TWRP_SHA256: $TWRP_SHA"

for d in /sys/bus/usb/drivers/cdc_acm/*/idVendor; do
  [ -e "$d" ] || continue
  v=$(cat "$d" 2>/dev/null)
  [ "$v" = "1782" ] && { b=$(echo "$d" | awk -F/ '{print $(NF-1)}'); echo -n "$b" > /sys/bus/usb/drivers/cdc_acm/unbind 2>/dev/null; }
done

echo "== 同一会话：读原厂 → 写 TWRP → 回读 $(date +%H:%M:%S) =="
$SPD --wait 900 --verbose 0 \
  exec_addr $EXEC \
  fdl fdl/fdl1-dl.bin 0x65000800 \
  fdl fdl/fdl2-dl.bin 0xb4fffe00 \
  exec timeout 30000 \
  read_part vendor_boot_a 0 $SZ vendor_boot_a_stock.img \
  w vendor_boot_a "$DIR/twrp/twrp_v120.img" \
  read_part vendor_boot_a 0 $SZ vendor_boot_a_after_twrp.img \
  reset
echo "== spd exit=$? $(date +%H:%M:%S) =="

for f in vendor_boot_a_stock.img vendor_boot_a_after_twrp.img; do
  [ -f "$DIR/$f" ] && mv -f "$DIR/$f" "$V/$f"
done

echo "== 原厂备份 =="
if [ -f "$STOCK" ]; then
  ls -l "$STOCK"
  python3 - "$STOCK" <<'PY'
import sys,hashlib,struct
d=open(sys.argv[1],'rb').read()
print("size:",len(d),"magic:",d[:8],"sha256:",hashlib.sha256(d).hexdigest())
print("ver:",struct.unpack('<I',d[8:12])[0],"page:",struct.unpack('<I',d[12:16])[0],
      "vramdisk:",struct.unpack('<I',d[24:28])[0])
print("head_nonzero:",sum(1 for b in d[:4096] if b))
PY
else
  echo "!! 原厂备份未取到，后续不应刷入"
fi

echo "== 回读校验 =="
BACK=$(sha256sum "$AFTER" 2>/dev/null | awk '{print $1}')
echo "TWRP_SHA256: $TWRP_SHA"
echo "BACK_SHA256: $BACK"
[ "$TWRP_SHA" = "$BACK" ] && echo "VERDICT: verified-match" || echo "VERDICT: MISMATCH"
