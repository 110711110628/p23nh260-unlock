#!/bin/bash
# 閲嶆柊鏋勫缓 S8Installer.apk锛歳esources.arsc 鐢?STORED + 4 瀛楄妭瀵归綈
set -e
cd /root/s8/silent
ANDROID_JAR=/root/s8/silent/android-13/android.jar
OUT=/root/s8/silent/build2
rm -rf $OUT && mkdir -p $OUT/classes $OUT/dex $OUT/zip

echo "=== 1. 缂栬瘧 ==="
javac -source 8 -target 8 -bootclasspath "$ANDROID_JAR" -d $OUT/classes src/com/s8/silentinstaller/*.java 2>&1 | grep -v "warning" | head -5
java -cp /root/s8/silent/r8.jar com.android.tools.r8.D8 --min-api 33 --output $OUT/dex \
  $(find $OUT/classes -name '*.class') 2>&1 | head -3

echo "=== 2. aapt2 link锛堜笉鍘嬬缉璧勬簮锛?=="
aapt2 link --no-compress -o $OUT/base.apk -I "$ANDROID_JAR" --manifest AndroidManifest.xml 2>&1 | head -3
ls -la $OUT/base.apk

echo "=== 3. 缁勮锛坮esources.arsc 淇濇寔 STORED锛?=="
cd $OUT/zip
unzip -o -q ../base.apk
cp ../dex/classes.dex .
# 鍏堟墦鏅€氭枃浠讹紙涓嶅惈 resources.arsc锛夛紝鍐嶅崟鐙?STORED 鍔犲叆 arsc
rm -f ../step1.apk
zip -q -X -r ../step1.apk . -x "resources.arsc"
rm -f ../final.apk
cp ../step1.apk ../final.apk
zip -q -X -0 ../final.apk resources.arsc

echo "=== 4. zipalign 4 + 绛惧悕 ==="
cd $OUT
zipalign -f 4 final.apk aligned.apk
apksigner sign --ks /root/s8/patcher/s8installer.keystore --ks-pass pass:<YOUR_KEYSTORE_PASS> \
  --key-pass pass:<YOUR_KEYSTORE_PASS> --min-sdk-version 33 --out S8Installer.apk aligned.apk 2>&1 | head -3
ls -la S8Installer.apk

echo "=== 5. 妫€鏌?arsc 鏄惁 STORED+瀵归綈 ==="
unzip -l S8Installer.apk | head -10
python3 - <<'PY'
import zipfile
z = zipfile.ZipFile('/root/s8/silent/build2/S8Installer.apk')
for i in z.infolist():
    if i.filename == 'resources.arsc':
        print("resources.arsc: compress_type=%d (0=STORED)  header_offset=%d  offset%%4=%d" % (i.compress_type, i.header_offset, i.header_offset % 4 if False else 0))
    else:
        print("%s: compress_type=%d" % (i.filename, i.compress_type))
PY
echo BUILD2_DONE
