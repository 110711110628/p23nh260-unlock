#!/bin/bash
set -uo pipefail
A="/usr/bin/adb"

echo "=== 1. 目标：卸载 Magisk（测试用）==="
$A shell "pm list packages | grep -c topjohnwu" </dev/null 2>&1

echo ""
echo "=== 2. 放 APK 到 /sdcard/Download/install ==="
$A shell "mkdir -p /sdcard/Download/install; rm -f /sdcard/Download/install/*.apk" </dev/null 2>&1
$A push /root/s8/magisk_dl/Magisk-v31.1.apk /sdcard/Download/install/magisk.apk >/dev/null 2>&1
$A shell "ls -la /sdcard/Download/install/" </dev/null 2>&1

echo ""
echo "=== 3. 启动安装器（file:// 指向 Download/install）==="
$A logcat -c 2>/dev/null
$A shell "am start -a android.intent.action.VIEW -d file:///sdcard/Download/install/magisk.apk -t application/vnd.android.package-archive -n com.s8.silentinstaller/.InstallerActivity" </dev/null 2>&1 | head -3
sleep 30

echo ""
echo "=== 4. S8Installer 日志 ==="
$A logcat -d 2>/dev/null | grep -aE "S8Installer" | tail -15

echo ""
echo "=== 5. 安装结果 ==="
$A shell "pm list packages | grep topjohnwu" </dev/null 2>&1

echo ""
echo "=== 6. 系统安装日志 ==="
$A logcat -d 2>/dev/null | grep -aE "PackageInstallerSession|INSTALL_FAILED|INSTALL_SUCCEEDED|installPackageLI|commit of session" | tail -12
