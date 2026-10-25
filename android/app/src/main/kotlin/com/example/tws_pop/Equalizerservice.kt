package com.example.tws_pop

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.audiofx.AudioEffect
import android.os.Build
import android.os.IBinder

/**
 * Keeps the equalizer alive in the background. Music apps announce their
 * audio session with a broadcast; for each one we attach the equalizer.
 */
class EqualizerService : Service() {

    companion object {
        @Volatile
        var running = false

        private const val CHANNEL_ID = "tws_pop_eq"
        private const val NOTIFICATION_ID = 4107
    }

    private var receiverRegistered = false

    private val sessionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return

            val session = intent.getIntExtra(AudioEffect.EXTRA_AUDIO_SESSION, -1)
            if (session <= 0) return

            when (intent.action) {
                AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION ->
                    SystemEqualizer.attach(session)

                AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION ->
                    SystemEqualizer.detach(session)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        SystemEqualizer.init(this)

        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        registerSessionReceiver()

        // Best effort: some phones apply effects on session 0 to all audio.
        SystemEqualizer.attach(0)

        running = true

        // Restart after being killed so the equalizer keeps working.
        return START_STICKY
    }

    private fun registerSessionReceiver() {
        if (receiverRegistered) return

        val filter = IntentFilter().apply {
            addAction(AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION)
            addAction(AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION)
        }

        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(sessionReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(sessionReceiver, filter)
        }

        receiverRegistered = true
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "System equalizer",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("TWS POP equalizer")
            .setContentText("Equalizer is active")
            .setSmallIcon(android.R.drawable.stat_sys_headset)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        running = false

        if (receiverRegistered) {
            try {
                unregisterReceiver(sessionReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }

        SystemEqualizer.releaseAll()

        super.onDestroy()
    }
}