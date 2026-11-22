# 09 · 应用市场特权化（第三方应用市场静默安装）

## 1. 问题

第三方应用市场（`com.example.appmarket`）是普通用户应用，**没有 INSTALL_PACKAGES**。
它安装应用时必须走 PackageInstaller session → 系统强制"用户确认" → 弹出 **厂商 安装器**。

## 2. 解法：把应用市场变成系统特权应用

### 步骤

1. **把 APK 放入系统分区**：`/system/priv-app/HuaweiAppGallery/HuaweiAppGallery.apk`
   - product 分区已满（148M/149.9MB），只能用 system（3GB，有 ~58MB 空闲）
   - AppGallery APK 60.3MB，刚好塞得下
2. **加特权权限白名单**：`/system/etc/permissions/privapp-permissions-huawei.xml`

```xml
<permissions>
    <privapp-permissions package="com.example.appmarket">
        <permission name="android.permission.INSTALL_PACKAGES"/>
        <permission name="android.permission.DELETE_PACKAGES"/>
        <permission name="android.permission.QUERY_ALL_PACKAGES"/>
        <permission name="android.permission.READ_INSTALL_SESSIONS"/>
        <permission name="android.permission.RECEIVE_BOOT_COMPLETED"/>
        <permission name="android.permission.REQUEST_INSTALL_PACKAGES"/>
        <permission name="android.permission.WRITE_SECURE_SETTINGS"/>
        <permission name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    </privapp-permissions>
</permissions>
```

3. **重建 system 镜像**（注意 erofs 特性与 xattr 保留）
4. **刷入**
5. 重启后验证

### 验证

```
$ adb shell dumpsys package com.example.appmarket | grep -E 'pkgFlags|INSTALL_PACKAGES'
pkgFlags=[ SYSTEM HAS_CODE ALLOW_CLEAR_USER_DATA UPDATED_SYSTEM_APP LARGE_HEAP ]
android.permission.INSTALL_PACKAGES: granted=true   ← 关键
```

### 实测效果

从应用市场安装应用后 logcat：

```
PackageInstallerSession: com.example.appmarket ... com.fenbi.android.solar
PackageInstallerSession: Marking session 2050153302 as applied
PackageManager: installPackageLI: path=/data/app/vmdl1303524033.tmp
PackageInstallerSession: Marking session 1303524033 as applied
```

**厂商 安装器调用记录 = 0 次** ✓（完全静默，无弹窗）

## 3. 空间问题与取舍

| 分区 | 总大小 | 已用 | 可用 | 结论 |
|---|---|---|---|---|
| product | 149.9MB | 148MB | ~1.9MB | ✗ 放不下 |
| system | 2.95GB | ~2.89GB | ~58MB | ✓ 放得下 60MB APK |
| system_ext | 319.7MB | 满 | 0 | ✗ |

> 如果要在 product 放，需要删除 product 里其他 60MB+ 的内容（没有）。

## 4. 桌面图标清理

刷完后桌面出现 **3 个**"应用市场"图标：

| 图标 | Activity | 说明 |
|---|---|---|
| 第三方应用市场 | `com.example.appmarket/.MainActivity` | 保留 |
| 厂商游戏中心 | `com.example.appmarket/.GameBoxActivity` | 同一 APK 的第二个入口 |
| 厂商应用商店 | `com.vendor.bbkmiddlemarket/.WelComeActivity` | 昨晚恢复的 |

清理方法（可选）：

```bash
# 禁用组件（shell 可执行）
adb shell pm disable-user --user 0 com.example.appmarket/com.huawei.gamebox.GameBoxActivity
# 或禁用整个厂商商店
adb shell pm disable-user --user 0 com.vendor.bbkmiddlemarket
```

## 5. 相关脚本

- `scripts/build/build_system_v3.sh` — 构建含应用市场的 system 镜像
- `scripts/flash/flash_system_v3.sh` — 刷入（11 extent 写入 + 逐段校验）

## 6. 结论

> **把商店变成特权应用 = 商店自己就能静默安装，不需要我们写任何安装器。**
> 这是最省事的方案——之前写静默安装器是因为商店路线被堵死，
> 现在两条路都通了（商店 + 本地 APK 安装器）。
