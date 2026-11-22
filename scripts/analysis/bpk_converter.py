#!/usr/bin/env python3
"""
步步高 BPK <-> APK 双向转换工具

BPK格式说明:
  - BPK是步步高定制的ZIP格式，魔数从PK改为BPK
  - ZIP元数据区域(EOCD/CD/LFH/DD)使用XOR加密
  - 文件数据本身不加密
  - LFH中extra_field_length字段不参与XOR加密
  - LFH文件名从密钥偏移0开始加密（CD文件名从偏移42开始）
  - APK v2签名块位于CD之前，需完整保留

转换方式：原地修改（in-place）
  - 复制整个文件，保留所有原始数据
  - 仅修改魔数和XOR加密/解密元数据
  - 完整保留APK签名块、文件顺序、原始压缩数据

用法:
  python bpk_converter.py to-bpk <input.apk> <output.bpk>
  python bpk_converter.py to-apk <input.bpk> <output.apk>
  python bpk_converter.py info <file>
"""

import struct
import sys
import os
import argparse

# ============================================================
# XOR 密钥
# ============================================================

XOR_KEYS = {
    'EOCD': b'END_OF_CENTRAL_DIRECTORY_XOR_CODE_OF_BBK_APK_ENCRYPTION',
    'CD':   b'CENTRAL_DIRECTORY_XOR_CODE_OF_BBK_APK_ENCRYPTION',
    'LFH':  b'LOCAL_FILE_HEADER_XOR_CODE_OF_BBK_APK_ENCRYPTION',
}

# ============================================================
# 魔数标记
# ============================================================

# 标准ZIP
ZIP_LFH_SIG  = 0x04034b50  # PK\x03\x04
ZIP_CD_SIG   = 0x02014b50  # PK\x01\x02
ZIP_EOCD_SIG = 0x06054b50  # PK\x05\x06
ZIP_DD_SIG   = 0x08074b50  # PK\x07\x08

# BPK魔数转换算法
def pk2bpk(pk):
    """ZIP魔数 -> BPK魔数"""
    return (((pk % 0x1000000) << 8) + 0x42)

def bpk2pk(bpk):
    """BPK魔数 -> ZIP魔数"""
    return ((((bpk >> 24) + 1) << 24) + (bpk >> 8))

BPK_LFH_SIG  = pk2bpk(ZIP_LFH_SIG)   # 0x034b5042
BPK_CD_SIG   = pk2bpk(ZIP_CD_SIG)    # 0x014b5042
BPK_EOCD_SIG = pk2bpk(ZIP_EOCD_SIG)  # 0x054b5042
BPK_DD_SIG   = pk2bpk(ZIP_DD_SIG)    # 0x074b5042

# ============================================================
# 工具函数
# ============================================================

def xor_crypt(data, key, key_offset=0):
    """XOR加解密（对称的，加密解密用同一个函数）"""
    result = bytearray(len(data))
    key_len = len(key)
    for i in range(len(data)):
        result[i] = data[i] ^ key[(key_offset + i) % key_len]
    return bytes(result)


def sig_to_bytes(s):
    """将整数签名转为4字节小端"""
    return struct.pack('<I', s)


def bytes_to_sig(b):
    """将4字节转为整数签名"""
    return struct.unpack('<I', b)[0]


# ============================================================
# 格式检测
# ============================================================

def detect_format(data):
    """检测文件格式，返回 'bpk', 'apk', 或 'unknown'
    通过查找EOCD来判断，因为文件开头可能有额外数据（如BPK头部）
    """
    # 先尝试找BPK的EOCD
    eocd_bpk, _ = find_eocd(data, is_bpk=True)
    if eocd_bpk is not None:
        return 'bpk'
    # 再尝试找标准ZIP的EOCD
    eocd_zip, _ = find_eocd(data, is_bpk=False)
    if eocd_zip is not None:
        return 'apk'
    return 'unknown'


# ============================================================
# EOCD 解析
# ============================================================

def find_eocd(data, is_bpk=False):
    """从文件末尾向前查找EOCD，返回位置和解析后的结构"""
    if is_bpk:
        sig = sig_to_bytes(BPK_EOCD_SIG)
    else:
        sig = sig_to_bytes(ZIP_EOCD_SIG)

    # EOCD至少22字节，最多22+65535（comment）
    search_start = max(0, len(data) - 65557)
    pos = data.rfind(sig, search_start)
    if pos == -1:
        return None, -1

    if pos + 22 > len(data):
        return None, -1

    # EOCD结构: 4sig + 2disk + 2disk_cd + 2entries_disk + 2entries + 4cd_size + 4cd_offset + 2comment_len
    if is_bpk:
        # BPK: 前4字节签名明文，后18字节加密
        eocd_enc = data[pos+4:pos+22]
        eocd_dec = xor_crypt(eocd_enc, XOR_KEYS['EOCD'], 0)
        eocd_data = data[pos:pos+4] + eocd_dec
    else:
        eocd_data = data[pos:pos+22]

    eocd = struct.unpack('<IHHHHIIH', eocd_data)
    return eocd, pos


# ============================================================
# CD 解析
# ============================================================

def parse_cd_entries(data, cd_offset, cd_size, is_bpk=False):
    """解析中央目录，返回条目列表"""
    entries = []
    pos = cd_offset
    end = cd_offset + cd_size
    cd_key = XOR_KEYS['CD']

    while pos + 46 <= end:
        # 读取签名
        entry_sig = bytes_to_sig(data[pos:pos+4])

        if is_bpk:
            if entry_sig != BPK_CD_SIG:
                break
        else:
            if entry_sig != ZIP_CD_SIG:
                break

        # 解析CD头（42字节，除4字节签名外）
        if is_bpk:
            cd_header_enc = data[pos+4:pos+46]
            cd_header_dec = xor_crypt(cd_header_enc, cd_key, 0)
        else:
            cd_header_dec = data[pos+4:pos+46]

        cd_header = struct.unpack('<HHHHHHIIIHHHHHII', cd_header_dec)
        (ver_made, ver_need, flags, comp_method, mod_time, mod_date,
         crc32, comp_size, uncomp_size, name_len, extra_len,
         comment_len, disk_num, int_attr, ext_attr, local_offset) = cd_header

        # 解析文件名
        if is_bpk:
            # CD文件名从密钥偏移42开始
            name_enc = data[pos+46:pos+46+name_len]
            name_dec = xor_crypt(name_enc, cd_key, 42)
            name = name_dec.decode('utf-8', errors='replace')
        else:
            name = data[pos+46:pos+46+name_len].decode('utf-8', errors='replace')

        entry_size = 46 + name_len + extra_len + comment_len

        entries.append({
            'name': name,
            'ver_made': ver_made,
            'ver_need': ver_need,
            'flags': flags,
            'comp_method': comp_method,
            'mod_time': mod_time,
            'mod_date': mod_date,
            'crc32': crc32,
            'comp_size': comp_size,
            'uncomp_size': uncomp_size,
            'name_len': name_len,
            'extra_len': extra_len,
            'comment_len': comment_len,
            'disk_num': disk_num,
            'int_attr': int_attr,
            'ext_attr': ext_attr,
            'local_offset': local_offset,
            'cd_pos': pos,
            'cd_entry_size': entry_size,
        })

        pos += entry_size

    return entries


# ============================================================
# 原地修改转换
# ============================================================

def _detect_bpk_crc_format(data, entries, lfh_key):
    """
    检测BPK中LFH的crc32字段格式
    返回:
      'encrypted' - 加密的0xFFFFFFFF（先置0xFF，再加密）
      'plaintext' - 明文的0xFFFFFFFF（先加密，再覆盖为明文0xFF）
    """
    if not entries:
        return 'plaintext'  # 默认用C代码的格式
    
    # 找一个没有data descriptor的条目来检测
    for entry in entries:
        if entry['flags'] & 0x8:
            continue  # 有DD的跳过
        
        local_off = entry['local_offset']
        if local_off + 18 > len(data):
            continue
        
        # 读取crc32的原始4字节
        crc32_raw = data[local_off+14:local_off+18]
        
        # 如果原始字节全是ff，说明是明文格式
        if crc32_raw == b'\xff\xff\xff\xff':
            return 'plaintext'
        else:
            # 解密看看是不是0xFFFFFFFF
            crc32_dec = bytes([crc32_raw[i] ^ lfh_key[10+i] for i in range(4)])
            if crc32_dec == b'\xff\xff\xff\xff':
                return 'encrypted'
    
    # 默认返回明文格式（C代码的格式）
    return 'plaintext'


def _convert_inplace(data, direction, crc_mode='auto'):
    """
    原地修改转换
    direction: 'apk-to-bpk' 或 'bpk-to-apk'
    crc_mode: 'auto' 自动检测 / 'plaintext' 明文0xFF / 'encrypted' 加密的0xFF
    返回修改后的bytearray
    """
    is_bpk_input = (direction == 'bpk-to-apk')
    output = bytearray(data)  # 复制一份，准备修改

    # 1. 解析EOCD
    eocd, eocd_pos = find_eocd(output, is_bpk=is_bpk_input)
    if eocd is None:
        raise ValueError("无法找到EOCD")

    (eocd_sig, disk_num, disk_cd, entries_disk, entries_total,
     cd_size, cd_offset, comment_len) = eocd

    # 2. 解析CD条目
    entries = parse_cd_entries(output, cd_offset, cd_size, is_bpk=is_bpk_input)
    if len(entries) != entries_total:
        print(f"[!] 警告: EOCD声明{entries_total}个条目，实际解析到{len(entries)}个")

    # 3. 检测crc32字段格式
    lfh_key = XOR_KEYS['LFH']
    cd_key = XOR_KEYS['CD']
    
    if crc_mode == 'auto' and is_bpk_input:
        # 从原始BPK检测格式
        crc_format = _detect_bpk_crc_format(data, entries, lfh_key)
        print(f"[*] 检测到BPK格式: {'加密0xFF' if crc_format == 'encrypted' else '明文0xFF'}")
    elif crc_mode == 'auto':
        # APK→BPK方向，默认用明文格式（C代码的格式）
        crc_format = 'plaintext'
    else:
        crc_format = crc_mode

    for entry in entries:
        local_offset = entry['local_offset']
        name_len = entry['name_len']
        extra_len = entry['extra_len']

        # ========================================
        # 处理LFH
        # ========================================
        # LFH结构:
        #   4 bytes: signature
        #  24 bytes: header (version..name_len)  <- XOR加密部分
        #   2 bytes: extra_field_length          <- 不加密!
        # N bytes: file_name                     <- XOR加密（从密钥偏移0开始）
        # M bytes: extra_field                   <- 不加密
        #   ... file data ...

        # 读取原始LFH头（30字节 = 4 + 26）
        lfh_pos = local_offset
        lfh_sig_bytes = output[lfh_pos:lfh_pos+4]
        lfh_header_24 = output[lfh_pos+4:lfh_pos+28]   # 前24字节（加密的）
        lfh_extra_len_bytes = output[lfh_pos+28:lfh_pos+30]  # 最后2字节（不加密）

        # 修改LFH签名
        if direction == 'bpk-to-apk':
            new_sig = sig_to_bytes(ZIP_LFH_SIG)
        else:
            new_sig = sig_to_bytes(BPK_LFH_SIG)
        output[lfh_pos:lfh_pos+4] = new_sig

        # 处理LFH头（24字节，不包括extra_field_length）
        # 注意：BPK中LFH的crc32/comp_size/uncomp_size是明文的0xFFFFFFFF
        #       （C代码逻辑：先加密整个头，再把这3个字段覆盖为0xFFFFFFFF）
        if direction == 'bpk-to-apk':
            # 解密24字节头
            lfh_header_dec = xor_crypt(lfh_header_24, lfh_key, 0)

            # 解密文件名（从密钥偏移0开始）
            name_enc = output[lfh_pos+30:lfh_pos+30+name_len]
            name_dec = xor_crypt(name_enc, lfh_key, 0)
            output[lfh_pos+30:lfh_pos+30+name_len] = name_dec

            # 从CD中恢复crc32/comp_size/uncomp_size的正确值
            # （BPK中这些字段是明文0xFFFFFFFF，解密后变成乱码，需要从CD恢复）
            lfh_header = struct.unpack('<HHHHHIIIH', lfh_header_dec)
            (ver_need, flags, method, mtime, mdate,
             lfh_crc, lfh_comp, lfh_uncomp, lfh_name_len) = lfh_header

            # 如果没有data descriptor，用CD中的正确值覆盖
            if not (flags & 0x8):
                new_header = struct.pack('<HHHHHIIIH',
                    ver_need, flags, method, mtime, mdate,
                    entry['crc32'], entry['comp_size'], entry['uncomp_size'],
                    lfh_name_len)
                output[lfh_pos+4:lfh_pos+28] = new_header
            else:
                # 有data descriptor，直接写解密后的头
                output[lfh_pos+4:lfh_pos+28] = lfh_header_dec

        else:  # apk-to-bpk
            flags = entry['flags']

            if not (flags & 0x8):
                # 没有data descriptor，需要处理crc32/comp_size/uncomp_size
                if crc_format == 'plaintext':
                    # 明文格式（C代码逻辑）：先加密整个头，再覆盖为明文0xFF
                    lfh_header_enc = xor_crypt(lfh_header_24, lfh_key, 0)
                    output[lfh_pos+4:lfh_pos+28] = lfh_header_enc
                    # 覆盖crc32/comp_size/uncomp_size为明文0xFFFFFFFF
                    output[lfh_pos+4+10:lfh_pos+4+22] = b'\xff' * 12
                else:
                    # 加密格式：先把crc32等置为0xFFFFFFFF，再加密整个头
                    lfh_header = struct.unpack('<HHHHHIIIH', lfh_header_24)
                    (ver_need, fl, method, mtime, mdate,
                     crc, comp, uncomp, lfh_name_len) = lfh_header
                    new_header = struct.pack('<HHHHHIIIH',
                        ver_need, fl, method, mtime, mdate,
                        0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF,
                        lfh_name_len)
                    lfh_header_enc = xor_crypt(new_header, lfh_key, 0)
                    output[lfh_pos+4:lfh_pos+28] = lfh_header_enc
            else:
                # 有data descriptor，直接加密整个头
                lfh_header_enc = xor_crypt(lfh_header_24, lfh_key, 0)
                output[lfh_pos+4:lfh_pos+28] = lfh_header_enc

            # 加密文件名（从密钥偏移0开始）
            name_plain = output[lfh_pos+30:lfh_pos+30+name_len]
            name_enc = xor_crypt(name_plain, lfh_key, 0)
            output[lfh_pos+30:lfh_pos+30+name_len] = name_enc

            # extra_field_length 和 extra field 不加密，保持原样
            # 文件数据不加密，保持原样

        # 处理data descriptor（如果有）
        if entry['flags'] & 0x8:
            dd_pos = local_offset + 30 + name_len + extra_len + entry['comp_size']
            dd_sig_bytes = output[dd_pos:dd_pos+4]
            dd_sig = bytes_to_sig(dd_sig_bytes)

            # 检查是否有DD签名
            has_dd_sig = False
            if is_bpk_input:
                if dd_sig == BPK_DD_SIG:
                    has_dd_sig = True
            else:
                if dd_sig == ZIP_DD_SIG:
                    has_dd_sig = True

            if has_dd_sig:
                # DD结构: 4sig + 4crc + 4comp_size + 4uncomp_size = 16字节
                # 除签名外的12字节参与XOR
                if direction == 'bpk-to-apk':
                    output[dd_pos:dd_pos+4] = sig_to_bytes(ZIP_DD_SIG)
                    dd_data_enc = output[dd_pos+4:dd_pos+16]
                    dd_data_dec = xor_crypt(dd_data_enc, lfh_key, 0)
                    output[dd_pos+4:dd_pos+16] = dd_data_dec
                else:
                    output[dd_pos:dd_pos+4] = sig_to_bytes(BPK_DD_SIG)
                    dd_data_plain = output[dd_pos+4:dd_pos+16]
                    dd_data_enc = xor_crypt(dd_data_plain, lfh_key, 0)
                    output[dd_pos+4:dd_pos+16] = dd_data_enc

        # ========================================
        # 处理CD条目
        # ========================================
        # CD结构:
        #   4 bytes: signature
        #  42 bytes: header  <- XOR加密
        # N bytes: file_name <- XOR加密（密钥偏移42，连续的）
        # M bytes: extra     <- XOR加密
        # K bytes: comment   <- XOR加密

        cd_entry_pos = entry['cd_pos']
        cd_entry_size = entry['cd_entry_size']

        # 修改CD签名
        if direction == 'bpk-to-apk':
            output[cd_entry_pos:cd_entry_pos+4] = sig_to_bytes(ZIP_CD_SIG)
        else:
            output[cd_entry_pos:cd_entry_pos+4] = sig_to_bytes(BPK_CD_SIG)

        # 处理CD数据（除签名外的所有内容：42字节头 + name + extra + comment）
        cd_data_start = cd_entry_pos + 4
        cd_data_end = cd_entry_pos + cd_entry_size
        cd_data_len = cd_data_end - cd_data_start

        if direction == 'bpk-to-apk':
            # 解密（整个数据块连续解密）
            cd_data_enc = output[cd_data_start:cd_data_end]
            cd_data_dec = xor_crypt(cd_data_enc, cd_key, 0)
            output[cd_data_start:cd_data_end] = cd_data_dec
        else:
            # 加密（整个数据块连续加密）
            cd_data_plain = output[cd_data_start:cd_data_end]
            cd_data_enc = xor_crypt(cd_data_plain, cd_key, 0)
            output[cd_data_start:cd_data_end] = cd_data_enc

    # ========================================
    # 处理EOCD
    # ========================================
    # EOCD结构: 4sig + 18bytes data
    # 修改签名
    if direction == 'bpk-to-apk':
        output[eocd_pos:eocd_pos+4] = sig_to_bytes(ZIP_EOCD_SIG)
        # 解密后18字节
        eocd_data_enc = output[eocd_pos+4:eocd_pos+22]
        eocd_data_dec = xor_crypt(eocd_data_enc, XOR_KEYS['EOCD'], 0)
        output[eocd_pos+4:eocd_pos+22] = eocd_data_dec
    else:
        output[eocd_pos:eocd_pos+4] = sig_to_bytes(BPK_EOCD_SIG)
        # 加密后18字节
        eocd_data_plain = output[eocd_pos+4:eocd_pos+22]
        eocd_data_enc = xor_crypt(eocd_data_plain, XOR_KEYS['EOCD'], 0)
        output[eocd_pos+4:eocd_pos+22] = eocd_data_enc

    # EOCD的comment部分不加密（如果有的话）

    # ========================================
    # APK签名块：保持原样不动（位于CD之前）
    # ========================================
    # 签名块不是ZIP格式的一部分，直接保留

    return output


# ============================================================
# BPK -> APK 转换
# ============================================================

def bpk_to_apk(bpk_path, apk_path):
    """将BPK格式转换为标准APK（原地修改方式）"""
    print(f"[*] 读取BPK: {bpk_path}")

    with open(bpk_path, 'rb') as f:
        data = f.read()

    original_size = len(data)
    print(f"[*] 原始大小: {original_size} 字节")

    # 验证格式
    fmt = detect_format(data)
    if fmt != 'bpk':
        print(f"[!] 错误: 文件不是BPK格式 (检测到: {fmt})")
        return False

    # 解析EOCD获取基本信息
    eocd, eocd_pos = find_eocd(data, is_bpk=True)
    if eocd is None:
        print("[!] 错误: 无法找到EOCD")
        return False

    entries_total = eocd[4]
    cd_size = eocd[5]
    cd_offset = eocd[6]
    print(f"[*] 文件数: {entries_total}")
    print(f"[*] CD偏移: 0x{cd_offset:x}")

    # 检查是否有APK签名块
    sig_magic = b'APK Sig Block 42'
    sig_pos = data.rfind(sig_magic, max(0, cd_offset - 16*1024*1024), cd_offset)
    if sig_pos != -1:
        sig_block_end = sig_pos + 16
        sig_size = struct.unpack('<Q', data[sig_pos-8:sig_pos])[0]
        print(f"[*] 检测到APK签名块: {sig_size} 字节")
    else:
        print("[*] 未检测到APK v2签名块")

    # 原地修改转换（自动检测格式）
    print("[*] 转换中...")
    output = _convert_inplace(data, 'bpk-to-apk', crc_mode='auto')

    # 写出
    print(f"[*] 写出APK: {apk_path}")
    with open(apk_path, 'wb') as f:
        f.write(output)

    print(f"[✓] 转换完成! 输出大小: {len(output)} 字节")
    return True


def apk_to_bpk(apk_path, bpk_path, crc_mode='auto'):
    """将标准APK转换为BPK格式（原地修改方式）
    
    crc_mode: 'auto' 默认明文格式 / 'plaintext' 明文0xFF / 'encrypted' 加密0xFF
    """
    print(f"[*] 读取APK: {apk_path}")

    with open(apk_path, 'rb') as f:
        data = f.read()

    original_size = len(data)
    print(f"[*] 原始大小: {original_size} 字节")

    # 验证格式
    fmt = detect_format(data)
    if fmt != 'apk':
        print(f"[!] 错误: 文件不是标准APK格式 (检测到: {fmt})")
        return False

    # 解析EOCD获取基本信息
    eocd, eocd_pos = find_eocd(data, is_bpk=False)
    if eocd is None:
        print("[!] 错误: 无法找到EOCD")
        return False

    entries_total = eocd[4]
    cd_size = eocd[5]
    cd_offset = eocd[6]
    print(f"[*] 文件数: {entries_total}")
    print(f"[*] CD偏移: 0x{cd_offset:x}")

    # 检查是否有APK签名块
    sig_magic = b'APK Sig Block 42'
    sig_pos = data.rfind(sig_magic, max(0, cd_offset - 16*1024*1024), cd_offset)
    if sig_pos != -1:
        sig_size = struct.unpack('<Q', data[sig_pos-8:sig_pos])[0]
        print(f"[*] 检测到APK签名块: {sig_size} 字节")
    else:
        print("[*] 未检测到APK v2签名块")

    # 显示crc模式
    if crc_mode == 'encrypted':
        print("[*] CRC模式: 加密0xFF")
    else:
        print("[*] CRC模式: 明文0xFF (C代码格式)")

    # 原地修改转换
    print("[*] 转换中...")
    output = _convert_inplace(data, 'apk-to-bpk', crc_mode=crc_mode)

    # 写出
    print(f"[*] 写出BPK: {bpk_path}")
    with open(bpk_path, 'wb') as f:
        f.write(output)

    print(f"[✓] 转换完成! 输出大小: {len(output)} 字节")
    return True


# ============================================================
# 文件信息查看
# ============================================================

def show_info(filepath):
    """显示BPK或APK文件的信息"""
    print(f"文件: {filepath}")
    print(f"大小: {os.path.getsize(filepath)} 字节")
    print()

    with open(filepath, 'rb') as f:
        data = f.read()

    header = data[:4]
    print(f"文件头: {header.hex()} ({header})")

    fmt = detect_format(data)
    if fmt == 'bpk':
        print("格式: 步步高 BPK (加密ZIP)")
        is_bpk = True
    elif fmt == 'apk':
        print("格式: 标准 ZIP/APK")
        is_bpk = False
    else:
        print("格式: 未知")
        return

    eocd, eocd_pos = find_eocd(data, is_bpk=is_bpk)
    if eocd:
        _, _, _, _, entries_total, cd_size, cd_offset, comment_len = eocd
        print(f"条目数: {entries_total}")
        print(f"CD偏移: 0x{cd_offset:x}")
        print(f"CD大小: {cd_size} 字节")
        print(f"EOCD位置: 0x{eocd_pos:x}")

        # 检查APK签名块
        sig_magic = b'APK Sig Block 42'
        sig_pos = data.rfind(sig_magic, max(0, cd_offset - 16*1024*1024), cd_offset)
        if sig_pos != -1:
            sig_size = struct.unpack('<Q', data[sig_pos-8:sig_pos])[0]
            print(f"APK签名块: {sig_size} 字节")
        else:
            print(f"APK签名块: 无")

        # 如果是BPK，检测crc32字段格式
        if is_bpk:
            entries = parse_cd_entries(data, cd_offset, cd_size, is_bpk=True)
            crc_fmt = _detect_bpk_crc_format(data, entries, XOR_KEYS['LFH'])
            if crc_fmt == 'encrypted':
                print(f"CRC模式: 加密0xFFFFFFFF (先置0xFF, 再加密)")
            else:
                print(f"CRC模式: 明文0xFFFFFFFF (先加密, 再覆盖为0xFF, C代码格式)")

        entries = parse_cd_entries(data, cd_offset, cd_size, is_bpk=is_bpk)
        print(f"\n文件列表 (前20个 / 共{len(entries)}个):")
        for i, e in enumerate(entries[:20]):
            comp = 'stored' if e['comp_method'] == 0 else 'deflate'
            print(f"  [{i:2d}] {e['name']} ({e['uncomp_size']} bytes, {comp})")
        if len(entries) > 20:
            print(f"  ... 还有 {len(entries)-20} 个文件")

    # 检查META-INF
    print(f"\nMETA-INF 目录:")
    if eocd:
        entries = parse_cd_entries(data, cd_offset, cd_size, is_bpk=is_bpk)
        for e in entries:
            if 'META-INF/' in e['name']:
                print(f"  {e['name']}")


# ============================================================
# 主函数
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description='步步高 BPK <-> APK 双向转换工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  %(prog)s to-bpk app.apk app.bpk      # APK转BPK
  %(prog)s to-apk app.bpk app.apk      # BPK转APK
  %(prog)s info app.bpk                # 查看文件信息
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='可用命令')

    # to-bpk
    p_bpk = subparsers.add_parser('to-bpk', help='APK转BPK格式')
    p_bpk.add_argument('input', help='输入APK文件路径')
    p_bpk.add_argument('output', help='输出BPK文件路径')
    p_bpk.add_argument('--encrypted-crc', action='store_true',
                        help='使用加密0xFF模式（先置0xFFFFFFFF再加密，默认是明文0xFF/C代码格式）')

    # to-apk
    p_apk = subparsers.add_parser('to-apk', help='BPK转APK格式')
    p_apk.add_argument('input', help='输入BPK文件路径')
    p_apk.add_argument('output', help='输出APK文件路径')

    # info
    p_info = subparsers.add_parser('info', help='查看文件信息')
    p_info.add_argument('file', help='要查看的文件路径')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    if args.command == 'to-bpk':
        if not os.path.exists(args.input):
            print(f"[!] 错误: 输入文件不存在: {args.input}")
            return 1
        crc_mode = 'encrypted' if args.encrypted_crc else 'plaintext'
        success = apk_to_bpk(args.input, args.output, crc_mode=crc_mode)
        return 0 if success else 1

    elif args.command == 'to-apk':
        if not os.path.exists(args.input):
            print(f"[!] 错误: 输入文件不存在: {args.input}")
            return 1
        success = bpk_to_apk(args.input, args.output)
        return 0 if success else 1

    elif args.command == 'info':
        if not os.path.exists(args.file):
            print(f"[!] 错误: 文件不存在: {args.file}")
            return 1
        show_info(args.file)
        return 0


if __name__ == '__main__':
    sys.exit(main())
