#!/bin/bash
A="/usr/bin/adb"

echo "########## 1. 热限流状态 ##########"
$A shell "dumpsys thermalservice 2>/dev/null | head -30" </dev/null 2>&1
echo ""
echo "--- thermal zones ---"
$A shell "for z in /sys/class/thermal/thermal_zone*/; do n=\$(cat \$z/type 2>/dev/null); t=\$(cat \$z/temp 2>/dev/null); echo \"\$n = \$t\"; done 2>/dev/null | head -15" </dev/null 2>&1
echo ""
echo "########## 2. CPU 全部 policy ##########"
$A shell "ls /sys/devices/system/cpu/cpufreq/ 2>/dev/null" </dev/null 2>&1
$A shell "for p in /sys/devices/system/cpu/cpufreq/policy*/; do echo \"== \$p\"; cat \$p/related_cpus 2>/dev/null; cat \$p/scaling_min_freq \$p/scaling_max_freq \$p/cpuinfo_max_freq \$p/scaling_governor 2>/dev/null; done" </dev/null 2>&1
echo ""
echo "########## 3. BBK 性能相关属性 ##########"
$A shell "getprop | grep -iE 'bbk|sprd' | grep -iE 'perf|game|frame|fps|boost|thermal|mode' | head -20" </dev/null 2>&1
echo ""
echo "########## 4. 性能服务/守护 ##########"
$A shell "getprop | grep -iE 'init.svc.perf|init.svc.thermal|init.svc.game|perfmonitord'" </dev/null 2>&1
echo ""
echo "########## 5. 当前负载/频率实时 ##########"
$A shell "cat /proc/loadavg; echo '---'; for c in 0 4 7; do echo -n \"cpu\$c: \"; cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_cur_freq 2>/dev/null; done" </dev/null 2>&1
echo ""
echo "########## 6. 游戏中心/应用市场帧率限制相关设置 ##########"
$A shell "settings list global 2>/dev/null | head -40" </dev/null 2>&1
