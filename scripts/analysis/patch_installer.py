import struct, hashlib, zlib, zipfile, io, os, subprocess, sys

APK_IN = '/tmp/bpk2apk/BPackageInstaller.apk'
APK_OUT = '/root/s8/patcher/BPackageInstaller_patched.apk'

# 要补丁的方法: (类名, 方法名, 返回常量0/1)
TARGETS = [
    ('Lcom/android/packageinstaller/PackageInstallerActivity;', 'isInBlackList', 0),
    ('Lcom/android/packageinstaller/util/Utils;', 'isInBlackList', 0),
    ('Lcom/android/packageinstaller/util/Utils;', 'isApkFileCanInstall', 1),
]

# ---------- dex 解析工具 ----------
def uleb(b, off):
    r = 0; s = 0
    while True:
        x = b[off]; off += 1
        r |= (x & 0x7f) << s
        if not (x & 0x80):
            return r, off
        s += 7

def find_class_def(dex, cls_name):
    # header: string_ids_size@0x38 off@0x3c; type_ids@0x40/0x44; class_defs@0x60/0x64
    sid_size, sid_off = struct.unpack_from('<II', dex, 0x38)
    type_size, type_off = struct.unpack_from('<II', dex, 0x40)
    cd_size, cd_off = struct.unpack_from('<II', dex, 0x60)
    def string(idx):
        so, = struct.unpack_from('<I', dex, sid_off + idx*4)
        n, p = uleb(dex, so)
        return dex[p:p+n].decode('utf-8', 'replace')
    def type_name(tidx):
        sidx, = struct.unpack_from('<I', dex, type_off + tidx*4)
        return string(sidx)
    for i in range(cd_size):
        off = cd_off + i*32
        class_idx, = struct.unpack_from('<I', dex, off)
        if type_name(class_idx) != cls_name:
            continue
        class_data_off, = struct.unpack_from('<I', dex, off+24)
        return class_data_off
    return None

def find_method_code_off(dex, cls_name, mname):
    cdo = find_class_def(dex, cls_name)
    if not cdo:
        return None
    p = cdo
    sf, p = uleb(dex, p)
    inf, p = uleb(dex, p)
    dm, p = uleb(dex, p)
    vm, p = uleb(dex, p)
    # 跳过字段
    for _ in range(sf + inf):
        _, p = uleb(dex, p)
        _, p = uleb(dex, p)
    # 方法（直接+虚）
    midx = 0
    for _ in range(dm + vm):
        diff, p = uleb(dex, p)
        midx += diff
        acc, p = uleb(dex, p)
        code_off, p = uleb(dex, p)
        # 方法名: method_ids[0x58/0x5c]
        mid_size, mid_off = struct.unpack_from('<II', dex, 0x58)
        name_idx, = struct.unpack_from('<I', dex, mid_off + midx*8 + 4)
        sid_size, sid_off = struct.unpack_from('<II', dex, 0x38)
        so, = struct.unpack_from('<I', dex, sid_off + name_idx*4)
        n, q = uleb(dex, so)
        if dex[q:q+n].decode('utf-8', 'replace') == mname:
            return code_off
    return None

def fix_dex_header(dex):
    d = bytearray(dex)
    # signature: sha1 over bytes 32..end
    sig = hashlib.sha1(bytes(d[32:])).digest()
    d[12:32] = sig
    # checksum: adler32 over bytes 12..end
    ck = zlib.adler32(bytes(d[12:])) & 0xffffffff
    struct.pack_into('<I', d, 8, ck)
    return bytes(d)

def patch_method(dex, cls_name, mname, retval):
    code_off = find_method_code_off(dex, cls_name, mname)
    if not code_off:
        print("  !! 未找到 %s.%s" % (cls_name, mname))
        return dex, False
    d = bytearray(dex)
    # code_item: registers(2) ins(2) outs(2) tries(2) debug_off(4) insns_size(4) insns...
    tries_off = code_off + 6
    insns_size, = struct.unpack_from('<I', d, code_off + 12)
    insns_off = code_off + 16
    # 写: const/4 v0, #retval ; return v0 ; 其余 nop
    struct.pack_into('<H', d, insns_off, 0x0012 | (0 << 8))  # const/4 v0, #0 (A=0,B=0)
    # const/4: opcode 0x12, A=0(reg), B=retval
    cu0 = (0x12) | (0 << 8) | (retval << 12)
    struct.pack_into('<H', d, insns_off, cu0)
    struct.pack_into('<H', d, insns_off+2, 0x000f)  # return v0
    for i in range(2, insns_size):
        struct.pack_into('<H', d, insns_off + i*2, 0x0000)  # nop
    struct.pack_into('<H', d, tries_off, 0)  # tries_size = 0
    print("  ✓ 补丁 %s.%s -> ret %d (code_off=0x%x insns=%d)" % (cls_name, mname, retval, code_off, insns_size))
    return bytes(d), True

# ---------- 主流程 ----------
os.makedirs('/root/s8/patcher', exist_ok=True)
zin = zipfile.ZipFile(APK_IN)
names = zin.namelist()
dexd = {}
patched = 0
for n in names:
    if n.startswith('classes') and n.endswith('.dex'):
        dex = zin.read(n)
        changed = False
        for cls, mname, rv in TARGETS:
            dex2, ok = patch_method(dex, cls, mname, rv)
            if ok:
                dex = dex2
                changed = True
                patched += 1
        if changed:
            dex = fix_dex_header(dex)
        dexd[n] = dex

print("\n共补丁 %d 个方法" % patched)
if patched == 0:
    print("!! 没有补丁生效，中止"); sys.exit(1)

# 重打包 zip（保持结构，重新压缩）
zout = zipfile.ZipFile(APK_OUT, 'w', zipfile.ZIP_DEFLATED)
for n in names:
    data = dexd.get(n, zin.read(n))
    zout.writestr(n, data)
zout.close()
print("输出:", APK_OUT, os.path.getsize(APK_OUT))
