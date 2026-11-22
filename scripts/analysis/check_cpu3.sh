#!/bin/bash
A="/usr/bin/adb"

echo "########## 1. 硬件频率范围（确认正常值）##########"
$A shell "for p in /sys/devices/system/cpu/cpufreq/policy*/; do echo \"== \$p\"; echo -n 'cpuinfo_min: '; cat \$p/cpuinfo_min_freq 2>/dev/null; echo -n 'cpuinfo_max: '; cat \$p/cpuinfo_max_freq 2>/dev/null; echo -n 'available freqs: '; cat \$p/scaling_available_frequencies 2>/dev/null | head -c 200; echo; done" </dev/null 2>&1
echo ""
echo "########## 2. 用 root 通道尝试写 min_freq（测试 SELinux 权限）##########"
cat > /tmp/s8cpu_write.sh <<'SH'
#!/system/bin/sh
OUT=/data/local/tmp/cpuwrite.txt
{
echo "uid=$(id -u) ctx=$(cat /proc/self/attr/current)"
echo "--- 读取当前 ---"
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
echo "--- 尝试写入 614400 ---"
echo 614400 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 2>&1 && echo "policy0 写入成功" || echo "policy0 写入失败"
echo 614400 > /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq 2>&1 && echo "policy4 写入成功" || echo "policy4 写入失败"
echo 614400 > /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq 2>&1 && echo "policy7 写入成功" || echo "policy7 写入失败"
echo "--- 写入后 ---"
for p in /sys/devices/system/cpu/cpufreq/policy*/; do echo -n "$p min="; cat $p/scaling_min_freq 2>/dev/null; done
echo "--- dmesg 是否有 avc denied ---"
dmesg 2>/dev/null | grep -i "avc.*denied" | grep -i cpufreq | tail -3
} > $OUT 2>&1
chmod 666 $OUT
SH
$A push /tmp/s8cpu_write.sh /data/local/tmp/s8cmd.sh >/dev/null 2>&1
sleep 6
$A shell "cat /data/local/tmp/cpuwrite.txt 2>/dev/null" </dev/null 2>&1
echo ""
echo "########## 3. 写完后等 5 秒看是否被系统改回 ##########"
sleep 5
$A shell "for p in /sys/devices/system/cpu/cpufreq/policy*/; do echo -n \"\$p min=\"; cat \$p/scaling_min_freq 2>/dev/null; echo -n \" cur=\"; cat \$p/scaling_cur_freq 2>/dev/null; done" </dev/null 2>&1
echo ""
echo "########## 4. 当前场景（PowerHAL）##########"
$A logcat -d 2>/dev/null | grep -aE "PowerHAL.*(scene|Enter|Exit)" | tail -8
