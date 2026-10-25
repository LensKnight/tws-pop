package com.example.tws_pop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Starts the earbuds watcher again after a restart or an app update. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> ConnectionService.start(context)
        }
    }
}