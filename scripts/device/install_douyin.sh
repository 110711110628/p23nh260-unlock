#!/bin/bash
# 安装抖音（session 方式，绕过 BBK 安装器检查）
set -uo pipefail
A="/usr/bin/adb"
APK=/root/s8/apks/douyin.apk
OUT=/root/s8/douyin_install.log
{
echo "=== 开始 $(date) ==="
ls -la "$APK"
SIZE=$(stat -c %s "$APK")
echo "大小: $SIZE"

echo "--- 推送到设备 ---"
$A shell "rm -f /data/local/tmp/douyin.apk" </dev/null 2>&1
$A push "$APK" /data/local/tmp/douyin.apk
echo "推送返回: $?"
$A shell "ls -la /data/local/tmp/douyin.apk" </dev/null 2>&1

echo "--- 创建 session ---"
SID=$($A shell "pm install-create -r -d -S $SIZE" </dev/null 2>&1 | grep -oE '[0-9]+' | head -1)
echo "session=$SID"
echo "--- 写入 ---"
$A shell "pm install-write -S $SIZE $SID base /data/local/tmp/douyin.apk" </dev/null 2>&1 | head -3
echo "--- 提交（大 APK 需要 1-2 分钟）---"
$A shell "pm install-commit $SID" </dev/null 2>&1 | head -5
echo "--- 验证 ---"
$A shell "pm list packages | grep -iE 'aweme|douyin|ss.android.ugc'" </dev/null 2>&1
$A shell "dumpsys package com.ss.android.ugc.aweme 2>/dev/null | grep -E 'versionName|versionCode' | head -2" </dev/null 2>&1
$A shell "rm -f /data/local/tmp/douyin.apk" </dev/null 2>&1
echo "=== 完成 $(date) ==="
} > $OUT 2>&1
