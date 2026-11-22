# 14 · super 动态分区 LP 元数据重建救砖法

> 适用：任何 Android 动态分区（super）设备。当设备卡 fastboot / 无限重启，
> 而 init 日志出现 `[liblp]Logical partition metadata has invalid ...` 时，
> **分区数据往往完好，只是元数据坏了** —— 重建元数据即可救活。

## 一、故障现象

```
init: [liblp]Logical partition metadata has invalid geometry magic signature.
init: [liblp]Logical partition metadata has invalid table checksum.
init: Could not read logical partition metadata from /dev/block/mmcblk0p41
init: Failed to mount required partitions early ...
→ init 关机 → bootloader 回退 fastboot
```

**判断**：super 里 system/vendor/product 的数据可能完全没事，只是开头
几百 KB 的**元数据区**被写坏（常见原因：刷写中断电/拔线、OTA 中断）。

## 二、LP 元数据格式（Android 10 ~ 13，来自 AOSP 源码）

### 1. 总体布局（super 开头）

```
偏移 0x0000      4096 字节     保留区（全 0，防止被当成引导扇区）
偏移 0x1000      4096 字节     Geometry（主）
偏移 0x2000      4096 字节     Geometry（备份）
偏移 0x3000      metadata_max_size   Metadata slot 0（主）
偏移 0x13000     metadata_max_size   Metadata slot 0（备份）    ← 0x3000 + 65536
偏移 0x23000     metadata_max_size   Metadata slot 1（主）
偏移 0x33000     metadata_max_size   Metadata slot 1（备份）
...
```

slot N 主 = `12288 + N * metadata_max_size * 2`；备份 = 主 + `metadata_max_size`。

### 2. Geometry（52 字节，packed）

```
0    u32   magic = 0x616c4467
4    u32   struct_size = 52
8    u8[32] checksum = SHA256(整个 geometry，checksum 字段置 0)
40   u32   metadata_max_size   （如 65536，必须 512 对齐）
44   u32   metadata_slot_count  （A/B 设备 = 2）
48   u32   logical_block_size   （通常 4096）
```

### 3. Header（v1.0 = 128 字节；v1.2 = 256 字节）

```
0    u32   magic = 0x414C5030
4    u16   major_version = 10
6    u16   minor_version（0/1 → 128 字节 header；≥2 → 256 字节 header）
8    u32   header_size（128 或 256）
12   u8[32] header_checksum = SHA256(header[0:header_size]，本字段置 0)
44   u32   tables_size
48   u8[32] tables_checksum = SHA256(所有表内容)
80   12B   partitions 表描述符   (offset, num_entries, entry_size)
92   12B   extents 表描述符
104  12B   groups 表描述符
116  12B   block_devices 表描述符
128  u32   flags            （v1.2 才有）
132  ...   reserved[124]
```

> 表描述符的 `offset` 是**相对于 header 末尾**（即 header_start + header_size）。
> 表之间不能有间隙。

### 4. 表项结构

| 表 | 结构 | 大小 |
|---|---|---|
| partition | name[36] + attributes u32 + first_extent_index u32 + num_extents u32 + group_index u32 | **52** |
| extent | num_sectors u64 + target_type u32 + target_data u64 + target_source u32 | **24** |
| group | name[36] + flags u32 + maximum_size u64 | **48** |
| block_device | first_logical_sector u64 + alignment u32 + alignment_offset u32 + size u64 + partition_name[36] + flags u32 | **64** |

- partition 属性：`1`=READONLY，`2`=SLOT_SUFFIXED（retrofit）
- extent target_type：`0`=LINEAR（target_data 为 super 内绝对扇区），`1`=ZERO

## 三、init 的校验规则（reader.cpp）

排错时逐条对照：

1. geometry：magic、`struct_size == 52`、SHA256 校验、`slot_count != 0`、
   `metadata_max_size % 512 == 0`
2. header：magic、`major == 10`、`minor <= 2`、
   `header_size` 必须等于 128（minor<2）或 256（minor≥2）、
   `header_checksum` 校验
3. 表边界：`offset <= tables_size` 且 `tables_size - offset >= num*entry_size`
4. 表项大小必须等于结构大小（52/24/48/64）
5. `tables_checksum` 校验
6. 分区：属性合法、`first_extent + num_extents <= extents 数`、`group_index` 合法
7. extent：`target_source < block_devices 数`
8. **block_devices[0].first_logical_sector * 512 >= 元数据区总大小**
   （元数据区 = 4096 + 4096*2 + metadata_max_size*slot_count*2）
   —— 这条最容易被忽略，first_logical_sector 通常 = 2048（1MB）

## 四、救砖流程（完整）

### 1. 拿到 super 全量镜像（BROM/TWRP）

```bash
# BROM 方式（设备卡 fastboot 时）
python3 mtk.py r super super_full.img
# 或 TWRP
adb shell dd if=/dev/block/by-name/super of=/sdcard/super.img
```

### 2. 扫描 ext4 超级块，定位逻辑分区

```python
# 找 ext4 magic 0xEF53（分区起始 + 0x438）
# erofs magic 0xE0F5E1E2（分区起始 + 1024）
# 验证 block_size/blocks 合理 + volume label
```

得到每个分区的 (起始, 大小, label)。

### 3. 从残留数据恢复分区表

在 super 前 1MB 内找分区名 ASCII（`system_a` 等）和 extent 的
`target_data`（= 分区起始扇区）。**extent 数据通常还在**，可直接抄用。

### 4. 重建元数据

用模板脚本生成（geometry + header + 4 张表 + 全部 checksum），
然后按 reader.cpp 规则自验证。

### 5. 刷入

**推荐 fastboot 方式**（最稳）：

```bash
cp super_full.img super_fixed.img
dd if=meta_fixed.bin of=super_fixed.img bs=1 count=274432 conv=notrunc
fastboot flash super super_fixed.img
fastboot reboot
```

> 为什么安全：`super_fixed.img` 除元数据外与原始 dump **逐位相同**，
> 即使刷写中断，已写入的区域也是原数据，不会进一步损坏分区。

## 五、脚本

- `scripts/lp-recovery/scan_super_fs.py` — 扫描 super 找 ext4/erofs 分区
- `scripts/lp-recovery/build_lp_metadata.py` — 按 AOSP 规则生成元数据并自验证

## 六、事故预防

1. **刷写 super 等大分区时绝对不能断电/拔线**（本事故的真因）
2. 改动前 `dump` 全量 super 并备份元数据（前 512KB 就够）
3. 保留 fastboot 可用性作为最后手段（MTK/Unisoc 设备一般可进）
