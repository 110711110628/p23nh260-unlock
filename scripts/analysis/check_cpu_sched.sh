#!/bin/bash
A="/usr/bin/adb"

echo "########## 1. CPU 在线/离线 ##########"
$A shell "cat /sys/devices/system/cpu/online 2>/dev/null; echo '--- 每个核 online ---'; for c in 0 1 2 3 4 5 6 7; do echo -n \"cpu\$c: \"; cat /sys/devices/system/cpu/cpu\$c/online 2>/dev/null || echo '(无节点/常开)'; done" </dev/null 2>&1
echo ""
echo "########## 2. 每个 policy 的频率范围/调度器/可用频率 ##########"
$A shell "for p in /sys/devices/system/cpu/cpufreq/policy*/; do echo \"=== \$p\"; echo -n 'cpus: '; cat \$p/related_cpus 2>/dev/null; echo -n 'min: '; cat \$p/scaling_min_freq 2>/dev/null; echo -n 'max: '; cat \$p/scaling_max_freq 2>/dev/null; echo -n 'hw_max: '; cat \$p/cpuinfo_max_freq 2>/dev/null; echo -n 'governor: '; cat \$p/scaling_governor 2>/dev/null; echo -n 'available: '; cat \$p/scaling_available_governors 2>/dev/null; done" </dev/null 2>&1
echo ""
echo "########## 3. schedutil 调参 ##########"
$A shell "for p in /sys/devices/system/cpu/cpufreq/policy*/; do echo \"=== \$p\"; for f in \$p/schedutil/*; do echo -n \"\$(basename \$f): \"; cat \$f 2>/dev/null; done; done" </dev/null 2>&1 | head -40
echo ""
echo "########## 4. 任务放置/负载均衡/boost ##########"
$A shell "cat /proc/sys/kernel/sched_boost 2>/dev/null; cat /proc/sys/kernel/sched_util_clamp_min 2>/dev/null; cat /proc/sys/kernel/sched_util_clamp_max 2>/dev/null; cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null; cat /proc/sys/kernel/sched_energy_aware 2>/dev/null" </dev/null 2>&1
$A shell "ls /proc/sys/kernel/ | grep sched | head -30" </dev/null 2>&1
echo ""
echo "########## 5. uclamp / cgroup ##########"
$A shell "ls -d /dev/cpuctl/* 2>/dev/null | head; for d in /dev/cpuctl/*/; do echo -n \"\$(basename \$d) cpus: \"; cat \$d/cpuset.cpus 2>/dev/null; done" </dev/null 2>&1 | head -20
echo ""
echo "########## 6. BBK/性能 相关节点与属性 ##########"
$A shell "ls /sys/kernel/ 2>/dev/null | grep -iE 'sched|perf|boost|game' | head -10" </dev/null 2>&1
$A shell "getprop | grep -iE 'sched|uclamp|ece|boost|game|perf' | head -25" </dev/null 2>&1
echo ""
echo "########## 7. perfmonitord 在干什么 ##########"
$A shell "ls -la /proc/\$(pidof perfmonitord)/ 2>/dev/null | head -5; cat /proc/\$(pidof perfmonitord)/cmdline 2>/dev/null | tr '\\0' ' '" </dev/null 2>&1
echo ""
echo "########## 8. 当前各核实时频率（采样 3 次）##########"
$A shell "for i in 1 2 3; do echo \"--- 第 \$i 次 ---\"; for c in 0 1 2 3 4 5 6 7; do echo -n \"cpu\$c=\$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_cur_freq 2>/dev/null) \"; done; echo; sleep 1; done" </dev/null 2>&1
echo ""
echo "########## 9. CPU 拓扑 ##########"
$A shell "cat /sys/devices/system/cpu/cpu0/topology/core_id 2>/dev/null; cat /sys/devices/system/cpu/cpu4/topology/core_id 2>/dev/null; cat /sys/devices/system/cpu/cpu7/topology/core_id 2>/dev/null" </dev/null 2>&1
$A shell "dumpsys cpuinfo 2>/dev/null | head -12" </dev/null 2>&1
