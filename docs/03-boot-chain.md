# 03 · 引导链 / BROM / AVB / TWRP

## 1. 启动链

```
BootROM (BROM)  ← 可被 spd_dump 劫持
   ↓ FDL1 (0x65000800) / FDL2 (0xb4fffe00)
   ↓ U-Boot (厂商 定制，含版本校验/解锁状态)
   ↓ boot_a (init 包装器 + 内核)
   ↓ vendor_boot_a (TWRP 或原厂)
   ↓ Android 13 系统
```

关键地址（spd_dump 用）：

```
BROM:     1782:4d00（USB VID:PID）
FDL1:     0x65000800
FDL2:     0xb4fffe00
exec_addr 0x65012f48（CVE 漏洞载荷地址）
```

## 2. Bootloader 解锁

- 设备出厂 BL 锁定（`androidboot.verifiedbootstate=orange` 是解锁后状态）
- 官方不开放解锁：`unlock_ability=0`
- **解锁方法**：BROM 模式下通过漏洞载荷修改 `seccfg` 分区
  - 使用 `spd_dump` + custom_exec_no_verify 载荷
  - 修改后 BL 显示橙色警告，但允许刷写/启动未签名镜像

> 风险：BROM 窗口约 19 秒，需在窗口内完成；解锁后所有分区可写。

## 3. boot_a 镜像结构（重要）

厂商 的 boot_a 是 **Android boot v2 格式**（非 v3/v4）+ **自定义 init 包装器**：

```
magic:       "ANDROID!"
kernel_size: 11,031,603  (@0x08)
kernel_addr: 0x40080000
ramdisk_size:11,728,073  (@0x10)
ramdisk_addr:0x51b00000
page_size:   2048
header_version: 2
cmdline:     "bootopt=64S3,32N2,64N2 buildvariant=user"
```

- 内核起始：`0x800`（2048），gzip 压缩
- ramdisk 起始：`0xA86000`（对齐后），gzip 压缩（解压后 ~27.7MB）
- ramdisk 内含：`init`（厂商 定制包装器）、`init.magisk`（原厂 init）、`probe.sh`、
  `system/`（first_stage_ramdisk + fstab）、`overlay.d`、`.backup` 等

### 我们注入的包装器（initwrap10）

```
PID1 (包装器)
  ├─ fork
  │   └─ 父进程 → execve("/init.magisk")   ← 原厂 init
  └─ 子进程（kernel 域，uid 0）
        ├─ 等待 /proc/1/root/system/bin/sh 就绪
        ├─ chroot 到 /proc/1/root（真实根）
        ├─ 等待 /data 解密（只读探测，不写 /data，避免 FBE 卡死）
        ├─ 强制 permissive（写 /sys/fs/selinux/enforce=0）
        └─ execve("/system/bin/sh", "-c", <内联脚本>)
```

**重要教训**：
- 向 vendor_boot 注入内核模块会导致**第一阶段 init 报错 → kernel panic（黑屏）**，
  因为 `androidboot.init_fatal_panic=true`。**永远不要往 vendor_boot 塞模块。**
- 包装器子进程在 **SELinux enforcing + kernel 域**下无法写文件/exec，
  因此 `force_permissive()` 是第一优先级（但在 kernel 域经常被策略拦截）。

## 4. vendor_boot / TWRP

- vendor_boot_a = **TWRP 原生镜像**（`twrp_s8native_full.img`，100MB）
- TWRP 的 fstab **没有 avb 参数** → 所以当前系统 dm-verity 是关闭的（关键前提）
- vendor_boot 结构：

```
magic:      "VNDRBOOT"
header v4:  ramdisk_size@0x18, header_size@0x830,
            dtb_addr@0x834, dtb_size@0x838,
            table@0x83c, bootconfig@0x848
ramdisk 对齐: 4096
真实 dtb 起始 = align(4096+ramdisk)+0x40
```

- 修改 vendor_boot 的 cmdline（偏移 `0x1c`，2048 字节）可注入内核参数。
  但实测**启动器不合并镜像 cmdline**（permissive 参数未生效）。

## 5. AVB / dm-verity

```
vbmeta_a:    "AVB0" magic，flags=0（verification 启用）
vbmeta_system_a / vbmeta_vendor_a: 同上
```

- 解锁状态下，启动器容忍 AVB 失败（显示橙色警告后继续）
- 但 **dm-verity 由 fstab 控制**：TWRP vendor_boot 的 fstab 无 avb 标志 → verity 关闭
- 因此修改 system/product 不会被 verity 拦（**只能**通过 TWRP vendor_boot 实现）

## 6. 恢复手段（救砖）

| 场景 | 手段 |
|---|---|
| bl 损坏/分区错乱 | BROM + spd_dump 写回 `super.bin`（8GB 备份，~35 分钟） |
| boot 损坏 | TWRP dd 写回 `backup/boot_a.bin`（64MB） |
| vendor_boot 损坏 | TWRP dd 写回 `img/twrp_s8native_full.img` |
| 系统刷坏 | TWRP 写回 `system_a.img`（3GB）或 `product_a.img` |

> 所有原始镜像/备份保存在服务器，见 README 的备份清单。
