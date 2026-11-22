#!/bin/bash
# 给静默安装器加详细日志并重建
set -e
cd /root/s8/silent/src/com/s8/silentinstaller

cat > Installer.java <<'JAVA'
package com.s8.silentinstaller;

import android.content.Context;
import android.content.Intent;
import android.app.PendingIntent;
import android.content.pm.PackageInstaller;
import android.net.Uri;
import android.util.Log;
import java.io.File;
import java.io.InputStream;
import java.io.OutputStream;

public class Installer {
    static final String TAG = "S8Installer";
    static final String ACTION_RESULT = "com.s8.silentinstaller.RESULT";

    static void installFile(Context ctx, File f) {
        try {
            install(ctx, Uri.fromFile(f));
        } catch (Exception e) {
            Log.e(TAG, "installFile " + f + " failed", e);
        }
    }

    static void install(Context ctx, Uri uri) throws Exception {
        Log.i(TAG, "install start uri=" + uri);
        PackageInstaller pi = ctx.getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams sp =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        int sid = pi.createSession(sp);
        Log.i(TAG, "session created sid=" + sid);
        InputStream in = ctx.getContentResolver().openInputStream(uri);
        Log.i(TAG, "input stream opened: " + in);
        if (in == null) {
            throw new Exception("openInputStream returned null");
        }
        try (PackageInstaller.Session s = pi.openSession(sid)) {
            try (OutputStream out = s.openWrite("base.apk", 0, -1)) {
                byte[] buf = new byte[1 << 16];
                int n;
                long total = 0;
                while ((n = in.read(buf)) > 0) {
                    out.write(buf, 0, n);
                    total += n;
                }
                s.fsync(out);
                Log.i(TAG, "wrote " + total + " bytes, fsync done");
            } finally {
                in.close();
            }
            Intent intent = new Intent(ACTION_RESULT).setPackage(ctx.getPackageName());
            PendingIntent pi2 = PendingIntent.getBroadcast(ctx, sid, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
            s.commit(pi2.getIntentSender());
            Log.i(TAG, "commit sent session=" + sid);
        }
    }
}
JAVA

cat > ResultReceiver.java <<'JAVA'
package com.s8.silentinstaller;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.util.Log;
import android.widget.Toast;

public class ResultReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context c, Intent i) {
        int status = i.getIntExtra(PackageInstaller.EXTRA_STATUS, -999);
        String msg = i.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
        String pkg = i.getStringExtra(PackageInstaller.EXTRA_PACKAGE_NAME);
        Log.i("S8Installer", "RESULT status=" + status + " msg=" + msg + " pkg=" + pkg);
        String text = (status == PackageInstaller.STATUS_SUCCESS)
                ? ("安装成功: " + pkg) : ("安装结果(" + status + "): " + msg);
        Toast.makeText(c, text, Toast.LENGTH_LONG).show();
    }
}
JAVA

echo "=== 重建 ==="
cd /root/s8/silent
bash build_apk2.sh 2>&1 | tail -4
ls -la build2/S8Installer.apk
