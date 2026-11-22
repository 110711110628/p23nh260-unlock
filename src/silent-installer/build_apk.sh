#!/bin/bash
# 鏋勫缓 S8 闈欓粯瀹夎鍣?APK
set -e
cd /root/s8/silent
SRC=src
OUT=build
rm -rf $OUT && mkdir -p $OUT/classes $OUT/dex

ANDROID_JAR=$(find /root/s8/silent -name "android.jar" | head -1)
[ -z "$ANDROID_JAR" ] && { echo "鎵句笉鍒?android.jar"; exit 1; }
echo "android.jar: $ANDROID_JAR"

echo "=== 1. javac ==="
javac -source 8 -target 8 -bootclasspath "$ANDROID_JAR" -d $OUT/classes \
  $SRC/com/s8/silentinstaller/*.java 2>&1 | grep -v "^warning:" | head -10
echo "class 鏂囦欢: $(find $OUT/classes -name '*.class' | wc -l)"

echo "=== 2. d8 -> dex ==="
java -cp /root/s8/silent/r8.jar com.android.tools.r8.D8 \
  --min-api 33 --output $OUT/dex $(find $OUT/classes -name '*.class') 2>&1 | head -5
ls -la $OUT/dex/classes.dex

echo "=== 3. aapt2 缂栬瘧骞堕摼鎺?APK ==="
aapt2 compile --dir res -o $OUT/ 2>/dev/null || true
aapt2 link -o $OUT/base.apk -I "$ANDROID_JAR" --manifest AndroidManifest.xml 2>&1 | head -5
[ -f $OUT/base.apk ] || { echo "aapt2 link 澶辫触"; exit 1; }
ls -la $OUT/base.apk

echo "=== 4. 鍔犲叆 classes.dex ==="
cd $OUT && mkdir -p zip && cd zip
unzip -o -q ../base.apk
cp ../dex/classes.dex .
zip -q -r ../final.apk .
cd ..
ls -la final.apk

echo "=== 5. zipalign + 绛惧悕 ==="
zipalign -f 4 final.apk aligned.apk
apksigner sign --ks /root/s8/patcher/s8installer.keystore --ks-pass pass:<YOUR_KEYSTORE_PASS> \
  --key-pass pass:<YOUR_KEYSTORE_PASS> --min-sdk-version 33 --out S8Installer.apk aligned.apk 2>&1 | head -3
ls -la S8Installer.apk

echo "=== 6. 楠岃瘉 ==="
aapt2 dump badging S8Installer.apk 2>/dev/null | grep -E "^package:|application-label" | head -2
apksigner verify --print-certs S8Installer.apk 2>&1 | head -3
echo BUILD_APK_DONE
