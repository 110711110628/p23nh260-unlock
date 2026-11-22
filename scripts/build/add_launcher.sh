#!/bin/bash
# 给静默安装器加桌面图标（LAUNCHER），然后重建
set -e
cd /root/s8/silent
python3 - <<'PY'
p = '/root/s8/silent/AndroidManifest.xml'
s = open(p).read()
if 'android.intent.category.LAUNCHER' not in s:
    # 在 activity 的第一个 intent-filter 后加入 LAUNCHER filter
    anchor = '''            <intent-filter android:priority="1000">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="application/vnd.android.package-archive" />
            </intent-filter>'''
    add = anchor + '''
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>'''
    if anchor in s:
        s = s.replace(anchor, add, 1)
        open(p, 'w').write(s)
        print("已加 LAUNCHER 图标")
    else:
        print("锚点未找到，手动检查")
        print(s[:800])
else:
    print("已有 LAUNCHER")
PY
echo ""
echo "=== 重建 ==="
bash build_apk2.sh 2>&1 | tail -3
ls -la build2/S8Installer.apk
echo ""
echo "=== 验证 launcher ==="
aapt2 dump badging build2/S8Installer.apk 2>/dev/null | grep -E "launchable|package:" | head -3
