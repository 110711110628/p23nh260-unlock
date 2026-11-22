#!/system/bin/sh
# s8root: 开机即运行的 root 命令守护进程
LOG=/data/local/tmp/s8root.log
CMD=/data/local/tmp/s8cmd.sh
OUT=/data/local/tmp/s8cmd.out
PIDF=/data/local/tmp/s8root.pid
mkdir -p /data/local/tmp 2>/dev/null

# 防重复实例
if [ -f "$PIDF" ]; then
  OLD=$(cat "$PIDF" 2>/dev/null)
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    exit 0
  fi
fi
echo $$ > "$PIDF"

{
  echo "=== s8root started $(date) ==="
  echo "uid=$(id -u) ctx=$(cat /proc/self/attr/current 2>/dev/null)"
  echo "getenforce=$(getenforce 2>/dev/null)"
} >> $LOG 2>&1

# 顺手确保 adb / 开发设置开着
setprop persist.sys.usb.config mtp,adb 2>/dev/null
settings put global adb_enabled 1 2>/dev/null

while true; do
  if [ -f "$CMD" ]; then
    mv "$CMD" "$CMD.run" 2>/dev/null
    {
      echo "=== RUN $(date) uid=$(id -u) ==="
      /system/bin/sh "$CMD.run" 2>&1
      echo "=== EXIT=$? ==="
    } >> $OUT 2>&1
    rm -f "$CMD.run"
  fi
  sleep 2
done
