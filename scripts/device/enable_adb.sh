#!/bin/bash
# 基于固件逆向的 ADB 解锁（TWRP 内执行）
# 依据：AdbService.systemReady 逻辑
#   adbInUsb = persist.sys.usb.config 含 "adb"
#   adb_enabled = adbInUsb ? persist.sys.test_harness : true
#   → 要开 adb 必须同时：usb.config=adb 且 test_harness=1
set -uo pipefail
A="/usr/bin/adb"
if ! $A devices -l | grep -q recovery; then echo "NOT_IN_TWRP"; exit 2; fi
echo "=========== TWRP OK ==========="

echo "=== 1. 当前状态 ==="
$A shell "ls -la /data/property/ | grep -E 'usb|test_harness|adbd' "
$A shell "cat /data/property/persist.sys.usb.config 2>/dev/null; echo; cat /data/property/persist.sys.test_harness 2>/dev/null; echo"

echo ""
echo "=== 2. 备份现有属性文件 ==="
$A shell "mkdir -p /sdcard/s8restore/props; cp -a /data/property/persist.sys.usb.config /sdcard/s8restore/props/ 2>/dev/null; cp -a /data/property/persist.sys.test_harness /sdcard/s8restore/props/ 2>/dev/null; ls /sdcard/s8restore/props/"

echo ""
echo "=== 3. 写入 persist 属性 ==="
$A shell "printf 'adb' > /data/property/persist.sys.usb.config; printf '1' > /data/property/persist.sys.test_harness"
$A shell "chown root:root /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness"
$A shell "chmod 600 /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness"
$A shell "restorecon /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness 2>/dev/null; ls -laZ /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness 2>/dev/null || ls -la /data/property/persist.sys.usb.config /data/property/persist.sys.test_harness"

echo ""
echo "=== 4. settings 里也写一份（AdbService 会覆盖，但保证一致）==="
$A pull /data/system/users/0/settings_global.xml /tmp/sg_adb.xml
python3 - <<'PY'
import re
p='/tmp/sg_adb.xml'
s=open(p,encoding='utf-8').read()
for name in ('adb_enabled','development_settings_enabled'):
    m=re.search(r'(name="'+name+r'"\s+value=")([^"]*)(")', s)
    if m:
        s = s[:m.start(2)] + '1' + s[m.end(2):]
        print(f"  settings {name} = 1")
open(p,'w',encoding='utf-8').write(s)
PY
$A push /tmp/sg_adb.xml /data/system/users/0/settings_global.xml
$A shell "chown 1000:1000 /data/system/users/0/settings_global.xml; chmod 600 /data/system/users/0/settings_global.xml; restorecon /data/system/users/0/settings_global.xml"

echo ""
echo "=== 5. 同步并重启 ==="
$A shell "sync; echo SYNCED"
$A reboot
echo REBOOTED
