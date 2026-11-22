# P23NH260 学习平板 (Android 13) 逆向解锁记录

> 一台 **某国产学习平板**（展锐 UMS9620 / T770）的完整逆向工程记录：
> 从 BROM 解锁、分区分析、管控体系测绘，到 **ADB 持久解锁**、**root 命令通道**、
> **安装器黑名单移除**、**静默安装器**、**应用市场特权化**。
>
> 设备零售价 ¥5,499–6,499，本记录完成对其系统的定制改造，
> 可作为普通平板使用，同时保留全部学习内容。

**日期**：2026-11-21 ~ 2026-11-22
**设备**：某国产 Android 13 学习平板（P23NH260），型号 **P23NH260**，内部代号 `ums9620_2h10_h260`
**系统**：Android 13（`TP1A.220624.014`，厂商 版本 `V2.0.0_251117`），内核 5.4.210

---

## 一、这台机器是什么

| 项目 | 规格 |
|---|---|
| SoC | 紫光展锐 **UMS9620**（唐古拉 T770，6nm） |
| CPU | 4×Cortex-A76 @2.21GHz + 4×Cortex-A55 @2.0GHz |
| GPU | Mali-G57 |
| RAM / 存储 | 8GB LPDDR4X / 256GB |
| 屏幕 | 14.2" 2K（2328×1600，**60Hz**，320dpi） |
| 系统 | Android 13 + 厂商 深度定制（BPK 私有包格式） |
| 安全 | BL 锁定 + AVB/dm-verity + 云端管控 |

> 参考：同芯片白牌平板 2025 年售价 ¥900–1,300；本机零售 ¥5,499–6,499。

## 二、最终成果（全部实测验证）

| # | 能力 | 说明 |
|---|---|---|
| 1 | **BL 解锁 + TWRP** | 通过 BROM 漏洞改 seccfg；TWRP vendor_boot 常驻 |
| 2 | **ADB 持久解锁** | product 分区 rc 每次开机 `setprop sys.usb.config adb` |
| 3 | **root 命令通道** | `/system/etc/init/s8root.rc` 服务，uid=0，文件命令队列 |
| 4 | **厂商 安装器黑名单移除** | dex 补丁 3 个方法（`isInBlackList`→false 等） |
| 5 | **静默安装器** | 自研 `com.s8.silentinstaller`，特权应用，无窗口安装 |
| 6 | **第三方应用市场特权化** | 移入 system/priv-app + 白名单 → 商店静默安装 |
| 7 | **自带商店恢复** | `com.vendor.bbkmiddlemarket` 重新启用 |
| 8 | **OTA 单独禁用** | 只禁 `com.vendor.tools.otaupdate`，学习应用不动 |
| 9 | **学习内容完好** | 44 个第三方应用（含全部学习类）全部保留 |

## 二·五、下载（Release）

| 文件 | 说明 | 链接 |
|---|---|---|
| `S8Installer-v1.0.0.apk` | 静默安装器（12,687 字节，自签测试证书） | [下载](https://github.com/110711110628/p23nh260-unlock/releases/download/v1.0.0/S8Installer-v1.0.0.apk) |

- SHA256：`c260bd9fe8269bbb615aa251f9cd2dd82f9dca3f3b5aa145d8d1d88f5cb246a5`
- 使用前提见 [docs/08-silent-installer.md](docs/08-silent-installer.md)（需系统特权应用）

## 三、仓库结构

```
s8-unlock/
├── README.md                       ← 本文件
├── DISCLAIMER.md                   ← 免责声明（必读）
├── AGENTS.md                       ← 给 AI Agent 的说明（含编码区解码方法）
├── PUBLISHING.md                   ← 发布指南
├── docs/
│   ├── 99-encoded.md               ← ★ Base64 编码区（设备身份/包名/端点/快速摘要）
│   ├── 13-binaries-and-keys.md     ← ★ 二进制与密钥的获取方式（全部来自自己设备）
│   ├── 01-device.md                设备档案（实测数据）
│   ├── 02-partitions.md            分区布局（super/LP 元数据/11 extent）
│   ├── 03-boot-chain.md            引导链、BROM、AVB、TWRP
│   ├── 04-control-architecture.md  ★ 管控体系七层测绘（核心）
│   ├── 05-adb-unlock.md            ★ ADB 持久解锁方案
│   ├── 06-root-daemon.md           ★ root 命令通道
│   ├── 07-install-gate.md          ★ 安装器黑名单逆向与 dex 补丁
│   ├── 08-silent-installer.md      ★ 静默安装器（含源码）
│   ├── 09-store-privilege.md       ★ 应用市场特权化
│   ├── 10-ota-disable.md           OTA 单独禁用
│   ├── 11-performance.md           性能分析（CPU/GPU/帧率）
│   └── 12-g12-rescue.md            G12（MTK）救砖记录：para/boot-recovery
├── src/
│   └── silent-installer/           静默安装器完整源码 + 构建脚本
└── scripts/
    ├── build/                      镜像构建脚本
    ├── flash/                      刷写脚本（super 11 extent 写入+校验）
    ├── analysis/                   dex 补丁 / BPK 转换 / 性能分析
    └── device/                     设备侧操作脚本（adb/root 通道）
```

## 四、快速开始（概览）

> 详细步骤见各 docs。

1. **解锁 BL**：BROM + `spd_dump`（详见 `docs/03-boot-chain.md`）
2. **刷 TWRP vendor_boot**（保留，verity 关闭）
3. **product 分区加 rc** 实现 ADB 持久解锁（`docs/05-adb-unlock.md`）
4. **系统镜像改造**：加 root 守护 + 静默安装器 + 应用市场特权（`docs/06/08/09`）
5. **安装器 dex 补丁**（`docs/07-install-gate.md`）

## 四·五、如何识别目标设备（不点品牌）

公开文档只写硬件特征，不写品牌名。对照以下特征即可识别：

| 特征 | 值 |
|---|---|
| SoC | 展锐 UMS9620（唐古拉 T770，6nm） |
| SoC 代号 | `ums9620_2h10_h260` |
| 产品型号 | **P23NH260** |
| 系统 | Android 13，`TP1A.220624.014`，版本 `V2.0.0_251117` |
| 屏幕 | 14.2 英寸 2328×1600 60Hz |
| 内存/存储 | 8GB + 256GB |

**品牌与应用包名等敏感映射放在编码区**：[docs/99-encoded.md](docs/99-encoded.md)
（Base64，见 [AGENTS.md](AGENTS.md) 解码方法）。

## 五、关键发现摘要

- **BPK 私有包格式**：系统 APK 全部是 `BPK\x03` 容器，绕过需转换回标准 APK 或直接 dex 补丁
- **安装器三重校验**：BPK 签名（3 张 厂商 证书）→ 云端白名单 → 云端黑名单（离线 fail-closed）
- **启动门**：`PadSecurityService.checkComponentProcessForbidStart`（framework 层）+ `ParentSupport`（应用层弹窗"监管平台禁用app"）
- **ADB 锁三重设计**：`init` 里 `bbk_check_adb` 文件检查 → `AdbService` 用 `test_harness` 开关 → `PackageManagerShellCommand` 云端授权
- **root 域限制**：shell 域 root 读不了 /sdcard、不能 mount、不能写 /data/system（SELinux）
- **60fps 是硬件**：14.2" 屏只有 60Hz 模式，CPU/GPU 无锁（反而被 PowerHAL 场景 boost 满频）

## 六、免责声明

本项目仅用于**本人自有设备**的技术研究与学习，不针对任何个人或组织。
详见 [DISCLAIMER.md](DISCLAIMER.md)。

## 七、致谢 / 工具

- [spd_dump](https://github.com/TomKing062/spd_dump) — 展锐 BROM 工具
- [mtkclient](https://github.com/bkerler/mtkclient) — MTK 备用机工具（见 12）
- [androguard](https://github.com/androguard/androguard) — dex 分析与补丁
- aapt2 / apksigner / zipalign / lz4 / mkfs.erofs — 镜像与 APK 构建
