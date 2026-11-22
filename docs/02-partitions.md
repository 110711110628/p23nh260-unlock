# 02 · 分区布局（super / LP 元数据 / 11 extent）

## 1. super 分区结构（liblp）

- super 物理分区可通过 `/dev/block/by-name/super` 访问
- LP 元数据：magic `0x414c5030` @ 偏移 `0x3000`（即 12288），
  每组表头 256 字节，包含分区表 / extent 表 / 组表 / 块设备表
- 我们逆向出的解析要点：表基址 = `0x3000 + hsize@0x3008`

## 2. 逻辑分区与 extent 映射

| 逻辑分区 | 大小 | extent 数 | 首个 target 扇区 |
|---|---|---|---|
| system_a | 2951.4 MB | 11 | 2048 |
| system_ext_a | 319.7 MB | 1 | 5713920 |
| vendor_a | 3836.0 MB | 3 | 7106408 |
| product_a | 149.9 MB | 1 | 13498368（307072 扇区）|
| odm_a | 229.5 MB | 3 | 13809664 |
| vendor_dlkm_a | 9.7 MB | 2 | 14280704 |

### system_a 的 11 段（我们刷写时按段 dd 的完整列表）

```
target=2048       count=5710416  skip=0
target=5712472    count=1448    skip=5710416
target=6391328    count=480     skip=5711864
target=13498216   count=152     skip=5712344
target=13808216   count=1448    skip=5712496
target=14279544   count=1160    skip=5713944
target=14300640   count=67144   skip=5715104
target=6368712    count=22616   skip=5782248
target=13805440   count=2776    skip=5804864
target=14367784   count=144     skip=5807640
target=14784456   count=236688  skip=5807784
```

> `target` = super 内扇区偏移；`skip/count` = 镜像内偏移与长度（512 字节扇区）。
> 总大小 = 3,094,769,664 字节（= 分区大小）。

## 3. 分区文件系统

| 分区 | 格式 | 说明 |
|---|---|---|
| system | **erofs**（lz4hc 压缩） | 只读；我们重建时用 `mkfs.erofs -z lz4hc` |
| system_ext | erofs | |
| vendor | erofs | |
| product | erofs | **可修改**（150MB，改动最快） |
| odm / vendor_dlkm | erofs | |
| userdata | f2fs | |
| metadata | f2fs | 存我们的调试标记 |

> 关键：erofs 重建时必须保留 `feature_incompat = 0x1`（LZ4_0PADDING），
> 否则 5.4 内核无法挂载。所有文件需保留 `security.selinux` xattr。

## 4. 物理分区（GPT）

关键物理分区（偏移/大小，来自 expdb/GPT 读取）：

```
boot_para    @0x8000    1MB
para         @0x108000  512KB   ← MTK 式 misc（存 boot-recovery 标志）
boot_a       @0x19000000 32MB
vendor_boot_a@0x1b000000 64MB
init_boot_a  @0x1f000000 8MB
vbmeta_a     @0x20500000 8MB
super        @0x31000000 4.6GB+
userdata     @0x15b800000 9GB+
```

## 5. 修改系统的两种路径

| 路径 | 成本 | 适用 |
|---|---|---|
| **product 分区**（150MB） | 刷写 ~15 秒 | rc 注入、特权应用、adb 解锁 |
| **system 分区**（3GB） | 刷写 ~5 分钟 + 11 段校验 | root 守护、安装器补丁、应用市场特权化 |

> 实践结论：**能用 product 解决的绝不碰 system**；system 改动必须走完整的
> 11 extent 写入 + 逐段 MD5 校验（见 `scripts/flash/flash_system_v3.sh`）。
