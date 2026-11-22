#!/bin/bash
# 刷 vendor_boot_a = TWRP(v3: S8原生161模块 + S8原生dtb)
# 同一会话：读头核对 → 写100MB → 回读100MB → reset
set -uo pipefail
DIR=/root/s8
cd "$DIR" || exit 1
SPD=/usr/local/bin/spd_dump
EXEC=0x65012f48
IMG="$DIR/img/twrp_s8native_full.img"
STOCK="$DIR/verify/vendor_boot_a_stock.img"
V="$DIR/verify"
mkdir -p "$V"

echo "########## 0. 前置检查 ##########"
fail=0
for f in "$IMG" "$STOCK"; do
  if [ ! -f "$f" ]; then echo "  !! 缺少 $f"; fail=1; continue; fi
  sz=$(stat -c %s "$f")
  if [ "$sz" != "104857600" ]; then echo "  !! $f 大小 $sz != 104857600"; fail=1; else echo "  OK $f ($sz)"; fi
done
[ "$fail" = "0" ] || { echo "前置检查失败，中止"; exit 1; }

SRC=$(sha256sum "$IMG" | awk '{print $1}')
STOCK_SHA=$(sha256sum "$STOCK" | awk '{print $1}')
echo "  待刷 SHA256   : $SRC"
echo "  回滚源 SHA256 : $STOCK_SHA"
[ "$SRC" = "97e48b4eff5e1c1192d08f0f798030ed702de4808aef55a85254246f28d1cf37" ] \
  || { echo "  !! 待刷镜像哈希与预期不符，中止"; exit 1; }
[ "$STOCK_SHA" = "00dddac1fe5655b41a73b53132593f22dd97cf6fec1b126659f02a8b18d9ca93" ] \
  || { echo "  !! 回滚源哈希与预期不符，中止"; exit 1; }
echo "  两个哈希均与预期一致"

rm -f "$DIR/vb_precheck.bin" "$DIR/vendor_boot_a_after.img" "$V/vendor_boot_a_after.img"

echo "########## 1. 释放 cdc_acm 占用 ##########"
for d in /sys/bus/usb/drivers/cdc_acm/*/idVendor; do
  [ -e "$d" ] || continue
  v=$(cat "$d" 2>/dev/null) || continue
  if [ "$v" = "1782" ]; then
    b=$(echo "$d" | awk -F/ '{print $(NF-1)}')
    echo -n "$b" > /sys/bus/usb/drivers/cdc_acm/unbind 2>/dev/null && echo "  unbind $b"
  fi
done

echo "########## 2. 守候 BROM $(date +%H:%M:%S) ##########"
$SPD --wait 900 --verbose 0 \
  exec_addr $EXEC \
  fdl fdl/fdl1-dl.bin 0x65000800 \
  fdl fdl/fdl2-dl.bin 0xb4fffe00 \
  exec timeout 30000 \
  read_part vendor_boot_a 0 0x1000 vb_precheck.bin \
  w vendor_boot_a "$IMG" \
  read_part vendor_boot_a 0 0x6400000 vendor_boot_a_after.img \
  reset
RC=$?
echo "########## spd exit=$RC $(date +%H:%M:%S) ##########"

[ -f "$DIR/vendor_boot_a_after.img" ] && mv -f "$DIR/vendor_boot_a_after.img" "$V/"

echo "########## 3. 写前分区头核对 ##########"
if [ -f "$DIR/vb_precheck.bin" ]; then
  python3 - "$DIR/vb_precheck.bin" "$STOCK" <<'PY'
import sys
a=open(sys.argv[1],"rb").read()
b=open(sys.argv[2],"rb").read()[:len(a)]
vrs=int.from_bytes(a[24:28],"little")
print(f"  读到 {len(a)} 字节  magic={a[:8]}  vendor_ramdisk={vrs}")
print(f"  与备份头逐字节一致={a==b}  （刷之前分区应仍是原厂）")
PY
else
  echo "  !! 未取到分区头（可能未进 BROM）"
fi

echo "########## 4. 回读校验 ##########"
if [ -f "$V/vendor_boot_a_after.img" ]; then
  ASZ=$(stat -c %s "$V/vendor_boot_a_after.img")
  BACK=$(sha256sum "$V/vendor_boot_a_after.img" | awk '{print $1}')
  echo "  回读大小: $ASZ (应为 104857600)"
  echo "  SRC  : $SRC"
  echo "  BACK : $BACK"
  if [ "$SRC" = "$BACK" ] && [ "$ASZ" = "104857600" ]; then
    echo "  VERDICT: verified-match"
  else
    echo "  VERDICT: MISMATCH —— 需要回滚，重进 BROM 跑 rollback_vb.sh"
  fi
  python3 - "$V/vendor_boot_a_after.img" <<'PY'
import sys, struct
d=open(sys.argv[1],"rb").read()
vrs,=struct.unpack("<I", d[24:28]); dts,=struct.unpack("<I", d[2100:2104])
print(f"  magic={d[:8]} vendor_ramdisk={vrs} dtb={dts}")
print(f"  cmdline={d[28:28+100].rstrip(bytes([0])).decode('utf-8','replace')}")
PY
else
  echo "  !! 没有回读文件，写入可能未完成"
fi

echo "########## DONE ##########"
