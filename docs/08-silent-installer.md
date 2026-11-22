# 08 · 静默安装器（com.s8.silentinstaller）

> 目标：**无窗口、无确认、无 厂商 安装器**地安装 APK。
> 实现方式：system/product 特权应用 + PackageInstaller Session API。

## 1. 原理

```
特权应用（INSTALL_PACKAGES）提交安装 session
    → system_server 跳过"用户确认"
    → 直接 installPackageLI 安装
    → 全程无 UI
```

普通应用（如第三方应用市场）没有 INSTALL_PACKAGES，系统会强制弹出确认界面
（就是 厂商 安装器）——这就是为什么必须把它做成特权应用。

## 2. 应用设计

### 包信息
```
package: com.s8.silentinstaller
路径:    /product/priv-app/S8Installer/S8Installer.apk
权限:    INSTALL_PACKAGES, DELETE_PACKAGES, QUERY_ALL_PACKAGES,
         READ_INSTALL_SESSIONS, RECEIVE_BOOT_COMPLETED,
         REQUEST_INSTALL_PACKAGES, MANAGE_EXTERNAL_STORAGE
```

### 三个入口

| 入口 | 触发方式 | 行为 |
|---|---|---|
| `InstallerActivity` | 桌面图标 / 点 APK 文件 | 扫描目录，逐个静默安装 |
| `BootReceiver` | `BOOT_COMPLETED` / `com.s8.INSTALL` 广播 | 开机自动安装 |
| `ResultReceiver` | session 结果回调 | Toast 显示成功/失败 |

### 扫描目录
```java
new File(ctx.getExternalFilesDir(null), "install")   // 应用自己的外部目录（无需权限）
new File("/sdcard/Download/install")                 // 需要 MANAGE_EXTERNAL_STORAGE
```

### 核心代码（Installer.java）

```java
PackageInstaller pi = ctx.getPackageManager().getPackageInstaller();
PackageInstaller.SessionParams sp = new PackageInstaller.SessionParams(
        PackageInstaller.SessionParams.MODE_FULL_INSTALL);
int sid = pi.createSession(sp);
try (PackageInstaller.Session s = pi.openSession(sid)) {
    try (OutputStream out = s.openWrite("base.apk", 0, -1)) {
        // 从 URI 流式复制 APK
        s.fsync(out);
    }
    PendingIntent pi2 = PendingIntent.getBroadcast(ctx, sid, intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
    s.commit(pi2.getIntentSender());
}
```

## 3. 构建

### 工具链
```
aapt2        — 编译/链接
javac        — 编译 Java
r8.jar (d8)  — 转 dex（从 Maven 阿里云镜像下载）
zipalign 4   — 对齐
apksigner    — 签名
```

### 关键坑
1. **resources.arsc 必须 STORED 且 4 字节对齐**（Android 13 要求），
   否则安装报错：
   `Targeting R+ requires the resources.arsc of installed APKs to be stored uncompressed and aligned`
2. 构建脚本：`src/silent-installer/build_apk2.sh`

### 安装方式
```bash
# 推送到设备
adb push S8Installer.apk /data/local/tmp/
# session 安装（作为系统特权应用 → 保留 INSTALL_PACKAGES）
SIZE=$(stat -c %s S8Installer.apk)
SID=$(adb shell "pm install-create -r -S $SIZE" | grep -oE '[0-9]+' | head -1)
adb shell "pm install-write -S $SIZE $SID base /data/local/tmp/S8Installer.apk"
adb shell "pm install-commit $SID"
```

> 技巧：把 APK 作为**系统应用更新**安装（同一签名），
> 可以避免重新刷 system——系统应用更新仍保留特权权限。

## 4. 白名单配置

`/system/etc/permissions/privapp-permissions-s8installer.xml`：

```xml
<permissions>
    <privapp-permissions package="com.s8.silentinstaller">
        <permission name="android.permission.INSTALL_PACKAGES"/>
        <permission name="android.permission.DELETE_PACKAGES"/>
        <permission name="android.permission.QUERY_ALL_PACKAGES"/>
        <permission name="android.permission.READ_INSTALL_SESSIONS"/>
        <permission name="android.permission.RECEIVE_BOOT_COMPLETED"/>
        <permission name="android.permission.REQUEST_INSTALL_PACKAGES"/>
        <permission name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    </privapp-permissions>
</permissions>
```

## 5. 实测验证

```
I S8Installer: install start uri=file:///sdcard/Download/install/magisk.apk
I S8Installer: session created sid=2131412086
I S8Installer: input stream opened: java.io.FileInputStream@5d8345a
I S8Installer: wrote 10679283 bytes, fsync done
I S8Installer: commit sent session=2131412086
I S8Installer: RESULT status=0 msg=INSTALL_SUCCEEDED: Session installed pkg=com.topjohnwu.magisk
→ package:com.topjohnwu.magisk 已安装
```

系统日志：
```
D PackageManager: installPackageLI: path=/data/app/vmdl2131412086.tmp
D PackageInstallerSession: Marking session 2131412086 as applied
```

## 6. 使用方法

| 方式 | 操作 |
|---|---|
| 桌面图标 "该设备静默安装" | 点一下 = 安装 `/sdcard/Download/install/` 里的全部 APK |
| 点 APK 文件 | 选择"该设备静默安装" → 静默安装 |
| 开机自动 | APK 放进目录 → 重启自动装 |
| adb 广播 | `am broadcast -a com.s8.INSTALL -p com.s8.silentinstaller` |

## 7. 已知坑

1. **应用自己的外部目录目录所有者是 shell**（adb 创建）时应用读不了 →
   改用 `/sdcard/Download/install`（需要 MANAGE_EXTERNAL_STORAGE）
2. `MANAGE_EXTERNAL_STORAGE` 需要系统应用 + 白名单才自动授予
3. 首次启动前应用处于 stopped 状态，**广播不会送达** → 需先启动一次
