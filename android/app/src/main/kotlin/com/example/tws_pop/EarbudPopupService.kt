package com.example.tws_pop

import android.app.Service
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.VideoView
import java.io.File
import java.io.IOException

class EarbudPopupService : Service() {

    private var wm: WindowManager? = null
    private var popup: LinearLayout? = null
    private var videoView: VideoView? = null
    private var batteryText: TextView? = null
    private var batteryIcon: BatteryIconView? = null
    private var closeRunnable: Runnable? = null

    private var isClosing = false
    private var durationMs = 10500L
    private var floatingEnabled = true
    private var styleName = "classic"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        val eventType = intent?.getStringExtra("eventType")

        val level = intent?.getIntExtra("batteryLevel", -1) ?: -1
        val deviceName = intent?.getStringExtra("deviceName")
            ?.takeIf { it.isNotBlank() }
            ?: "Bluetooth earbuds"

        // Battery broadcasts must never open a new popup.
        if (eventType == "battery") {
            if (popup != null && !isClosing) {
                updateBattery(level)
            }
            if (popup == null || isClosing) {
                stopSelf(startId)
            }
            return START_NOT_STICKY
        }

        // Update an already visible popup.
        if (popup != null && !isClosing) {
            updateBattery(level)
            return START_NOT_STICKY
        }

        durationMs = intent?.getIntExtra("durationMs", 10500)?.toLong() ?: 10500L
        floatingEnabled = intent?.getBooleanExtra("floatingAnimation", true) ?: true
        styleName = intent?.getStringExtra("style") ?: "classic"

        // Only connection events should create a popup.
        showPopup(deviceName, level)

        return START_NOT_STICKY
    }

    private enum class DeviceType {
        BOAT,
        SONY,
        ONEPLUS,
        DEFAULT
    }

    private class PopupTheme(
        val card: Int,
        val stroke: Int,
        val strokeDp: Int,
        val title: Int,
        val subtitle: Int,
        val accent: Int,
        val mediaBg: Int,
        val compact: Boolean
    )

    private fun themeFor(style: String): PopupTheme = when (style) {
        "midnight" -> PopupTheme(
            Color.rgb(23, 25, 30), Color.rgb(48, 52, 62), 1,
            Color.WHITE, Color.rgb(150, 155, 167), Color.rgb(87, 145, 255),
            Color.rgb(32, 35, 42), false
        )
        "glow" -> PopupTheme(
            Color.rgb(14, 16, 22), Color.rgb(87, 145, 255), 2,
            Color.WHITE, Color.rgb(150, 155, 167), Color.rgb(120, 170, 255),
            Color.rgb(24, 30, 44), false
        )
        "compact" -> PopupTheme(
            Color.WHITE, Color.rgb(232, 232, 238), 1,
            Color.rgb(28, 28, 30), Color.rgb(120, 120, 130), Color.rgb(45, 110, 245),
            Color.rgb(248, 248, 250), true
        )
        else -> PopupTheme(
            Color.WHITE, Color.rgb(232, 232, 238), 1,
            Color.rgb(28, 28, 30), Color.rgb(120, 120, 130), Color.rgb(45, 110, 245),
            Color.rgb(248, 248, 250), false
        )
    }


    private fun detectDeviceType(deviceName: String): DeviceType {
        val name = deviceName.lowercase()

        return when {
            "airdopes 219" in name || "airdopes219" in name ->
                DeviceType.BOAT

            "wh-ch720n" in name || "wh720n" in name ->
                DeviceType.SONY

            "oneplus nord buds" in name ||
            "nord buds 2r" in name ->
                DeviceType.ONEPLUS

            else -> DeviceType.DEFAULT
        }
    }


    private fun showPopup(deviceName: String, level: Int) {
        val theme = themeFor(styleName)
        val deviceType = detectDeviceType(deviceName)
        val subtitleText = when (deviceType) {
            DeviceType.BOAT -> "Your music. Your vibe."
            DeviceType.SONY -> "Premium sound. Pure silence."
            DeviceType.ONEPLUS -> "Smooth sound. Seamless vibes."
            DeviceType.DEFAULT -> "Connected. Ready to play."
        }

        val manager = getSystemService(WINDOW_SERVICE) as WindowManager
        wm = manager

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(22), dp(22), dp(22), dp(20))
            background = roundedBackground(
                theme.card,
                dp(28),
                theme.stroke,
                theme.strokeDp
            )
            elevation = dp(16).toFloat()
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        val statusDot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.rgb(52, 199, 89))
            }
        }

        header.addView(
            statusDot,
            LinearLayout.LayoutParams(dp(7), dp(7)).apply {
                rightMargin = dp(7)
            }
        )

        val title = TextView(this).apply {
            text = "NEW CONNECTION"
            textSize = 11f
            letterSpacing = 0.13f
            setTextColor(theme.accent)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }

        header.addView(title)
        card.addView(header)

        val videoContainer = FrameLayout(this).apply {
            background = roundedBackground(
                theme.mediaBg,
                dp(20),
                Color.TRANSPARENT
            )
            clipToOutline = true
        }

        val video = VideoView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            alpha = 1f
        }

        // The compact style has no artwork area at all.
        if (!theme.compact) {
            videoView = video

            videoContainer.addView(
                video,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    Gravity.CENTER
                )
            )

            card.addView(
                videoContainer,
                LinearLayout.LayoutParams(dp(190), dp(135)).apply {
                    topMargin = dp(15)
                    bottomMargin = dp(17)
                }
            )
        }

        val name = TextView(this).apply {
            text = deviceName
            textSize = 20f
            setTextColor(theme.title)
            typeface = Typeface.create(
                "sans-serif-medium",
                Typeface.NORMAL
            )
            gravity = Gravity.CENTER
            maxLines = 2
            setPadding(dp(4), if (theme.compact) dp(12) else 0, dp(4), 0)
        }

        card.addView(
            name,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        val subtitle = TextView(this).apply {
            text = subtitleText
            textSize = 13f
            setTextColor(theme.subtitle)
            gravity = Gravity.CENTER
            setPadding(0, dp(5), 0, dp(17))
        }

        card.addView(subtitle)

        // Compact battery row with a proper battery-shaped icon.
        val batteryRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val batteryLabel = TextView(this).apply {
            text = "BATTERY"
            textSize = 10f
            letterSpacing = 0.08f
            setTextColor(theme.subtitle)
            typeface = Typeface.DEFAULT_BOLD
        }

        batteryRow.addView(
            batteryLabel,
            LinearLayout.LayoutParams(0, dp(26), 1f)
        )

        val icon = BatteryIconView(this)
        batteryIcon = icon

        batteryRow.addView(
            icon,
            LinearLayout.LayoutParams(dp(29), dp(16)).apply {
                rightMargin = dp(8)
            }
        )

        val percent = TextView(this).apply {
            textSize = 13f
            setTextColor(theme.title)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER_VERTICAL
        }

        batteryText = percent

        batteryRow.addView(
            percent,
            LinearLayout.LayoutParams(
                dp(43),
                dp(26)
            )
        )

        card.addView(
            batteryRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(26)
            )
        )

        updateBattery(level)

        val params = WindowManager.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.90f).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(36)
        }

        try {
            isClosing = false
            popup = card

            manager.addView(card, params)

            // Slide only. No card fade and no video fade.
            card.translationY = dp(35).toFloat()
            card.animate()
                .translationY(0f)
                .setDuration(350)
                .setInterpolator(AccelerateDecelerateInterpolator())
                .start()

            if (!theme.compact) {
                when (deviceType) {
                    DeviceType.BOAT,
                    DeviceType.ONEPLUS -> playVideo(video, deviceType)

                    DeviceType.SONY,
                    DeviceType.DEFAULT -> {
                        videoContainer.removeView(video)
                        videoView = null
                        showDeviceAnimation(videoContainer, deviceType)
                    }
                }
            }

            val timeout = Runnable {
                closePopup(card)
            }

            closeRunnable = timeout
            card.postDelayed(timeout, durationMs)

        } catch (e: Exception) {
            Log.e("TWS_POP", "Could not display popup", e)
            cleanup(card)
            stopSelf()
        }
    }

    private fun showDeviceAnimation(
        container: FrameLayout,
        deviceType: DeviceType
    ) {
        val imageRes = when (deviceType) {
            DeviceType.SONY -> R.drawable.sony_headphones
            DeviceType.DEFAULT -> R.drawable.default_earbuds
            DeviceType.ONEPLUS -> R.drawable.oneplus_nord_buds_2r
            DeviceType.BOAT -> return
        }

        val image = ImageView(this).apply {
            setImageResource(imageRes)
            scaleType = ImageView.ScaleType.FIT_CENTER
            alpha = 1f
        }

        container.addView(
            image,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        )

        // Respect the "Floating artwork animation" setting.
        if (!floatingEnabled) return

        // Gentle floating animation — no fade.
        image.animate().cancel()
        image.translationY = 0f

        showFloatingLoop(image)
    }

    private fun showFloatingLoop(image: ImageView) {
        if (popup == null || isClosing || image.parent == null) return

        image.animate()
            .translationY(-dp(8).toFloat())
            .setDuration(1000L)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .withEndAction {
                if (popup != null && !isClosing && image.parent != null) {
                    image.animate()
                        .translationY(0f)
                        .setDuration(1000L)
                        .setInterpolator(AccelerateDecelerateInterpolator())
                        .withEndAction {
                            showFloatingLoop(image)
                        }
                        .start()
                }
            }
            .start()
    }

    private fun playVideo(video: VideoView, deviceType: DeviceType) {
        try {
            val videoName = when (deviceType) {
                DeviceType.BOAT -> "opening.mp4"
                DeviceType.ONEPLUS -> "oneplus_nord_buds.mp4"
                DeviceType.SONY, DeviceType.DEFAULT -> null
            }

            // Sony ke liye video nahi hai
            if (videoName == null) {
                video.visibility = View.GONE
                return
            }

            video.visibility = View.VISIBLE

            val videoFile = File(cacheDir, videoName)

            if (!videoFile.exists() || videoFile.length() == 0L) {
                val tempFile = File(cacheDir, "${videoName}_temp")

                assets.open(videoName).use { input ->
                    tempFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }

                if (!tempFile.exists() || tempFile.length() == 0L) {
                    throw IOException("Copied video file is empty")
                }

                if (!tempFile.renameTo(videoFile)) {
                    tempFile.copyTo(videoFile, overwrite = true)
                    tempFile.delete()
                }
            }

            video.setOnPreparedListener { player ->
                if (videoView !== video || popup == null || isClosing) {
                    player.release()
                    return@setOnPreparedListener
                }

                player.isLooping = true
                video.alpha = 1f
                player.start()
            }

            video.setOnErrorListener { _, what, extra ->
                Log.e(
                    "TWS_POP_VIDEO",
                    "Playback error: what=$what, extra=$extra"
                )
                true
            }

            video.setVideoURI(Uri.fromFile(videoFile))

        } catch (e: Exception) {
            Log.e("TWS_POP_VIDEO", "Video initialization failed", e)
        }
    }

    private fun updateBattery(level: Int) {
        val valid = level in 0..100

        batteryText?.visibility =
            if (valid) View.VISIBLE else View.GONE

        batteryIcon?.visibility =
            if (valid) View.VISIBLE else View.GONE

        if (!valid) return

        batteryText?.text = "$level%"
        batteryIcon?.setLevel(level)
    }

    private fun closePopup(card: LinearLayout) {
        if (popup !== card || isClosing) return

        isClosing = true

        closeRunnable?.let { card.removeCallbacks(it) }
        closeRunnable = null

        card.animate().cancel()

        // Slide down only; no fade.
        card.animate()
            .translationY(dp(35).toFloat())
            .setDuration(280)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .withEndAction {
                cleanup(card)
                stopSelf()
            }
            .start()
    }

    private fun cleanup(card: LinearLayout) {
        closeRunnable?.let { card.removeCallbacks(it) }
        closeRunnable = null

        card.animate().cancel()

        try {
            videoView?.stopPlayback()
        } catch (e: Exception) {
            Log.w("TWS_POP_VIDEO", "Video cleanup issue", e)
        }

        try {
            if (card.parent != null) {
                wm?.removeView(card)
            }
        } catch (e: Exception) {
            Log.w("TWS_POP", "Popup already removed", e)
        }

        if (popup === card) {
            popup = null
            videoView = null
            batteryText = null
            batteryIcon = null
        }

        isClosing = false
    }

    private fun roundedBackground(
        color: Int,
        radius: Int,
        strokeColor: Int,
        strokeDp: Int = 1
    ): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius.toFloat()

            if (strokeColor != Color.TRANSPARENT) {
                setStroke(dp(strokeDp), strokeColor)
            }
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    // Draws a battery outline, terminal and coloured charge fill.
    private inner class BatteryIconView(
        context: android.content.Context
    ) : View(context) {

        private var level = 0

        private val outlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dp(1.5f).toFloat()
            color = Color.rgb(100, 100, 110)
        }

        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }

        private val outline = RectF()
        private val fill = RectF()

        fun setLevel(value: Int) {
            level = value.coerceIn(0, 100)
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)

            val terminalWidth = width * 0.10f
            val left = dp(1f).toFloat()
            val top = height * 0.16f
            val right = width - terminalWidth - dp(2f)
            val bottom = height * 0.84f
            val radius = dp(2f).toFloat()

            outline.set(left, top, right, bottom)

            canvas.drawRoundRect(
                outline,
                radius,
                radius,
                outlinePaint
            )

            val terminal = RectF(
                right + dp(1f).toFloat(),
                height * 0.35f,
                width - dp(1f).toFloat(),
                height * 0.65f
            )

            fillPaint.color = Color.rgb(100, 100, 110)
            canvas.drawRoundRect(
                terminal,
                dp(1f).toFloat(),
                dp(1f).toFloat(),
                fillPaint
            )

            val inset = dp(2.5f).toFloat()
            val availableWidth = right - left - inset * 2
            val fillWidth = availableWidth * level / 100f

            fill.set(
                left + inset,
                top + inset,
                left + inset + fillWidth,
                bottom - inset
            )

            fillPaint.color = when {
                level <= 20 -> Color.rgb(255, 69, 58)
                level <= 50 -> Color.rgb(255, 159, 10)
                else -> Color.rgb(52, 199, 89)
            }

            if (fillWidth > 0f) {
                canvas.drawRoundRect(
                    fill,
                    dp(1f).toFloat(),
                    dp(1f).toFloat(),
                    fillPaint
                )
            }
        }
    }

    private fun dp(value: Float): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onDestroy() {
        val currentPopup = popup

        if (currentPopup != null) {
            cleanup(currentPopup)
        } else {
            closeRunnable = null
            videoView = null
            batteryText = null
            batteryIcon = null
        }

        wm = null
        super.onDestroy()
    }
}