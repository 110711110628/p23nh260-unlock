#!/bin/bash
# 精准管控：恢复误伤组件 + 只禁 OTA 与系统设置（阻止云控重置 adb）
# 依据：BPackageInstaller 逆向（黑名单云端判定 + 离线 fail-closed）
set -uo pipefail
A="/usr/bin/adb"
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "=========== TWRP OK ==========="

PR=/tmp/pr.xml
SG=/tmp/sg.xml
$A pull /data/system/users/0/package-restrictions.xml $PR || exit 1
$A pull /data/system/users/0/settings_global.xml $SG || exit 1
cp $PR /root/s8/pr_before_fine.xml
cp $SG /root/s8/sg_before_fine.xml
echo "已备份到 /root/s8/pr_before_fine.xml, sg_before_fine.xml"

python3 - "$PR" "$SG" <<'PYEOF'
import re, sys

pr_path, sg_path = sys.argv[1], sys.argv[2]
data = open(pr_path, encoding="utf-8").read()

# 要恢复的（误伤）：enabled="2" -> 移除
ENABLE = ["com.eebbk.bbkmiddlemarket",      # 应用商店
          "com.eebbk.ovumserver",           # 护眼/网课服务
          "com.eebbk.greensecuritymidware"] # 绿网

# 要禁用的（精准打击）
DISABLE = ["com.eebbk.bbkallowlisting",     # 白名单/管控
           "com.eebbk.padsecuritymanager",  # 家长管控
           "com.eebbk.tools.otaupdate",     # ★OTA 升级（防止白干）
           "com.android.settings"]          # 系统设置（云控重置 adb 的执行者）

def find_pkg(data, pkg):
    pat = re.compile(r'(<pkg name="' + re.escape(pkg) + r'")([^>]*?)(\s*/?>)')
    return pat.search(data)

# 恢复
for pkg in ENABLE:
    m = find_pkg(data, pkg)
    if not m:
        print(f"  [恢复] {pkg}: 不在文件里（系统可能默认启用）")
        continue
    attrs = m.group(2)
    if 'enabled="2"' in attrs:
        new_attrs = attrs.replace(' enabled="2"', '')
        data = data[:m.start()] + m.group(1) + new_attrs + m.group(3) + data[m.end():]
        print(f"  [恢复] {pkg}: 已移除 enabled=2")
    else:
        print(f"  [恢复] {pkg}: 本来就是启用状态")

# 禁用
for pkg in DISABLE:
    m = find_pkg(data, pkg)
    if m:
        attrs = m.group(2)
        if 'enabled=' in attrs:
            new_attrs = re.sub(r' enabled="[^"]*"', ' enabled="2"', attrs)
            data = data[:m.start()] + m.group(1) + new_attrs + m.group(3) + data[m.end():]
            print(f"  [禁用] {pkg}: 改为 enabled=2")
        else:
            data = data[:m.start()] + m.group(1) + attrs + ' enabled="2"' + m.group(3) + data[m.end():]
            print(f"  [禁用] {pkg}: 新增 enabled=2")
    else:
        ins = f'\n    <pkg name="{pkg}" enabled="2" />'
        data = data.replace("</package-restrictions>", ins + "\n</package-restrictions>")
        print(f"  [禁用] {pkg}: 插入新条目")

open(pr_path, "w", encoding="utf-8").write(data)

# settings: adb_enabled + development_settings_enabled
sg = open(sg_path, encoding="utf-8").read()
for name in ("adb_enabled", "development_settings_enabled"):
    m = re.search(r'(name="' + name + r'"\s+value=")([^"]*)(")', sg)
    if m:
        sg = sg[:m.start(2)] + "1" + sg[m.end(2):]
        print(f"  [settings] {name} = 1")
    else:
        print(f"  [settings] {name}: 不存在（跳过）")
open(sg_path, "w", encoding="utf-8").write(sg)
PYEOF

echo ""
echo "=== 写回设备 ==="
$A push $PR /data/system/users/0/package-restrictions.xml || exit 1
$A push $SG /data/system/users/0/settings_global.xml || exit 1
$A shell "chown 1000:1000 /data/system/users/0/package-restrictions.xml /data/system/users/0/settings_global.xml; chmod 600 /data/system/users/0/package-restrictions.xml /data/system/users/0/settings_global.xml; restorecon /data/system/users/0/package-restrictions.xml /data/system/users/0/settings_global.xml; sync"

echo ""
echo "=== 核对 ==="
$A shell "grep -oE '<pkg name=\"[^\"]*\"[^>]*enabled=\"2\"[^>]*>' /data/system/users/0/package-restrictions.xml | grep -oE 'name=\"[^\"]*\"' | head -20"
echo "--- settings ---"
$A shell "grep -oE 'name=\"(adb_enabled|development_settings_enabled)\"[^/]*' /data/system/users/0/settings_global.xml"
echo ""
echo "=== 重启 ==="
$A reboot
echo REBOOTED
