#!/bin/bash
A="/usr/bin/adb"

echo "########## 1. 所有 LAUNCHER activity（找应用市场相关）##########"
$A shell "cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>/dev/null | grep -iE 'market|appgallery|store|应用' | head -20" </dev/null 2>&1
echo ""
echo "--- 用 dumpsys 查两个商店包的全部 launcher activity ---"
for p in com.huawei.appmarket com.eebbk.bbkmiddlemarket; do
  echo "== $p =="
  $A shell "dumpsys package $p 2>/dev/null | grep -B1 -A3 'android.intent.category.LAUNCHER' | grep -E 'Activity|name' | head -12" </dev/null 2>&1
done
echo ""
echo "########## 2. launcher 里有多少个市场图标（启动器数据）##########"
$A shell "dumpsys package com.bbk.studyos.launcher 2>/dev/null | grep -iE 'market' | head -5" </dev/null 2>&1
echo ""
echo "--- 检查是否有重复的包（同包名多APK）---"
$A shell "pm path com.huawei.appmarket; echo '---'; pm path com.eebbk.bbkmiddlemarket" </dev/null 2>&1
echo ""
echo "########## 3. 应用市场是否有多个 LAUNCHER 入口 ##########"
$A shell "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.huawei.appmarket 2>/dev/null" </dev/null 2>&1
$A shell "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER com.eebbk.bbkmiddlemarket 2>/dev/null" </dev/null 2>&1
