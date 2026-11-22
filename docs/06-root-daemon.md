# 06 · root 命令通道

> 目标：正常系统里获得一个**持久 root 执行通道**（不依赖 TWRP）。

## 方案：system/etc/init 里的 init 服务

厂商 的 init 会解析 `/system/etc/init/*.rc`，因此我们在 system 镜像里加：

### `/system/etc/init/s8root.rc`

```rc
service s8root /system/bin/sh /system/etc/s8root.sh
    class core
    user root
    group root system shell
    seclabel u:r:shell:s0
    disabled

on boot
    start s8root
    exec_background - root root -- /system/bin/sh /system/etc/s8root.sh
    write /metadata/s8root_rc_parsed 1
```

关键点：
- `user root` → uid 0
- `seclabel u:r:shell:s0` → 运行在 **shell 域**（init→shell 的 transition 策略允许）
- `class core` + `on boot: start` → 开机自动启动
- `exec_background` 作为兜底（双保险）

### `/system/etc/s8root.sh`

```sh
#!/system/bin/sh
LOG=/data/local/tmp/s8root.log
CMD=/data/local/tmp/s8cmd.sh
OUT=/data/local/tmp/s8cmd.out
PIDF=/data/local/tmp/s8root.pid
mkdir -p /data/local/tmp 2>/dev/null

# 防重复实例
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then exit 0; fi
echo $$ > "$PIDF"

{
  echo "=== s8root started $(date) ==="
  echo "uid=$(id -u) ctx=$(cat /proc/self/attr/current 2>/dev/null)"
  echo "getenforce=$(getenforce 2>/dev/null)"
} >> $LOG 2>&1

setprop persist.sys.usb.config mtp,adb 2>/dev/null
settings put global adb_enabled 1 2>/dev/null

# 命令通道：轮询 /data/local/tmp/s8cmd.sh
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
```

## 使用方式

```bash
# 写命令
adb shell "echo 'id; getenforce' > /data/local/tmp/s8cmd.sh"
# 等 2 秒，读结果（注意 daemon 以 077 umask 写文件，需要命令自己 chmod）
adb shell "printf 'id > /data/local/tmp/r.txt 2>&1; chmod 666 /data/local/tmp/r.txt\n' > /data/local/tmp/s8cmd.sh"
sleep 4
adb shell "cat /data/local/tmp/r.txt"
```

## 验证结果

```
uid=0(root) gid=0(root) groups=0(root),1000(system),2000(shell) context=u:r:shell:s0
Enforcing
```

## 能力与限制

### 能做
- 以 uid 0 执行任意命令
- 读写 `/data`（含部分系统数据）
- 结束进程、修改部分属性、执行 pm/am 等
- 批量操作、调试

### 不能做（SELinux shell 域限制）
- **读 /sdcard**（fuse 权限拒绝）—— 需通过 adb shell（uid 2000）中转
- **读其他应用私有数据**（/data/data/*）
- **mount**（无 CAP_SYS_ADMIN 对应域权限）
- **写 /data/system**（package-restrictions.xml 等）

### 升级方向（未做）
把 `seclabel` 改为 `u:r:su:s0` 或去掉 seclabel（继承 init 域）可获得更大权限，
但需要验证 init→su 的 transition 策略是否允许。

## 相关脚本

- `src/silent-installer/s8root.sh` / `s8root.rc`
- `scripts/build/integrate_system2.sh` — 把 daemon 打进 system 镜像
