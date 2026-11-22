#!/bin/bash
# 安装王者荣耀（session 方式，1.6GB）
set -uo pipefail
A="/usr/bin/adb"
APK=/root/s8/apks/sgame.apk
OUT=/root/s8/sgame_install.log
{
echo "=== 开始 $(date) ==="
SIZE=$(stat -c %s "$APK")
echo "大小: $SIZE"
echo "--- 设备空间 ---"
$A shell "df -h /data | tail -1" </dev/null 2>&1
echo "--- 推送 ---"
$A shell "rm -f /data/local/tmp/sgame.apk" </dev/null 2>&1
$A push "$APK" /data/local/tmp/sgame.apk
$A shell "ls -la /data/local/tmp/sgame.apk" </dev/null 2>&1
echo "--- session ---"
SID=$($A shell "pm install-create -r -d -S $SIZE" </dev/null 2>&1 | grep -oE '[0-9]+' | head -1)
echo "session=$SID"
echo "--- 写入（1.6GB，约 60-90 秒）---"
$A shell "pm install-write -S $SIZE $SID base /data/local/tmp/sgame.apk" </dev/null 2>&1 | head -2
echo "--- 提交 ---"
$A shell "pm install-commit $SID" </dev/null 2>&1 | head -3
echo "--- 验证 ---"
$A shell "pm list packages | grep -i tmgp" </dev/null 2>&1
$A shell "dumpsys package com.tencent.tmgp.sgame 2>/dev/null | grep -E 'versionName' | head -1" </dev/null 2>&1
$A shell "rm -f /data/local/tmp/sgame.apk" </dev/null 2>&1
echo "=== 完成 $(date) ==="
} > $OUT 2>&1
