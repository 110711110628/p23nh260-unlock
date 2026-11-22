#!/bin/bash
A="/usr/bin/adb"

echo "########## 1. 内核调度参数实际值 ##########"
for f in sched_energy_aware sched_util_clamp_min sched_util_clamp_max sched_boost sched_rt_runtime_us sched_rt_period_us sched_latency_ns sched_min_granularity_ns sched_wakeup_granularity_ns sched_migration_cost_ns sched_use_walt_cpu_util sched_use_walt_task_util sched_clamp_min2boost; do
  echo -n "$f = "
  $A shell "cat /proc/sys/kernel/$f 2>/dev/null || echo '(不可读)'" </dev/null 2>&1
done
echo ""
echo "########## 2. 充电/供电状态（可能触发性能模式）##########"
$A shell "dumpsys battery 2>/dev/null | grep -E 'level|status|AC|USB|powered|temperature' | head -8" </dev/null 2>&1
echo ""
echo "########## 3. 频率钉住的来源排查 ##########"
echo "--- 是否有 thermal cooling device 在限制 ---"
$A shell "ls /sys/class/thermal/cooling_device*/ 2>/dev/null | head; for c in /sys/class/thermal/cooling_device*/; do echo -n \"\$(cat \$c/type 2>/dev/null): state=\"; cat \$c/cur_state 2>/dev/null; done" </dev/null 2>&1 | head -20
echo ""
echo "--- 是否 unisoc 的 dvfs/cpufreq 有 boost 节点 ---"
$A shell "ls /sys/module/ 2>/dev/null | grep -iE 'cpufreq|dvfs|sched|perf' | head -10" </dev/null 2>&1
$A shell "find /sys -name '*boost*' -maxdepth 4 2>/dev/null | head -10" </dev/null 2>&1
echo ""
echo "--- perfmonitord 是否有日志/配置 ---"
$A shell "ls -la /data/vendor/perf* /data/local/tmp/perf* /vendor/etc/perf* 2>/dev/null | head" </dev/null 2>&1
$A shell "logcat -d 2>/dev/null | grep -aiE 'perfmonitord|perf monitor|PowerHal|setBoost|boost' | tail -10" </dev/null 2>&1
echo ""
echo "########## 4. 电量/温度 ##########"
$A shell "cat /sys/class/power_supply/battery/capacity 2>/dev/null; cat /sys/class/power_supply/battery/temp 2>/dev/null; cat /sys/class/power_supply/battery/status 2>/dev/null" </dev/null 2>&1
echo ""
echo "########## 5. 验证能否写 sysfs（root 通道）##########"
cat > /tmp/s8cpu_probe.sh <<'SH'
#!/system/bin/sh
OUT=/data/local/tmp/cpuprobe.txt
{
echo "uid=$(id -u) ctx=$(cat /proc/self/attr/current)"
echo "--- 尝试读 perfmonitord 环境 ---"
cat /proc/$(pidof perfmonitord)/environ 2>/dev/null | tr '\0' '\n' | grep -iE 'perf|mode|boost' | head -5
echo "--- 当前 min freq ---"
for p in /sys/devices/system/cpu/cpufreq/policy*/; do echo -n "$p min="; cat $p/scaling_min_freq 2>/dev/null; done
} > $OUT 2>&1
chmod 666 $OUT
SH
$A push /tmp/s8cpu_probe.sh /data/local/tmp/s8cmd.sh >/dev/null 2>&1
sleep 6
$A shell "cat /data/local/tmp/cpuprobe.txt 2>/dev/null" </dev/null 2>&1
