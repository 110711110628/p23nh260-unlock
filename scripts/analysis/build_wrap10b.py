import struct, hashlib, os, subprocess, shutil

SRC_C='/root/s8/initwrap9b.c'; NEW_C='/root/s8/initwrap10.c'
c=open(SRC_C).read()
marker='    char *av[] = { "/system/bin/sh", "-c", (char *)SCRIPT, 0 };'
if 'force_permissive' not in c:
    force_fn='''
/* v10: exec 前强制 permissive（内核域有 CAP_MAC_ADMIN） */
static void force_permissive(void){
    for (int i = 0; i < 300; i++) {
        int f = open("/sys/fs/selinux/enforce", O_WRONLY);
        if (f >= 0) {
            ssize_t w = write(f, "0", 1);
            close(f); (void)w;
            lg("PERM written i=%d\\n", i);
            ms(300);
            return;
        }
        ms(200);
    }
    lg("PERM FAILED errno=%d\\n", errno);
}
'''
    idx=c.find('static void child_main(void){')
    c=c[:idx]+force_fn+'\n'+c[idx:]
    c=c.replace(marker, '    force_permissive();\n\n'+marker, 1)
    open(NEW_C,'w').write(c)
print('initwrap10.c ready')
r=subprocess.run(['aarch64-linux-gnu-gcc','-static','-O2','-o','/root/s8/initwrap10',NEW_C],capture_output=True,text=True)
assert r.returncode==0, r.stderr[-1500:]
print('compiled', os.path.getsize('/root/s8/initwrap10'))

BOOT='/root/s8/img/boot_s8_wrap9b.img'; NEWBOOT='/root/s8/img/boot_s8_wrap10.img'
d=open(BOOT,'rb').read()
ks,rs,osv,hs=struct.unpack_from('<IIII',d,8)
P=4096; al=lambda n:(n+P-1)//P*P
koff=al(hs); roff=koff+al(ks)
rd=d[roff:roff+rs]
open('/tmp/w9b.rd.lz4','wb').write(rd)
subprocess.run(['lz4','-d','-f','/tmp/w9b.rd.lz4','/tmp/w9b.rd.cpio'],capture_output=True,check=True)
shutil.rmtree('/root/s8/w9bwork',ignore_errors=True); os.makedirs('/root/s8/w9bwork'); os.chdir('/root/s8/w9bwork')
with open('/tmp/w9b.rd.cpio','rb') as fh:
    subprocess.run(['cpio','-id','--quiet'],stdin=fh,capture_output=True,check=True)
shutil.copyfile('/root/s8/initwrap10','init'); os.chmod('init',0o755)
subprocess.run('find . -print0 | cpio --null -o -H newc --owner 0:0 --quiet > /tmp/w10.cpio',shell=True,check=True)
subprocess.run(['lz4','-l','-12','-f','/tmp/w10.cpio','/tmp/w10.lz4'],capture_output=True,check=True)
newrd=open('/tmp/w10.lz4','rb').read()
print('new ramdisk', len(newrd))
hdr=bytearray(d[:koff]); struct.pack_into('<I',hdr,12,len(newrd))
tail=d[roff+rs:]
img=bytearray(hdr)+d[koff:roff]+newrd
img+=b'\0'*(al(len(img))-len(img))
img+=tail
print('built', len(img), 'target', len(d))
if len(img)>len(d):
    img=img[:len(d)]   # 截掉尾部对齐/填充
else:
    img+=b'\0'*(len(d)-len(img))
assert len(img)==len(d)
open(NEWBOOT,'wb').write(bytes(img))
print('sha256:', hashlib.sha256(bytes(img)).hexdigest())
print('md5:', hashlib.md5(bytes(img)).hexdigest())