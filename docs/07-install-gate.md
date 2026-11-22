# 07 · 安装器黑名单逆向与 dex 补丁

## 1. 问题：为什么 sideload 的 APK 装不上

厂商 的 `com.android.packageinstaller`（BPK 格式，13.6MB）在
`PackageInstallerActivity.PreInstallTask.doInBackground` 里做了三重校验。

### 反编译结果（`classes4.dex`）

```
PackageInstallerActivity.isInBlackList(String)Z
PackageInstallerActivity.isInWhiteList(...)Z
Utils.isInBlackList(Context,String,ApplicationInfo)Z
Utils.isApkFileCanInstall(Context,String,String)Z
```

### 校验逻辑

```
doInBackground():
  1. 文件是 BPK？
       → 必须在 3 张 厂商 证书白名单里：
         89:3E:2B:8C:1B:B6:9A:DB:DF:36:F4:0F:59:0C:62:82
         14:08:7C:E9:ED:28:A7:4F:A1:77:AA:89:14:47:57:4E
         40:59:05:EB:57:5C:99:63:4C:87:4A:EE:26:FE:E4:9D
  2. 普通 APK？
       → isInWhiteList（云端查签名）
       → 拒绝签名 E8:9B:15:8E:4B:CF:98:8E:BD:09:EB:83:F5:37:8E:87
  3. isInBlackList（云端查包名）
       → 离线时返回 true（fail-closed，一律判黑）
       → 已安装的应用跳过黑名单
```

### 关键日志

```
D BPackageInstaller: PreInstallTask B1:AB:17:34..., com.sinyee.babybus.homeland, com.example.appmarket
D BPackageInstaller: handlerScanStatus SCAN_RESULT_ALLOW_INSTALL isExistRisk = false
```

## 2. 破解：dex 三方法补丁

### 补丁策略

| 方法 | 修改 |
|---|---|
| `PackageInstallerActivity.isInBlackList(String)Z` | `const/4 v0,#0; return v0`（false）|
| `Utils.isInBlackList(Context,String,ApplicationInfo)Z` | 同上 |
| `Utils.isApkFileCanInstall(Context,String,String)Z` | `const/4 v0,#1; return v0`（true）|

### 补丁脚本：`scripts/analysis/patch_installer.py`

核心步骤：

```python
# 1. 手动解析 DEX：class_def → class_data → method code_off
# 2. code_item 结构：registers(2) ins(2) outs(2) tries(2) debug_off(4) insns_size(4) insns...
#    code_off+16 = 指令起始
# 3. 覆写第一条指令为 const/4 v0,#imm；第二条为 return v0；其余填 nop
# 4. tries_size 置 0
# 5. 修复 dex header：
#    signature = sha1(bytes[32:])
#    checksum  = adler32(bytes[12:])
```

### 补丁后处理

```bash
# DEX → APK 打包（resources.arsc 必须 STORED + 4 字节对齐，Android 13 要求）
aapt2 ...           # 或者直接 zipfile 重打包
zipalign -f 4 final.apk aligned.apk
apksigner sign --ks s8installer.keystore --min-sdk-version 33 ...
# APK → BPK（用 bpk_converter.py to-bpk）
python3 bpk_converter.py to-bpk signed.apk BPackageInstaller_new.apk
```

### 写回系统镜像

```bash
# 原地覆盖（保留 inode → 保留 xattr/owner/mode）
cat BPackageInstaller_new.apk > sysbuild/system/priv-app/BPackageInstaller/BPackageInstaller.apk
# 重建 erofs
mkfs.erofs -z lz4hc -T 0 -d 2 system_new.img sysbuild
truncate -s 3094769664 system_new.img
# 按 11 个 extent 写入 super（见 02 文档）
```

## 3. 验证

补丁成功后，安装任何 APK 时 logcat 出现：

```
D BPackageInstaller: handlerScanStatus SCAN_RESULT_ALLOW_INSTALL isExistRisk = false
```

即黑名单检查被放行。但**点击"安装"后的流程**仍受 厂商 安装器 UI 控制
（由于手势导航误触，安装窗口可能被系统返回手势取消——见 11 文档）。

## 4. 更彻底的替代方案（最终采用）

见 08 文档：**自建特权静默安装器 + 应用市场特权化**，
完全绕过 厂商 安装器，不需要用户点确认。
