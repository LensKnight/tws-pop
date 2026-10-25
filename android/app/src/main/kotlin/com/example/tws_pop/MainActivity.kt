package com.example.tws_pop

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val eventChannel = "tws_pop/bluetooth"
    private val methodChannel = "tws_pop/overlay"
    private val eqChannel = "tws_pop/eq"

    private val bluetoothPermissionCode = 5011

    private var pendingPermission: MethodChannel.Result? = null

    // ------------------------------------------------------------------
    // Bluetooth runtime permission (needed on Android 12 and above)
    // ------------------------------------------------------------------

    private fun hasBluetoothPermission(): Boolean =
        ConnectionService.hasPermission(this)

    private fun requestBluetoothPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 31 || hasBluetoothPermission()) {
            result.success(mapOf("granted" to true, "permanent" to false))
            return
        }

        if (pendingPermission != null) {
            result.error("BUSY", "A permission request is already open.", null)
            return
        }

        pendingPermission = result

        val permissions = mutableListOf(Manifest.permission.BLUETOOTH_CONNECT)
        if (Build.VERSION.SDK_INT >= 33) {
            // Lets the background notification show.
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        requestPermissions(permissions.toTypedArray(), bluetoothPermissionCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != bluetoothPermissionCode) return

        val result = pendingPermission ?: return
        pendingPermission = null

        val granted = hasBluetoothPermission()

        // After "don't ask again" Android no longer shows the dialog, so the
        // app has to send the user to its settings page instead.
        val permanent = !granted &&
            Build.VERSION.SDK_INT >= 31 &&
            !shouldShowRequestPermissionRationale(Manifest.permission.BLUETOOTH_CONNECT)

        result.success(mapOf("granted" to granted, "permanent" to permanent))
    }

    private fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName")
        )
        startActivity(intent)
    }

    // ------------------------------------------------------------------
    // Keeping the app alive in the background
    // ------------------------------------------------------------------

    private fun isBatteryExempt(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true

        val manager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return manager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryExemption() {
        if (Build.VERSION.SDK_INT < 23 || isBatteryExempt()) return

        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                openAppSettings()
            }
        }
    }

    // Many brands hide an "autostart" screen that decides whether an app may
    // keep running after it is swiped away. Try the known ones.
    private fun openAutostartSettings(): Boolean {
        val screens = listOf(
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.coloros.safecenter" to
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.oppo.safe" to
                "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.vivo.permissionmanager" to
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.samsung.android.lool" to
                "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.asus.mobilemanager" to
                "com.asus.mobilemanager.autostart.AutoStartActivity",
            "com.letv.android.letvsafe" to
                "com.letv.android.letvsafe.AutobootManageActivity"
        )

        for ((pkg, cls) in screens) {
            try {
                startActivity(Intent().setComponent(ComponentName(pkg, cls)))
                return true
            } catch (_: Exception) {
                // Not this brand, try the next one.
            }
        }

        openAppSettings()
        return false
    }

    // ------------------------------------------------------------------
    // Bluetooth helpers
    // ------------------------------------------------------------------

    private fun bluetoothAdapter(): BluetoothAdapter? =
        (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun openBluetoothSettings() {
        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
    }

    // Android 11 and below: toggles directly. Android 12+: opens settings.
    private fun setBluetooth(enable: Boolean, result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("NO_BLUETOOTH", "This device has no Bluetooth.", null)
            return
        }

        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
            try {
                @Suppress("DEPRECATION")
                if (enable) adapter.enable() else adapter.disable()
                result.success(true)
            } catch (e: SecurityException) {
                openBluetoothSettings()
                result.success(false)
            }
        } else {
            openBluetoothSettings()
            result.success(false)
        }
    }

    private fun readBattery(device: BluetoothDevice): Int = try {
        (device.javaClass.getMethod("getBatteryLevel").invoke(device) as? Int) ?: -1
    } catch (_: Exception) {
        -1
    }

    private fun getConnectedDevice(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter()
        if (adapter == null || !adapter.isEnabled || !hasBluetoothPermission()) {
            result.success(null)
            return
        }

        var answered = false
        fun reply(value: Any?) {
            if (!answered) {
                answered = true
                result.success(value)
            }
        }

        val started = try {
            adapter.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                    try {
                        val device = proxy.connectedDevices.firstOrNull()
                        if (device == null) {
                            reply(null)
                        } else {
                            val name = try { device.name } catch (_: SecurityException) { null }
                                ?: "Bluetooth earbuds"
                            reply(mapOf("name" to name, "battery" to readBattery(device)))
                        }
                    } catch (_: SecurityException) {
                        reply(null)
                    } finally {
                        adapter.closeProfileProxy(profile, proxy)
                    }
                }

                override fun onServiceDisconnected(profile: Int) {}
            }, BluetoothProfile.A2DP)
        } catch (_: SecurityException) {
            false
        }

        if (!started) reply(null)
    }

    // ------------------------------------------------------------------
    // System equalizer service
    // ------------------------------------------------------------------

    private fun startEqService() {
        val intent = Intent(this, EqualizerService::class.java)

        try {
            if (Build.VERSION.SDK_INT >= 26) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopEqService() {
        try {
            stopService(Intent(this, EqualizerService::class.java))
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ---------------- Overlay, Bluetooth and saved data ----------------
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" ->
                    result.success(Settings.canDrawOverlays(this))

                "requestOverlayPermission" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    }
                    result.success(null)
                }

                "hasBluetoothPermission" ->
                    result.success(hasBluetoothPermission())

                "requestBluetoothPermission" -> requestBluetoothPermission(result)

                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }

                // Starts or restarts the background watcher. Called right
                // after the Bluetooth permission has been granted.
                "refreshReceivers" -> {
                    ConnectionService.start(this, refresh = true, force = true)
                    result.success(true)
                }

                "isWatcherEnabled" ->
                    result.success(ConnectionService.isEnabled(this))

                "setWatcher" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    ConnectionService.setEnabled(this, enabled)

                    // The service keeps running while the app is open, and is
                    // stopped later if the option is off.
                    if (enabled) ConnectionService.start(this, force = true)
                    result.success(true)
                }

                "isBatteryExempt" -> result.success(isBatteryExempt())

                "requestBatteryExemption" -> {
                    requestBatteryExemption()
                    result.success(true)
                }

                "openAutostartSettings" -> result.success(openAutostartSettings())

                "showPopup" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        result.error(
                            "NO_OVERLAY_PERMISSION",
                            "Enable Display over other apps permission first.",
                            null
                        )
                    } else {
                        val name = call.argument<String>("deviceName")
                            ?: "Bluetooth earbuds"

                        val durationMs = call.argument<Int>("durationMs") ?: 10500
                        val floatingAnimation =
                            call.argument<Boolean>("floatingAnimation") ?: true
                        val style = call.argument<String>("style") ?: "classic"

                        val intent = Intent(this, EarbudPopupService::class.java).apply {
                            putExtra("deviceName", name)
                            putExtra("durationMs", durationMs)
                            putExtra("floatingAnimation", floatingAnimation)
                            putExtra("style", style)
                        }

                        startService(intent)
                        result.success(true)
                    }
                }

                "isBluetoothEnabled" ->
                    result.success(bluetoothAdapter()?.isEnabled == true)

                "setBluetooth" ->
                    setBluetooth(call.argument<Boolean>("enable") ?: true, result)

                "getConnectedDevice" -> getConnectedDevice(result)

                "loadPrefs" -> result.success(
                    getSharedPreferences("tws_pop_prefs", Context.MODE_PRIVATE)
                        .getString("data", null)
                )

                "savePrefs" -> {
                    getSharedPreferences("tws_pop_prefs", Context.MODE_PRIVATE)
                        .edit()
                        .putString("data", call.arguments as? String)
                        .apply()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // ---------------- System equalizer ----------------
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eqChannel
        ).setMethodCallHandler { call, result ->
            SystemEqualizer.init(applicationContext)

            when (call.method) {
                "getEq" -> {
                    val info = SystemEqualizer.info().toMutableMap()
                    info["serviceRunning"] = EqualizerService.running
                    result.success(info)
                }

                "setEqEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    SystemEqualizer.setEnabled(enabled)

                    if (enabled) startEqService() else stopEqService()
                    result.success(true)
                }

                "startService" -> {
                    startEqService()
                    result.success(true)
                }

                "setBand" -> {
                    SystemEqualizer.setBand(
                        call.argument<Int>("band") ?: 0,
                        call.argument<Int>("level") ?: 0
                    )
                    result.success(true)
                }

                "usePreset" ->
                    result.success(
                        SystemEqualizer.usePreset(call.argument<Int>("index") ?: 0)
                    )

                "setBass" -> {
                    SystemEqualizer.setBass(call.argument<Int>("strength") ?: 0)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // ---------------- Events from the background watcher ----------------
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannel
        ).setStreamHandler(object : EventChannel.StreamHandler {

            override fun onListen(
                arguments: Any?,
                events: EventChannel.EventSink?
            ) {
                // While the screen is open the service hands events to Flutter.
                ConnectionHub.sink = { event -> events?.success(event) }
                ConnectionService.start(this@MainActivity, refresh = true, force = true)
            }

            override fun onCancel(arguments: Any?) {
                ConnectionHub.sink = null
                stopWatcherIfDisabled()
            }
        })
    }

    private fun stopWatcherIfDisabled() {
        if (!ConnectionService.isEnabled(applicationContext)) {
            ConnectionService.stop(applicationContext)
        }
    }

    override fun onDestroy() {
        ConnectionHub.sink = null
        stopWatcherIfDisabled()

        super.onDestroy()
    }
}