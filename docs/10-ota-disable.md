# 10 · OTA 单独禁用

## 为什么单独禁用 OTA

OTA 会**重写 boot/vendor_boot/system/uboot**：
- 我们的 adb 解锁（product rc）会被覆盖
- 安装器 dex 补丁会被还原
- 应用市场特权化会失效
- 若 OTA 更新 uboot，BL 解锁补丁可能丢失 → 需要重新走 BROM

但设备上的**学习应用/资料推送**是走各应用自己的服务，与 OTA 无关。

## 操作

```bash
# 只禁用 OTA 应用（一个包，不影响其他）
adb shell pm disable-user --user 0 com.vendor.tools.otaupdate
```

验证：

```
$ adb shell dumpsys package com.vendor.tools.otaupdate | grep 'User 0:'
User 0: ... enabled=3 ...    ← 3 = DISABLED_USER
```

## 为什么 `pm disable-user` 能生效（而 pm enable 不行）

- `pm disable-user` 对系统应用有效（shell 有权限）
- `pm enable` 对某些系统应用会报
  `Shell cannot change component state for null to 1`
  ——此时需要直接改 `/data/system/users/0/package-restrictions.xml`
  （TWRP 里改 `enabled="2"` → `enabled="1"`）

## 相关包一览（管控类，可按需禁用）

| 包名 | 作用 | 建议 |
|---|---|---|
| `com.vendor.tools.otaupdate` | OTA | **禁用** |
| `com.vendor.parentsupport` | 家长监管（应用禁用弹窗） | 禁用（否则第三方应用无法启动）|
| `com.vendor.bbkallowlisting` | 白名单云控 | 禁用 |
| `com.vendor.padsecuritymanager` | 安全管理 | 禁用 |
| `com.vendor.ovumserver` | 护眼/网课/URL 拦截 | 禁用 |
| `com.vendor.greensecuritymidware` | 绿网 | 禁用 |
| `com.vendor.bbkmiddlemarket` | 厂商商店 | 保留或禁用（自选）|
| 学习类应用 | 同步/英语/数学等 | **保留** |

## 风险提示

- 禁用 `com.vendor.parentsupport` 后，**家长管控功能失效**（这是目的）
- 禁用监管类应用可能涉及当地法规（未成年人保护相关），请自行判断
- OTA 禁用后不会收到系统更新（安全补丁也不会）
