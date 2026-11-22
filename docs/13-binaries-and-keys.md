# 13 · 二进制与密钥的获取方式（不含任何厂商文件）

> 本仓库**不包含**任何厂商二进制、镜像、密钥、证书。
> 所有二进制都从**你自己的设备**上读取；所有密钥都在**你自己的电脑**上生成。

## 1. 需要哪些二进制

| 文件 | 用途 | 来源 |
|---|---|---|
| `boot_a.img` / `vendor_boot_a.img` | 引导链修改、TWRP | **自己的设备 dump** |
| `super.bin`（含 system/product 等） | 系统修改、回滚 | **自己的设备 dump** |
| `system_a.img` / `product_a.img` | 分区重建 | 从 super dump 中提取 |
| TWRP（vendor_boot 用） | root 恢复环境 | 官方/自编译 |
| `spd_dump` | 展锐 BROM 读写 | GitHub（开源） |
| `mtkclient` | MTK 设备备用工具 | GitHub（开源） |
| `android.jar`（API 33） | 编译 APK | Android SDK platform |
| `r8.jar` | dex 编译 | Google Maven / Maven 镜像 |
| 签名密钥 | 重签安装器 | **自己 keytool 生成** |

## 2. 从自己的设备 dump 分区

### 方式 A：TWRP（推荐，简单）

```bash
adb shell "dd if=/dev/block/by-name/boot_a        of=/sdcard/boot_a.img bs=1M count=64"
adb shell "dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot.img bs=1M count=100"
adb shell "dd if=/dev/block/by-name/super         of=/sdcard/super.bin"
adb pull /sdcard/boot_a.img
```

### 方式 B：BROM（设备已变砖时唯一手段）

```bash
# 1. 设备进 BROM（关机，按住音量键，插 USB）
# 2. spd_dump 读取
spd_dump --wait 300 read_flash 0 0x.... boot_a.img
# 3. 或者用 mtkclient（MTK 设备）
python mtk.py r boot_a boot_a.img
```

### 方式 C：从 super 镜像提取逻辑分区

```bash
# super 是 liblp 格式：magic 0x414C5030 @ 0x3000
# 用 lpunpack 或自写解析器提取 system_a/product_a 等
lpunpack super.bin out/
```

## 3. 需要 dump 的分区清单

| 分区 | 大小参考 | 说明 |
|---|---|---|
| boot_a | 32-64MB | 引导镜像 |
| vendor_boot_a | 64-100MB | TWRP / 厂商 ramdisk |
| init_boot_a | 8MB | Android 13 新分区（可能为空）|
| vbmeta_a / vbmeta_system_a / vbmeta_vendor_a | 8MB | AVB 元数据 |
| super | 4-8GB | 系统所有逻辑分区 |
| metadata | 小 | 调试标记 |

> **先备份再动手**：所有改动前先 dump 一份完整备份，写回时逐段校验。

## 4. 密钥：自己生成

```bash
keytool -genkeypair -v \
  -keystore my-installer.keystore -alias installer \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <YOUR_KEYSTORE_PASS> -keypass <YOUR_KEYSTORE_PASS> \
  -dname "CN=My Installer, OU=mod, O=me, L=x, ST=x, C=CN"
```

然后用 apksigner 签名：

```bash
apksigner sign --ks my-installer.keystore \
  --ks-pass pass:<YOUR_KEYSTORE_PASS> \
  --key-pass pass:<YOUR_KEYSTORE_PASS> \
  --min-sdk-version 33 --out signed.apk aligned.apk
```

> 自签密钥只对你自己的设备有效（系统应用特权来自 priv-app 白名单，
> 不要求平台签名）。

## 5. 工具链安装（Linux/Ubuntu 示例）

```bash
# 基础
sudo apt install -y openjdk-17-jdk aapt2 apksigner zipalign zip lz4 erofs-utils
# android.jar（API 33）
curl -sSL -o platform33.zip "https://dl.google.com/android/repository/platform-33_r02.zip"
unzip -q platform33.zip            # → android-13/android.jar
# r8/d8（dex 编译）
curl -sSL -o r8.jar "https://maven.aliyun.com/repository/google/com/android/tools/r8/8.3.37/r8-8.3.37.jar"
# spd_dump
git clone https://github.com/TomKing062/spd_dump.git && make
# mtkclient（MTK 备用）
pip install git+https://github.com/bkerler/mtkclient
```

## 6. 合规说明

- 本仓库**不提供**任何厂商的镜像/密钥/证书下载链接
- 所有二进制应来自**你拥有所有权的设备**
- 请勿传播厂商固件；如需救砖，优先使用自己提前做的备份
