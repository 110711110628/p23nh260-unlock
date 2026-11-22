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
