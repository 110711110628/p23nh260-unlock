#!/bin/bash
set -uo pipefail
A="/usr/bin/adb"
APK=/root/s8/silent/build2/S8Installer.apk

echo "=== 1. 安装更新 ==="
$A push $APK /data/local/tmp/si_v11.apk >/dev/null 2>&1
SIZE=$(stat -c %s $APK)
SID=$($A shell "pm install-create -r -S $SIZE" </dev/null 2>&1 | grep -oE '[0-9]+' | head -1)
$A shell "pm install-write -S $SIZE $SID base /data/local/tmp/si_v11.apk" </dev/null 2>&1 | head -1
$A shell "pm install-commit $SID" </dev/null 2>&1 | head -1

echo ""
echo "=== 2. 测试目标状态 ==="
$A shell "pm list packages | grep -c topjohnwu" </dev/null 2>&1
$A shell "ls -la /sdcard/Android/data/com.s8.silentinstaller/files/install/" </dev/null 2>&1

echo ""
echo "=== 3. 启动安装器（抓全日志）==="
$A logcat -c 2>/dev/null
$A shell "am start -a android.intent.action.VIEW -d file:///sdcard/Android/data/com.s8.silentinstaller/files/install/magisk_test.apk -t application/vnd.android.package-archive -n com.s8.silentinstaller/.InstallerActivity" </dev/null 2>&1 | head -3
sleep 20

echo ""
echo "=== 4. S8Installer 日志 ==="
$A logcat -d 2>/dev/null | grep -aE "S8Installer" | tail -20
echo ""
echo "=== 5. 安装结果 ==="
$A shell "pm list packages | grep topjohnwu" </dev/null 2>&1
echo ""
echo "=== 6. 会话相关 ==="
$A logcat -d 2>/dev/null | grep -aE "PackageInstallerSession|InstallSession|installPackageLI|INSTALL_FAILED|INSTALL_SUCCEEDED" | tail -12
