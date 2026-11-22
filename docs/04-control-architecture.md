# 04 · 管控体系七层测绘（核心）

> 这是本项目最重要的文档：把 厂商 这台学习机的**整套管控体系**逐层拆解。
> 每一层都附有实证（日志、文件、反编译结果）。

## 总览

```
第 7 层  云 + 内容        h600s.vendor.net / 监管平台 / 课程授权
第 6 层  应用层           20+ 个 厂商 自研系统应用
第 5 层  安装/管控层      BPackageInstaller + BPK + 云端黑/白名单
第 4 层  框架层           services.jar / framework.jar 深度魔改
第 3 层  内核层           5.4.210 + 厂商 模块 + SELinux 定制域
第 2 层  引导/安全层      U-Boot 定制 + AVB + seccfg 保护
第 1 层  硬件             展锐 UMS9620 BSP
```

---

## 第 2 层：引导/安全层

| 机制 | 实证 | 我们的突破 |
|---|---|---|
| BL 锁定 + seccfg 保护 | `unlock_ability=0` | BROM 漏洞改 seccfg |
| AVB 校验 | vbmeta_a "AVB0"，flags=0 | 解锁容忍 + TWRP fstab 关 verity |
| BROM 窗口 ~19 秒 | 实测需按键+插线 | 用 spd_dump 抢窗口 |
| boot 镜像自定义 | init 包装器 + `init.magisk` | 研究出包装器注入方法 |

## 第 3 层：内核 + SELinux

- 内核 5.4.210（Unisoc BSP 深度定制）
- 厂商 自加内核模块（`bm8.ko` 等）
- **SELinux 自定义域**（实测策略含）：

```
bbk_allowlist_app     ← com.vendor.bbkallowlisting
bbk_selftest          ← com.vendor.selftest
bbklog_app            ← com.vendor.bbklogger
bbk_stresstest_app    ← com.vendor.stresstest
```

- 策略中有大量 allow 规则（init→shell、shell→shell_exec、shell→system_file 等），
  我们利用这些规则实现 root 通道（见 06）
- **限制**：shell 域 root 读不了 /sdcard（fuse 权限）、不能 mount、
  不能写 /data/system —— 这是 SELinux 的域限制，不是 uid 限制

## 第 4 层：框架层（services.jar / framework.jar 魔改）

| 机制 | 位置 | 作用 |
|---|---|---|
| **AdbService 重写** | services.jar | `systemReady()` 里：`adbInUsb ? test_harness : true` 决定 `adb_enabled` |
| **PackageManagerShellCommand 加门** | services.jar | `pm install` 前调 `getRemoteUsbState()`（云端授权）|
| **PadSecurityService** | services.jar | `checkComponentProcessForbidStart()` —— AMS 层的**应用启动门** |
| **厂商CustomizedService/Delegate** | services.jar | AIDL 定制服务层（绑定 bbkallowlisting） |
| **OvumOvulationService** | services.jar | ovum 定制服务 |
| **ovum_util / IOLimitController** | services.jar | 后台应用清理、IO 限流 |
| **MagicManager / FrameRtgManager** | services.jar | 窗口管理/帧率调度魔改 |
| **versiond** | system | 分区完整性校验（实际未阻断） |

### 关键日志证据

```
D PackageManagerShellCommand: runinstall getRemoteUsbState
D 厂商CustomizedDelegate: delegate getRemoteUsbState
W ActivityManager: Unable to start service Intent { cmp=com.vendor.bbkallowlisting/.service.CustomizedService } not found
D PadSecurityService: checkComponentProcessForbidStart android 1000 null PackageNameNull
D PadSecurityService: doRetrieveServiceLocked true callingPackageName com.example.appmarket targetPackageName com.example.appmarket
```

## 第 5 层：安装/管控层（本项目主战场）

### BPK 私有包格式

- 系统 APK 全部是 `BPK\x03`（"BPK" 魔数）容器
- 结构 = 标准 ZIP 的加密/改造版本；可用自研 `bpk_converter.py` 无损互转
- 验证：BPK→APK→BPK 往返 md5 一致
- 安装器只接受 **3 张 厂商 证书签名**的 BPK

### 安装器三重校验（`PackageInstallerActivity.PreInstallTask`）

```
1. BPK 格式？ → 校验 3 张 厂商 证书之一
   89:3E:2B:8C:1B:B6:9A:DB:DF:36:F4:0F:59:0C:62:82
   14:08:7C:E9:ED:28:A7:4F:A1:77:AA:89:14:47:57:4E
   40:59:05:EB:57:5C:99:63:4C:87:4A:EE:26:FE:E4:9D

2. 普通 APK？ → isInWhiteList（云端查签名）
              → 拒绝特定签名 E8:9B:15:8E:...（Magisk 等通用签名）

3. isInBlackList（云端查包名；离线 = fail-closed → 判黑）
   已安装的应用跳过黑名单
```

### 我们的破解：dex 补丁

`BPackageInstaller.apk`（4 个 dex，dex 是 `classes4.dex`）：

| 方法 | 补丁 |
|---|---|
| `PackageInstallerActivity.isInBlackList(String)Z` | → `return false` |
| `Utils.isInBlackList(Context,String,ApplicationInfo)Z` | → `return false` |
| `Utils.isApkFileCanInstall(Context,String,String)Z` | → `return true` |

补丁方式（`scripts/analysis/patch_installer.py`）：
1. BPK → APK（`bpk_converter.py`）
2. 解析 DEX 找到方法 code_item，覆写 `const/4 v0,#0; return v0`
3. 修复 dex checksum + SHA1 signature
4. zipalign + apksigner 重签
5. APK → BPK 写回系统镜像

**验证**：logcat 出现 `handlerScanStatus SCAN_RESULT_ALLOW_INSTALL` ✓

## 第 6 层：应用层（20+ 自研应用）

| 应用 | 包名 | 作用 | 我们的处置 |
|---|---|---|---|
| 家长助手 | `com.vendor.parentsupport` | "监管平台禁用app"弹窗、杀应用 | **禁用**（应用启动门） |
| 白名单云控 | `com.vendor.bbkallowlisting` | CustomizedService 宿主 | 禁用 |
| 安全管理 | `com.vendor.padsecuritymanager` | PadSecurityService | 禁用 |
| 护眼/网课 | `com.vendor.ovumserver` | URL 拦截、家长管控 | 禁用 |
| 绿网 | `com.vendor.greensecuritymidware` | 内容过滤 | 禁用 |
| 自研商店 | `com.vendor.bbkmiddlemarket` | 应用商店 | **恢复启用**（用户选择）|
| 日志 | `com.vendor.bbklogger` + proxy | 行为日志 | 保留 |
| 自检/压测 | `com.vendor.selftest`/`stresstest` | 工程测试 | 保留 |
| OTA | `com.vendor.tools.otaupdate` | 系统更新 | **单独禁用** |
| AI 视觉 | `com.vendor.vision` | 相关 | 保留 |
| 桌面 | `com.bbk.studyos.launcher` | 学习桌面 | 保留 |
| 学习矩阵 | synstudy/synmath/synchinese/… | 学习内容 | **全部保留** |

## 第 7 层：云 + 内容

| 服务 | 端点（实证） | 用途 |
|---|---|---|
| 安装器云端 | `h600s.vendor.net/app/apkInfoApiOk100/newestApkInfosByApkPackageNamesForInstaller` | 黑/白名单查询 |
| 商店下载 | `<vendor-cdn>` | APK/patch 下载 |
| 监管平台 | 应用市场/家长助手内的"监管"提示 | 管控下发 |
| 内容授权 | 新东方/黄冈等课程 | 付费内容 |

---

## 结论：厂商投入评估

| 维度 | 估算 |
|---|---|
| 平台级系统+云+内容 | 100–200 人年 |
| 本机型（该设备） | **20–40 人年** |
| 防破解专项 | 3–5 人年 |
| 研发周期 | 18–24 个月 |

**最讽刺的一点**：投入最大、最精心的部分恰恰是"防止安装第三方应用"的管控链
（BPK、云端黑名单、pm 门、启动门、家长监管），因为它绑定 60%+ 毛利。
而我们只用**一个 dex 补丁（3 个方法）**就拆掉了最后一层。
