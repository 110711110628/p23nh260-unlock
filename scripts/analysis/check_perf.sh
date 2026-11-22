#!/bin/bash
A="/usr/bin/adb"

echo "########## 1. 桌面上的"应用市场"图标来源 ##########"
echo "--- 名字含 market/store/应用市场 的包 ---"
$A shell "pm list packages | grep -iE 'market|store|appgallery|vending'" </dev/null 2>&1
echo ""
echo "--- 各自 LAUNCHER activity ---"
for p in com.huawei.appmarket com.eebbk.bbkmiddlemarket com.bbk.studyos.launcher com.android.vending; do
  echo -n "$p => "
  $A shell "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $p" </dev/null 2>&1 | tail -1
done
echo ""
echo "--- 已安装的第三方/系统商店（launcher 名字）---"
$A shell "for p in com.huawei.appmarket com.eebbk.bbkmiddlemarket; do echo \"== \$p ==\"; dumpsys package \$p 2>/dev/null | grep -m1 -E 'versionName'; done" </dev/null 2>&1
echo ""
echo "########## 2. 帧率/刷新率 ##########"
$A shell "dumpsys SurfaceFlinger 2>/dev/null | grep -iE 'refresh|fps|DisplayHardware|frame rate' | head -20" </dev/null 2>&1
echo ""
echo "--- 显示模式 ---"
$A shell "dumpsys display 2>/dev/null | grep -iE 'mode|fps|refresh' | head -15" </dev/null 2>&1
echo ""
echo "########## 3. CPU 频率限制 ##########"
$A shell "for c in 0 4 7; do echo \"cpu\$c:\"; cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_cur_freq /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_max_freq /sys/devices/system/cpu/cpu\$c/cpufreq/cpuinfo_max_freq /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_governor 2>/dev/null; done" </dev/null 2>&1
echo ""
echo "--- 温度/限流 ---"
$A shell "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -8" </dev/null 2>&1
echo ""
echo "########## 4. 性能相关属性 ##########"
$A shell "getprop | grep -iE 'fps|frame|perf|boost|thermal|refresh' | head -25" </dev/null 2>&1
echo ""
echo "########## 5. 性能模式/游戏模式设置 ##########"
$A shell "settings list global 2>/dev/null | grep -iE 'perf|game|fps|frame|boost' | head -10" </dev/null 2>&1
$A shell "settings list system 2>/dev/null | grep -iE 'perf|game|fps|frame' | head -10" </dev/null 2>&1
echo ""
echo "########## 6. 厂商性能服务 ##########"
$A shell "ps -A -o PID,ARGS 2>/dev/null | grep -iE 'perf|power|thermal|game|boost' | head -10" </dev/null 2>&1
