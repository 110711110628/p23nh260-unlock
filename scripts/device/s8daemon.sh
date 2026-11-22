#!/system/bin/sh
# s8daemon v2: shell 域 + root uid 的调试/安装通道
# 日志双写：/data/local/tmp（必定可写） + /sdcard/Download（方便 MTP 取）
TMP=/data/local/tmp
DL=/sdcard/Download
L1=$TMP/s8daemon.log
L2=$DL/ROOT_PROOF.txt

log() {
  echo "$*" >> "$L1" 2>/dev/null
  echo "$*" >> "$L2" 2>/dev/null
}

{
  echo "=== S8DAEMON v2 start ==="
  date
  id
  getenforce
  echo "selinux ctx:"
  cat /proc/self/attr/current 2>/dev/null
} > "$L1" 2>&1
mkdir -p "$TMP" 2>/dev/null
mkdir -p "$DL/install" 2>/dev/null

# 等系统启动完成
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 150 ]; do
  sleep 2; i=$((i+1))
done
sleep 3
log "boot_completed after ${i}x2s"
cp "$L1" "$L2" 2>/dev/null

# 尝试把 adb 打开（尽力而为）
log "--- try enable adb ---"
setprop persist.sys.usb.config adb 2>>"$L1"
setprop service.adb.tcp.port 5555 2>>"$L1"
settings put global adb_enabled 1 2>>"$L1"
setprop sys.usb.config adb 2>>"$L1"
log "prop persist.sys.usb.config=$(getprop persist.sys.usb.config)"
log "prop sys.usb.config=$(getprop sys.usb.config)"

# 主循环
while true; do
  # 命令通道（两个位置都看）
  for CMD in "$DL/cmd.txt" "$TMP/cmd.txt"; do
    [ -f "$CMD" ] || continue
    RUN=$TMP/cmd.run
    cp "$CMD" "$RUN" 2>/dev/null
    rm -f "$CMD" 2>/dev/null
    {
      echo "=== RUN $(date) ==="
      echo "--- CMD ---"
      cat "$RUN" 2>/dev/null
      echo "--- OUT ---"
    } > "$TMP/cmd.out" 2>&1
    timeout 180 /system/bin/sh "$RUN" >> "$TMP/cmd.out" 2>&1
    echo "--- EXIT=$? ---" >> "$TMP/cmd.out"
    cp "$TMP/cmd.out" "$DL/cmd.out" 2>/dev/null
    mv "$RUN" "$TMP/cmd.run.done" 2>/dev/null
  done

  # 自动安装：/sdcard/Download/install/*.apk 与 /data/local/tmp/install/*.apk
  for A in "$DL/install"/*.apk "$TMP/install"/*.apk; do
    [ -f "$A" ] || continue
    {
      echo "=== INSTALL $A ==="
      date
    } >> "$L1" 2>&1
    /system/bin/cmd package install -r -d "$A" >> "$L1" 2>&1
    RC=$?
    echo "rc=$RC" >> "$L1" 2>&1
    if [ "$RC" = "0" ]; then
      mv "$A" "$A.done" 2>/dev/null
    else
      mv "$A" "$A.failed" 2>/dev/null
    fi
    cp "$L1" "$L2" 2>/dev/null
  done

  sleep 2
done
