#!/bin/bash
# 刷 v2 后验证：root 守护进程 + 静默安装器
set -uo pipefail
A="/usr/bin/adb"
echo "=== 0. 等设备起来（最多 90 秒）==="
for i in $(seq 1 18); do
  if $A devices -l 2>/dev/null | grep -q " device "; then echo "在线 ($((i*5))s)"; break; fi
  sleep 5
done
$A devices -l | head -3

echo ""
echo "=== 1. 系统状态 ==="
$A shell "getprop sys.boot_completed; getprop ro.build.version.incremental" </dev/null 2>&1 | head -3

echo ""
echo "=== 2. root 守护进程 ==="
$A shell "ls -la /data/local/tmp/s8root.log /data/local/tmp/s8root.pid 2>/dev/null" </dev/null 2>&1
$A shell "cat /data/local/tmp/s8root.log 2>/dev/null | head -10" </dev/null 2>&1
$A shell "cat /metadata/s8root_rc_parsed /metadata/s8root_boot_done 2>/dev/null" </dev/null 2>&1

echo ""
echo "=== 3. root 命令通道测试 ==="
$A shell "echo 'id; getenforce; cat /proc/self/attr/current' > /data/local/tmp/s8cmd.sh" </dev/null 2>&1
sleep 4
$A shell "cat /data/local/tmp/s8cmd.out 2>/dev/null" </dev/null 2>&1

echo ""
echo "=== 4. 静默安装器已安装？ ==="
$A shell "pm list packages | grep -i s8.silent" </dev/null 2>&1
$A shell "dumpsys package com.s8.silentinstaller 2>/dev/null | grep -E 'versionName|granted=true' | head -5" </dev/null 2>&1

echo ""
echo "=== 5. 测静默安装（用 B站 APK 放 install 目录，广播触发）==="
$A shell "mkdir -p /sdcard/Download/install" </dev/null 2>&1
$A push /root/s8/apks/hwyysc.apk /sdcard/Download/install/hwyysc_test.apk >/dev/null 2>&1
$A shell "am broadcast -a com.s8.INSTALL -p com.s8.silentinstaller" </dev/null 2>&1 | head -3
sleep 20
echo "--- 安装结果 ---"
$A shell "pm list packages | grep -c huawei.appmarket" </dev/null 2>&1
$A shell "pm list packages | grep -i install" </dev/null 2>&1 | head -5
$A logcat -d 2>/dev/null | grep -aE "S8Installer|PackageInstaller.*install|INSTALL_FAILED" | tail -10

echo ""
echo "=== 6. 当前禁用列表 ==="
$A shell "pm list packages -d" </dev/null 2>&1 | sed 's/package://' | head -12
echo VERIFY_DONE
