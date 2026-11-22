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
