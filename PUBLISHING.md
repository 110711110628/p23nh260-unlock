# 发布到 GitHub 指南

## 方式一：上传 ZIP（最简单，无需 git）

1. 把整个 `s8-unlock` 文件夹压缩成 zip
2. 打开 https://github.com/new 创建仓库（建议名：`bbk-s8-unlock`）
3. 创建后点 **uploading an existing file** 上传解压后的文件
4. 提交

## 方式二：安装 git 后命令行推送

```powershell
# 1. 安装 git（Windows）
winget install --id Git.Git -e

# 2. 进入目录
cd <你的路径>\s8-unlock

# 3. 初始化并提交
git init
git add .
git commit -m "P23NH260 学习平板 (Android 13) 逆向解锁记录"

# 4. 关联远程仓库（先在 GitHub 建好空仓库）
git branch -M main
git remote add origin https://github.com/<你的用户名>/bbk-s8-unlock.git
git push -u origin main
```

## 发布前检查清单

- [ ] 不含设备序列号/账号/密码（已脱敏）
- [ ] 不含厂商专有二进制（APK/镜像/密钥）——`.gitignore` 已排除
- [ ] 不含自己的 keystore 私钥（构建脚本用 `<YOUR_KEYSTORE_PASS>` 占位）
- [ ] DISCLAIMER.md 已包含
- [ ] README 中的链接有效

## 生成自己的签名密钥（静默安装器需要）

```bash
keytool -genkeypair -v -keystore my.keystore -alias mykey \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <YOUR_KEYSTORE_PASS> -keypass <YOUR_KEYSTORE_PASS> \
  -dname "CN=My Installer, OU=mod, O=me, L=x, ST=x, C=CN"
```

然后修改 `src/silent-installer/build_apk2.sh` 中的 keystore 路径与密码。

## 仓库建议配置

- **About** 描述：
  `P23NH260 学习平板 (Android 13) 学习机逆向解锁：ADB 持久解锁 / root 通道 / 静默安装器 / 商店特权化`
- **Topics**：`android` `reverse-engineering` `unisoc` `bbk` `adb` `android-13` `exploit` `root`
- **Releases**：可以把 `S8Installer.apk` 作为 release 附件（不要放在 git 历史里）
- **License**：MIT

## 合规提醒

发布前请确认：
1. 内容仅用于技术研究
2. DISCLAIMER 明确"仅供自有设备研究、禁止破解他人设备"
3. 不包含任何厂商专有代码/二进制/密钥
4. 不包含用户个人数据
