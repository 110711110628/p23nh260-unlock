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
