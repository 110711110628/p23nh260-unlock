#!/bin/bash
# ============ 一次重启全搞定 ============
# ① 刷 product_v3（root 通道守护进程）
# ② persist 属性 → ADB 解锁
# ③ 组件精准开关（恢复商店/护眼/绿网；禁 OTA/Settings/白名单/安全管理）
# ④ 建自动安装目录（用户自己放 APK）
# ⑤ 重启
set -uo pipefail
A="/usr/bin/adb"
IMG=/root/s8/product_v3.img
SRC_SHA=723f6ea7122766435ea1794ed756d46c3f4a5ea0cd46b33044b33a816a039648
SEEK=13498368
COUNT=307072

if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "================= TWRP OK ================="

# ---------- 0. 前置检查 ----------
SZ=$(stat -c %s "$IMG")
REAL=$(sha256sum "$IMG" | awk '{print $1}')
echo "[0] product_v3: size=$SZ sha=${REAL:0:16}..."
[ "$SZ" = "157220864" ] || { echo "!! 镜像大小不符"; exit 1; }
[ "$REAL" = "$SRC_SHA" ] || { echo "!! 镜像哈希不符"; exit 1; }

# ---------- 1. 备份（全部可回滚） ----------
echo "[1] 备份..."
$A shell "mkdir -p /sdcard/s8restore/props /sdcard/s8restore/sys"
$A shell "cp -a /data/system/users/0/package-restrictions.xml /sdcard/s8restore/sys/pr.xml 2>/dev/null"
$A shell "cp -a /data/system/users/0/settings_global.xml /sdcard/s8restore/sys/sg.xml 2>/dev/null"
$A shell "cp -a /data/property/persist.sys.usb.config /sdcard/s8restore/props/ 2>/dev/null"
$A shell "cp -a /data/property/persist.sys.test_harness /sdcard/s8restore/props/ 2>/dev/null"
$A shell "dd if=/dev/block/by-name/super of=/sdcard/s8restore/product_orig.img bs=1M skip=6591 count=150 2>/dev/null"
echo "    备份完成: /sdcard/s8restore/"

# ---------- 2. 刷 product_v3（带偏移三重校验） ----------
echo "[2] 刷 product_v3..."
$A push /root/s8/product_a.img /tmp/orig_product.img >/dev/null 2>&1
$A shell "dd if=/dev/block/by-name/super of=/tmp/pre1m.bin bs=1M skip=6591 count=1 2>/dev/null"
M1=$($A shell "head -c 1048576 /tmp/orig_product.img | md5sum" | awk '{print $1}')
M2=$($A shell "md5sum /tmp/pre1m.bin" | awk '{print $1}')
echo "    偏移校验: orig=$M1 dev=$M2"
[ "$M1" = "$M2" ] || { echo "!! 偏移校验失败，中止（未写任何分区）"; exit 1; }
$A push "$IMG" /tmp/product_v3.img || exit 1
$A shell "dd if=/tmp/product_v3.img of=/dev/block/by-name/super bs=512 seek=$SEEK count=$COUNT conv=notrunc 2>&1 | tail -1"
BACK=$($A shell "dd if=/dev/block/by-name/super of=/tmp/post.bin bs=512 skip=$SEEK count=$COUNT 2>/dev/null; sha256sum /tmp/post.bin" | awk '{print $1}')
echo "    回读: ${BACK:0:16}... 期望: ${SRC_SHA:0:16}..."
[ "$BACK" = "$SRC_SHA" ] || { echo "!! 回读不一致（可执行 restore_product.sh 回滚）"; exit 1; }
echo "    product 写入成功 ✓"

# ---------- 3. persist 属性（ADB 解锁关键） ----------
echo "[3] persist 属性..."
$A shell "printf 'adb' > /data/property/persist.sys.usb.config"
$A shell "printf '1' > /data/property/persist.sys.test_harness"
$A shell "chown root:root /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness"
$A shell "chmod 600 /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness"
$A shell "restorecon /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness 2>/dev/null"
echo "    usb.config=$(  $A shell "cat /data/property/persist.sys.usb.config" )"
echo "    test_harness=$( $A shell "cat /data/property/persist.sys.test_harness" )"

# ---------- 4. 组件精准开关 ----------
echo "[4] 组件开关..."
$A pull /data/system/users/0/package-restrictions.xml /tmp/pr.xml
python3 - <<'PY'
import re
p='/tmp/pr.xml'
data=open(p,encoding='utf-8').read()
ENABLE = ["com.eebbk.bbkmiddlemarket","com.eebbk.ovumserver","com.eebbk.greensecuritymidware"]
DISABLE = ["com.eebbk.bbkallowlisting","com.eebbk.padsecuritymanager",
           "com.eebbk.tools.otaupdate","com.android.settings"]
def find(data,pkg):
    return re.search(r'(<pkg name="'+re.escape(pkg)+r'")([^>]*?)(\s*/?>)', data)
for pkg in ENABLE:
    m=find(data,pkg)
    if not m: print("  [恢复]",pkg,"(不在文件)"); continue
    if 'enabled="2"' in m.group(2):
        data=data[:m.start()]+m.group(1)+m.group(2).replace(' enabled="2"','')+m.group(3)+data[m.end():]
        print("  [恢复]",pkg)
    else: print("  [恢复]",pkg,"(已启用)")
for pkg in DISABLE:
    m=find(data,pkg)
    if m:
        attrs=m.group(2)
        attrs = re.sub(r' enabled="[^"]*"','',attrs)
        data=data[:m.start()]+m.group(1)+attrs+' enabled="2"'+m.group(3)+data[m.end():]
        print("  [禁用]",pkg)
    else:
        data=data.replace("</package-restrictions>", '\n    <pkg name="'+pkg+'" enabled="2" />\n</package-restrictions>')
        print("  [禁用]",pkg,"(新增)")
open(p,'w',encoding='utf-8').write(data)
PY
$A push /tmp/pr.xml /data/system/users/0/package-restrictions.xml

# ---------- 5. settings ----------
echo "[5] settings..."
$A pull /data/system/users/0/settings_global.xml /tmp/sg.xml
python3 - <<'PY'
import re
p='/tmp/sg.xml'
s=open(p,encoding='utf-8').read()
for name in ("adb_enabled","development_settings_enabled"):
    m=re.search(r'(name="'+name+r'"\s+value=")([^"]*)(")', s)
    if m:
        s=s[:m.start(2)]+'1'+s[m.end(2):]
        print("  ",name,"= 1")
open(p,'w',encoding='utf-8').write(s)
PY
$A push /tmp/sg.xml /data/system/users/0/settings_global.xml
$A shell "chown 1000:1000 /data/system/users/0/package-restrictions.xml /data/system/users/0/settings_global.xml"
$A shell "chmod 600 /data/system/users/0/package-restrictions.xml /data/system/users/0/settings_global.xml"
$A shell "restorecon /data/system/users/0/package-restrictions.xml /data/system/users/0/settings_global.xml 2>/dev/null"

# ---------- 6. 自动安装目录 ----------
echo "[6] 建自动安装目录..."
$A shell "mkdir -p /sdcard/Download/install; ls -la /sdcard/Download/ | head -5"

# ---------- 7. sync + reboot ----------
echo "[7] sync + reboot..."
$A shell "sync; echo SYNCED"
$A reboot
echo "================= REBOOTED ================="
