#!/bin/bash
A="/usr/bin/adb"

echo "########## 1. GPU 频率/调度 ##########"
$A shell "ls /sys/class/devfreq/ 2>/dev/null" </dev/null 2>&1
$A shell "for d in /sys/class/devfreq/*/; do echo \"== \$d\"; cat \$d/name 2>/dev/null; echo -n 'min: '; cat \$d/min_freq 2>/dev/null; echo -n 'max: '; cat \$d/max_freq 2>/dev/null; echo -n 'cur: '; cat \$d/cur_freq 2>/dev/null; echo -n 'governor: '; cat \$d/governor 2>/dev/null; echo -n 'avail governors: '; cat \$d/available_governors 2>/dev/null; done" </dev/null 2>&1 | head -40
echo ""
echo "########## 2. cgroup/cpuset 限制（游戏进程能用的核）##########"
cat > /tmp/s8cpuset.sh <<'SH'
#!/system/bin/sh
OUT=/data/local/tmp/cpuset.txt
{
echo "=== cpuctl 各组的 cpus ==="
for d in /dev/cpuctl/*/; do
  n=$(basename "$d")
  echo -n "$n: cpus="; cat "$d/cpuset.cpus" 2>/dev/null
  echo -n "    uclamp.min="; cat "$d/cpu.uclamp.min" 2>/dev/null
  echo -n "    uclamp.max="; cat "$d/cpu.uclamp.max" 2>/dev/null
  echo -n "    shares="; cat "$d/cpu.shares" 2>/dev/null
  echo
done
echo ""
echo "=== 当前游戏进程所在 cgroup ==="
for p in $(pidof com.tencent.tmgp.sgame 2>/dev/null); do
  echo "pid=$p"
  cat /proc/$p/cgroup 2>/dev/null
  echo -n "  uclamp.min="; cat /proc/$p/sched_util_clamp_min 2>/dev/null
  echo -n "  uclamp.max="; cat /proc/$p/sched_util_clamp_max 2>/dev/null
  echo -n "  cpus_allowed="; grep Cpus_allowed_list /proc/$p/status 2>/dev/null
done
echo ""
echo "=== sched_energy_aware / 相关调参 ==="
for f in sched_energy_aware sched_util_clamp_min sched_util_clamp_max sched_boost sched_rt_runtime_us sched_latency_ns sched_min_granularity_ns sched_wakeup_granularity_ns sched_clamp_min2boost; do
  echo -n "$f = "; cat /proc/sys/kernel/$f 2>/dev/null || echo "(不可读)"
done
} > $OUT 2>&1
chmod 666 $OUT
SH
$A push /tmp/s8cpuset.sh /data/local/tmp/s8cmd.sh >/dev/null 2>&1
sleep 8
$A shell "cat /data/local/tmp/cpuset.txt 2>/dev/null" </dev/null 2>&1
