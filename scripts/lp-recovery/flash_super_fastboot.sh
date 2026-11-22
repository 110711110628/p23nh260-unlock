#!/bin/bash
# 等待 fastboot 出现，然后刷 super_fixed.img
set -u
LOG=/root/g12diag/flash_super.log
rm -f $LOG
echo "[$(date +%T)] 等待 fastboot 设备..." >> $LOG

for i in $(seq 1 120); do
  dev=$(timeout 5 fastboot devices 2>/dev/null | head -1)
  if [ -n "$dev" ]; then
    echo "[$(date +%T)] 发现设备: $dev" >> $LOG
    break
  fi
  sleep 5
done

if [ -z "${dev:-}" ]; then
  echo "[$(date +%T)] 超时未发现 fastboot 设备" >> $LOG
  exit 1
fi

echo "[$(date +%T)] 开始刷 super（4.98GB，预计 2-5 分钟）..." >> $LOG
timeout 900 fastboot flash super /root/g12diag/super_fixed.img >> $LOG 2>&1
rc=$?
echo "[$(date +%T)] fastboot flash 返回码: $rc" >> $LOG
if [ $rc -eq 0 ]; then
  echo "[$(date +%T)] 刷写成功，发送 reboot" >> $LOG
  timeout 20 fastboot reboot >> $LOG 2>&1
fi
tail -5 $LOG
