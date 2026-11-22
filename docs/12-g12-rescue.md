# 12 · G12（MTK）救砖记录

> 这是另一台备用机（SIRAGON SP-6100，MT6762V-WR，Android 13）的救砖过程，
> 记录在这里是因为：它是我们打包 boot 镜像的工具机，且验证了 MTK BROM 救砖流程。

## 症状

- 手机开机显示 **fastboot mode**，无法进入系统
- 用户描述："没电关机，充满后打不开"
- **没有刷过任何东西**（不是刷机事故）

## 诊断流程（mtkclient + BROM）

### 1. 进 BROM

```
关机 → 按住音量上+下 → 插 USB（窗口只有 0.5 秒，靠工具持续轮询）
```

### 2. mtkclient 连接

```bash
# mtkclient 依赖 + 源码（Python 3.13）
python mtk.py printgpt
```

输出：`Preloader - Device detected :)` + 完整 GPT。

关键分区：
```
boot_a       @0x19000000  32MB
init_boot_a  @0x1f000000  8MB
vbmeta_a     @0x20500000  8MB
super        @0x31000000  4.6GB
userdata     @0x15b800000 9GB
```

### 3. 读 boot_a 并分析

```bash
python mtk.py r boot_a boot_a.img
```

分析结果：
```
ANDROID! boot v2
kernel 11MB + ramdisk 11.7MB (gzip)
ramdisk 含 MAGISK/magiskinit/overlay.d → Magisk 补丁完整 ✓
boot_b 全零（A-only 空分区，正常）
init_boot 全零（正常）
```

**结论：boot 没坏。**

### 4. 找到真凶：`para` 分区

```bash
python mtk.py r para para.img
hexdump para.img
```

内容：
```
62 6F 6F 74 2D 72 65 63 6F 76 65 72 79 ... = "boot-recovery!"
```

→ `para`（MTK 的 misc 分区）里写着 **"boot-recovery"** 标志，
每次开机都要求进 recovery 模式；recovery 不存在/损坏 → 卡在黑屏/fastboot。

**不是用户弄坏的，是之前某次 `adb reboot recovery` 或系统更新留下的标志。**

### 5. 修复

```bash
python mtk.py e para      # 擦除 para
python mtk.py reset       # 重启
```

擦除后 para 全零，重启 → 应该正常进系统。

## 教训

1. **MTK 设备黑屏/fastboot ≠ 系统坏了**，先查 `para`/`misc` 的 boot-recovery 标志
2. mtkclient 的 BROM 连接**一旦建立就保持**（不像 0.5s 窗口想象的那样短）——
   第一次连上后可以连续执行多条命令
3. 读分区前先备份（`mtk r` 到本地文件）
4. Python 依赖：mtkclient 不在 PyPI，需从 GitHub 下载源码；
   依赖（usb/pyusb/Crypto/capstone/keystone）可以复用现有 site-packages

## 附：G12 的价值

- **它是我们 该设备 boot 镜像的打包机**（用 magiskboot 官方流程重打 v1–v6）
- 证明了 Magisk 的 boot 补丁流程在这台 MTK 设备上可行（但 Unisoc 不行 → 该设备 黑屏）
- 未来可作为 该设备 的模块引擎参考（Magisk 模块结构）
