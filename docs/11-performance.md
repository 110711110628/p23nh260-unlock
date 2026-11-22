# 11 · 性能分析（CPU / GPU / 帧率）

> 实测数据，用于回答"厂商有没有锁 CPU/帧率"。

## 1. 屏幕：只有 60Hz（硬件限制）

```
$ adb shell dumpsys display | grep supportedModes
supportedModes [{id=1, width=1600, height=2328, fps=60.0, alternativeRefreshRates=[]}]

$ adb shell dumpsys SurfaceFlinger | grep refresh-rate
refresh-rate : 60.00 Hz
```

**结论：14.2" 面板只有 60Hz 模式 → 游戏不可能超过 60fps（vsync 限制）。**
这不是软件锁，是硬件。

## 2. CPU：未锁频，反而被 boost 钉满

```
小核 cpu0-3:  cpuinfo 614MHz ~ 2.002GHz，governor=schedutil
大核 cpu4-7:  cpuinfo 614MHz ~ 2.21GHz，governor=schedutil
8 核全部 online
```

**实测当前状态**（连续 3 次采样）：

```
policy0 min=2002000 max=2002000  ← 钉在最高
policy4 min=2210000 max=2210000  ← 钉在最高
policy7 min=2210000 max=2210000  ← 钉在最高
```

来源：**厂商 PowerHAL 的场景 boost**（不是锁频）：

```
PowerHAL: Enter common_set: /dev/cpuctl/top-app-high-perf/cpu.uclamp.min: max
PowerHAL: Enter set_cluster_freqs_max_min:
PowerHAL: Enter common_set: /sys/class/devfreq/23140000.gpu/min_freq: 655200000
PowerHAL: ###Exit interaction_fling scene end###
```

- 交互/滑动场景会把 CPU min、GPU min、uclamp 全部拉满
- 设备插 USB 充电时也更容易触发

**想恢复省电调频**：需要关闭 PowerHAL 场景或直接写 sysfs
（shell 域 root 写 cpufreq 被 SELinux 拒绝，需改策略/域）。

## 3. cgroup/uclamp（游戏拿到的资源）

```
top-app:            uclamp.min=10, uclamp.max=max, shares=1024
top-app-high-perf:  uclamp.min=15, uclamp.max=max, shares=1280  ← 高性能
foreground:         uclamp.min=8
background:         uclamp.min=1, uclamp.max=60                  ← 后台压制
```

游戏在前台 → 进 `top-app` → 调度优先 ✓ 没有受限。

## 4. 温度/热限流

```
$ adb shell dumpsys thermalservice | grep 'Thermal Status'
Thermal Status: 0        ← 无限流
电池温度 22°C
```

## 5. 结论

| 项目 | 状态 |
|---|---|
| CPU 频率 | 完全可用，未锁（当前被 boost 钉满）|
| CPU 调度 | schedutil + EAS，8 核全开 |
| GPU | Mali-G57，有 devfreq + 场景 boost |
| 热限流 | 无 |
| **60 帧** | **60Hz 屏幕硬件限制** |

**一句话：厂商没锁 CPU/GPU/帧率；60fps 是屏幕决定的。**

## 6. 游戏实测预期

| 游戏 | 预期 |
|---|---|
| 王者荣耀 | 60fps 中高画质可跑稳 |
| 原神 | 低画质 30-45fps |
| 和平精英 | 中低画质 60fps 勉强 |
| 90/120fps 游戏 | 不可能（屏幕 60Hz）|

## 7. 相关脚本

- `scripts/analysis/check_perf.sh` — 帧率/CPU/热 概览
- `scripts/analysis/check_cpu_sched.sh` — 调度器/频率/uclamp 详情
- `scripts/analysis/check_cpu3.sh` — sysfs 写入测试（含 SELinux 拒绝验证）
