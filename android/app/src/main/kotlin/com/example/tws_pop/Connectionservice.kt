package com.example.tws_pop

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bridge between the background service and the Flutter screen. While the app
 * is open [sink] is set and Flutter handles popups and history itself. When
 * the app is closed [sink] is null and the service does that work alone.
 */
object ConnectionHub {
    @Volatile
    var sink: ((Map<String, Any?>) -> Unit)? = null
}

/**
 * Foreground service that listens for earbuds connecting, disconnecting and
 * battery changes, so the popup works even after the app is swiped away.
 */
class ConnectionService : Service() {

    companion object {
        @Volatile
        var running = false

        const val ACTION_REFRESH = "com.example.tws_pop.REFRESH_RECEIVERS"

        private const val CHANNEL_ID = "tws_pop_watch"
        private const val NOTIFICATION_ID = 4108
        private const val PREFS = "tws_pop_prefs"

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun isEnabled(context: Context): Boolean =
            prefs(context).getBoolean("watcher", true)

        fun setEnabled(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean("watcher", enabled).apply()
        }

        fun hasPermission(context: Context): Boolean =
            Build.VERSION.SDK_INT < 31 ||
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED

        /**
         * Starts the service. [force] starts it even when the background
         * option is off (used while the app itself is open).
         */
        fun start(
            context: Context,
            refresh: Boolean = false,
            force: Boolean = false
        ) {
            if (!force && !isEnabled(context)) return
            if (!hasPermission(context)) return

            val intent = Intent(context, ConnectionService::class.java)
            if (refresh) intent.action = ACTION_REFRESH

            try {
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, ConnectionService::class.java))
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private var registered = false

    // Name of the audio device currently connected, tracked in every mode.
    @Volatile
    private var connectedName: String? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return

            when (intent.action) {
                BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED,
                BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED ->
                    handleAudio(intent)

                "android.bluetooth.device.action.BATTERY_LEVEL_CHANGED" ->
                    handleBattery(intent)

                BluetoothAdapter.ACTION_STATE_CHANGED ->
                    handleAdapter(intent)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()

        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // For example: Bluetooth permission missing on Android 14.
            e.printStackTrace()
            stopSelf()
            return START_NOT_STICKY
        }

        registerReceivers(force = intent?.action == ACTION_REFRESH)
        primeConnectedDevice()

        running = true

        // The system restarts the service if it gets killed.
        return START_STICKY
    }

    // ------------------------------------------------------------------
    // Receivers
    // ------------------------------------------------------------------

    private fun registerReceivers(force: Boolean) {
        if (registered) {
            if (!force) return

            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            registered = false
        }

        val filter = IntentFilter().apply {
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            addAction("android.bluetooth.device.action.BATTERY_LEVEL_CHANGED")
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        }

        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }

        registered = true
    }

    private fun deviceFrom(intent: Intent): BluetoothDevice? {
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(
                BluetoothDevice.EXTRA_DEVICE,
                BluetoothDevice::class.java
            )
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
    }

    private fun nameOf(device: BluetoothDevice?): String {
        return try {
            device?.name ?: "Bluetooth earbuds"
        } catch (_: SecurityException) {
            "Bluetooth earbuds"
        }
    }

    private fun readBattery(device: BluetoothDevice): Int = try {
        (device.javaClass.getMethod("getBatteryLevel").invoke(device) as? Int) ?: -1
    } catch (_: Exception) {
        -1
    }

    private fun handleAudio(intent: Intent) {
        val device = deviceFrom(intent)

        val state = intent.getIntExtra(
            BluetoothProfile.EXTRA_STATE,
            BluetoothProfile.STATE_DISCONNECTED
        )

        if (state != BluetoothProfile.STATE_CONNECTED &&
            state != BluetoothProfile.STATE_DISCONNECTED
        ) return

        val connected = state == BluetoothProfile.STATE_CONNECTED
        val name = nameOf(device)
        val battery = if (connected && device != null) readBattery(device) else -1

        val sink = ConnectionHub.sink

        // App open: pass the raw event on. Flutter shows the popup itself.
        sink?.invoke(
            mapOf(
                "name" to name,
                "connected" to connected,
                "type" to "audio"
            )
        )

        val same = connectedName?.equals(name, ignoreCase = true) == true

        if (connected) {
            // A2DP and Headset both report the same device: ignore the repeat.
            if (same) return
            connectedName = name
        } else {
            if (!same) return
            connectedName = null
        }

        if (sink != null) return

        // App closed: the service does the work on its own.
        recordHistory(name, connected)
        if (connected) showPopup(name, battery)
    }

    private fun handleBattery(intent: Intent) {
        val level = intent.getIntExtra(
            "android.bluetooth.device.extra.BATTERY_LEVEL",
            -1
        )
        if (level !in 0..100) return

        val name = nameOf(deviceFrom(intent))

        ConnectionHub.sink?.invoke(
            mapOf("type" to "battery", "name" to name, "battery" to level)
        )

        // Updates the battery on a popup that is already on screen.
        try {
            startService(
                Intent(this, EarbudPopupService::class.java).apply {
                    putExtra("eventType", "battery")
                    putExtra("deviceName", name)
                    putExtra("batteryLevel", level)
                }
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun handleAdapter(intent: Intent) {
        val state = intent.getIntExtra(
            BluetoothAdapter.EXTRA_STATE,
            BluetoothAdapter.ERROR
        )

        if (state != BluetoothAdapter.STATE_ON &&
            state != BluetoothAdapter.STATE_OFF
        ) return

        if (state == BluetoothAdapter.STATE_OFF) {
            val name = connectedName
            connectedName = null

            if (name != null && ConnectionHub.sink == null) {
                recordHistory(name, false)
            }
        }

        ConnectionHub.sink?.invoke(
            mapOf(
                "type" to "bluetoothState",
                "enabled" to (state == BluetoothAdapter.STATE_ON)
            )
        )
    }

    /** Remembers a device that was already connected when the service started. */
    private fun primeConnectedDevice() {
        if (connectedName != null || !hasPermission(this)) return

        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            ?.adapter

        if (adapter == null || !adapter.isEnabled) return

        try {
            adapter.getProfileProxy(
                this,
                object : BluetoothProfile.ServiceListener {
                    override fun onServiceConnected(
                        profile: Int,
                        proxy: BluetoothProfile
                    ) {
                        try {
                            val device = proxy.connectedDevices.firstOrNull()
                            if (device != null && connectedName == null) {
                                connectedName = nameOf(device)
                            }
                        } catch (_: SecurityException) {
                        } finally {
                            adapter.closeProfileProxy(profile, proxy)
                        }
                    }

                    override fun onServiceDisconnected(profile: Int) {}
                },
                BluetoothProfile.A2DP
            )
        } catch (_: SecurityException) {
        }
    }

    // ------------------------------------------------------------------
    // Work done when the app is closed
    // ------------------------------------------------------------------

    private fun readSettings(): JSONObject {
        return try {
            JSONObject(prefs(this).getString("data", null) ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun recordHistory(name: String, connected: Boolean) {
        try {
            val root = readSettings()
            val old = root.optJSONArray("history") ?: JSONArray()

            val list = JSONArray()
            list.put(
                JSONObject()
                    .put("n", name)
                    .put("c", connected)
                    .put("t", System.currentTimeMillis())
            )

            for (i in 0 until minOf(old.length(), 19)) {
                list.put(old.get(i))
            }

            root.put("history", list)
            prefs(this).edit().putString("data", root.toString()).apply()
        } catch (_: Exception) {
        }
    }

    private fun showPopup(name: String, battery: Int) {
        if (!Settings.canDrawOverlays(this)) return

        val settings = readSettings()
        if (!settings.optBoolean("popupEnabled", true)) return

        val durationMs = (settings.optDouble("duration", 10.0) * 1000).toInt()
        val floating = settings.optBoolean("floating", true)
        val style = settings.optString("style", "classic")

        try {
            startService(
                Intent(this, EarbudPopupService::class.java).apply {
                    putExtra("deviceName", name)
                    putExtra("batteryLevel", battery)
                    putExtra("durationMs", durationMs)
                    putExtra("floatingAnimation", floating)
                    putExtra("style", style)
                }
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ------------------------------------------------------------------
    // Notification (Android requires one for a foreground service)
    // ------------------------------------------------------------------

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Earbuds watcher",
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
            .setContentTitle("TWS POP")
            .setContentText("Watching for your earbuds")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        running = false

        if (registered) {
            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            registered = false
        }

        super.onDestroy()
    }
}