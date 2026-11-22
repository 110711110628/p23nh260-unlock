#!/bin/bash
set -uo pipefail
A="/usr/bin/adb"
APK=/root/s8/silent/build2/S8Installer.apk

echo "=== 1. 安装更新（带桌面图标）==="
$A push $APK /data/local/tmp/si_v12.apk >/dev/null 2>&1
SIZE=$(stat -c %s $APK)
SID=$($A shell "pm install-create -r -S $SIZE" </dev/null 2>&1 | grep -oE '[0-9]+' | head -1)
$A shell "pm install-write -S $SIZE $SID base /data/local/tmp/si_v12.apk" </dev/null 2>&1 | head -1
$A shell "pm install-commit $SID" </dev/null 2>&1 | head -1

echo ""
echo "=== 2. 桌面图标启动测试（扫描 Download/install）==="
$A shell "pm uninstall com.topjohnwu.magisk" </dev/null 2>&1 | head -1
$A shell "ls -la /sdcard/Download/install/" </dev/null 2>&1
$A logcat -c 2>/dev/null
$A shell "monkey -p com.s8.silentinstaller -c android.intent.category.LAUNCHER 1" </dev/null 2>&1 | tail -2
sleep 25
echo ""
echo "=== 3. 结果 ==="
$A logcat -d 2>/dev/null | grep -aE "S8Installer" | tail -12
$A shell "pm list packages | grep topjohnwu" </dev/null 2>&1
echo ""
echo "=== 4. 桌面图标是否出现（launcher 查询）==="
$A shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.s8.silentinstaller" </dev/null 2>&1 | tail -2
