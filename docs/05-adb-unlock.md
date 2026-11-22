# 05 · ADB 持久解锁

## 问题：为什么 adb 默认没有？

厂商 设计了三重 adb 锁：

### 1. init 层：`bbk_check_adb` 文件检查

`/system/bin/init`（2,278,280 字节，厂商 定制版）里有：

```c
if (access("/mnt/vendor/bbk_check_adb", F_OK) == 0)
    append_prop("persist.sys.usb.config", ",adb");
```

即：只有存在一个**特殊文件**时才把 adb 加进 USB 配置。

### 2. 框架层：AdbService 重写

`services.jar` 中 `AdbService.systemReady()`（phase 550）：

```java
boolean adbInUsb = containsFunction(persist.sys.usb.config, "adb");
boolean r = adbInUsb ? getBoolean("persist.sys.test_harness", false) : true;
Settings.Global.putInt("adb_enabled", r ? 1 : 0);
```

即：如果 USB 配置里有 adb，则**必须同时有 test_harness=1**，否则把 `adb_enabled` 写回 0。

### 3. 云端层：`pm install` 远程授权

`PackageManagerShellCommand.runinstall()` 前调用 `getRemoteUsbState()`，
云端不同意则拒绝 pm 安装（见 07）。

## 我们的解法：product 分区 rc + 属性

**核心思路**：不碰系统，只在 product 分区（150MB，可快速刷写）加一个 init rc，
在每次开机时强制设置属性。

### product 分区内容

```
/product/etc/init/s8daemon.rc:
------------------------------------------------
on boot
    write /metadata/rc_test_parsed 1          # 调试标记（证明 rc 被解析）
    setprop persist.sys.usb.config adb
    setprop sys.usb.config adb                # 关键：直接触发 adbd
    exec_background - root root -- /system/bin/sh -c "..."
------------------------------------------------
```

### 为什么直接 `setprop sys.usb.config adb` 就能起 adbd

`/system/etc/init/hw/init.usb.rc` 和 `init.usb.configfs.rc` 里有触发器：

```
on property:sys.usb.config=adb && property:sys.usb.configfs=1
    start adbd
```

正常流程是 UsbDeviceManager（Java）在运行时设置这个属性；
我们绕过它，让 init 在 boot 阶段直接设置 → adbd 启动 ✓

### 配套属性（/data/property/ 下写文件）

| 文件 | 值 | 作用 |
|---|---|---|
| `persist.sys.test_harness` | `1` | 让 AdbService 放行 adb_enabled |
| `persist.sys.usb.config` | `mtp,adb` 或 `adb` | USB 双功能 |
| `persist.sys.cmdservice.enable` | `enable` | 启用官方 root 命令服务（可选） |

> 注意：只设 `persist.sys.usb.config=adb` 而不设 `test_harness=1` 时，
> `AdbService` 会把 `adb_enabled` 重置为 0（我们实测确认）。

## 验证

```bash
adb devices
# 7NH2…   device usb:3-3 product:ums9620_2h10_h260_native model:该设备
adb shell getprop sys.usb.config   # mtp,adb
adb shell getprop init.svc.adbd    # running
adb shell id                       # uid=2000(shell)
```

## 注意事项

- device 识别为 `1782:4002`（Unisoc adb 模式）；MTP-only 时是 `1782:4001`
- adb 认证用 RSA 密钥（`/data/misc/adb/adb_keys`），首次需授权
- `adb root` **不可用**（`ro.debuggable=0`，生产版 adbd 拒绝 root）
- 修改 product 后必须 `mkfs.erofs -z lz4hc` 重建并保持 `feature_incompat=0x1`、
  所有文件的 `security.selinux` xattr 不变

## 相关脚本

- `scripts/build/build_product_v7.sh` — 构建含 adb rc 的 product 镜像
- `scripts/flash/flash_v7.sh` — 刷入（product 在 super 内偏移 13498368）
- `scripts/build/rebuild_installer.sh` — 同一套 product 构建流程的参考
