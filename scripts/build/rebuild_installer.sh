#!/bin/bash
# 修复静默安装器：扫描自己的外部目录（无需存储权限）
set -e
cd /root/s8/silent/src/com/s8/silentinstaller

cat > InstallerActivity.java <<'JAVA'
package com.s8.silentinstaller;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Toast;
import java.io.File;

public class InstallerActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        final Intent it = getIntent();
        final Uri u = it.getData();
        final Context ctx = this;
        new Thread(new Runnable() {
            @Override
            public void run() {
                final StringBuilder sb = new StringBuilder();
                try {
                    if (u != null) {
                        Installer.install(ctx, u);
                        sb.append("已提交安装: ").append(u);
                    } else {
                        int c = scanAndInstall(ctx);
                        sb.append("目录安装提交 ").append(c).append(" 个 APK");
                    }
                } catch (Exception e) {
                    sb.append("失败: ").append(e.getMessage());
                }
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        Toast.makeText(InstallerActivity.this, sb.toString(), Toast.LENGTH_LONG).show();
                        finish();
                    }
                });
            }
        }).start();
    }

    /** 扫描所有可能目录并安装（自己的外部目录无需任何权限） */
    static int scanAndInstall(Context ctx) {
        int c = 0;
        File[] dirs = new File[] {
                new File(ctx.getExternalFilesDir(null), "install"),
                new File("/sdcard/Download/install")
        };
        for (File dir : dirs) {
            File[] fs = null;
            try {
                fs = dir.listFiles();
            } catch (Exception ignored) {
            }
            if (fs == null) {
                continue;
            }
            for (File f : fs) {
                if (f.getName().endsWith(".apk")) {
                    Installer.installFile(ctx, f);
                    c++;
                    try {
                        Thread.sleep(4000);
                    } catch (InterruptedException ignored) {
                    }
                }
            }
        }
        return c;
    }
}
JAVA

cat > BootReceiver.java <<'JAVA'
package com.s8.silentinstaller;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent i) {
        String a = i.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(a) && !"com.s8.INSTALL".equals(a)) {
            return;
        }
        final Context ctx = c.getApplicationContext();
        new Thread(new Runnable() {
            @Override
            public void run() {
                InstallerActivity.scanAndInstall(ctx);
            }
        }).start();
    }
}
JAVA

echo "=== 源码已更新 ==="
cd /root/s8/silent
echo "=== 重建 APK ==="
bash build_apk2.sh 2>&1 | tail -12
echo ""
echo "=== APK 信息 ==="
ls -la build2/S8Installer.apk
