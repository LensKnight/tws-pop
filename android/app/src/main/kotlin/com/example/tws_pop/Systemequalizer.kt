package com.example.tws_pop

import android.content.Context
import android.media.MediaPlayer
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer

/**
 * Holds the equalizer settings and attaches an Equalizer + BassBoost to the
 * audio sessions of other apps (and to the global mix where the phone allows
 * it). Settings are saved natively so the service can restore them after a
 * restart.
 */
object SystemEqualizer {

    private const val PREFS = "tws_pop_eq"

    private class Effects(val eq: Equalizer?, val bass: BassBoost?)

    // audio session id -> effects. Session 0 is the global output mix.
    private val active = mutableMapOf<Int, Effects>()

    private var appContext: Context? = null
    private var loaded = false

    // A throwaway player whose only job is to give us band info and presets.
    private var probePlayer: MediaPlayer? = null
    private var probeEq: Equalizer? = null
    private var probeBass: BassBoost? = null

    private var enabled = false
    private var levels = IntArray(0)
    private var bassStrength = 0

    @Synchronized
    fun init(context: Context) {
        if (loaded) return

        val ctx = context.applicationContext
        appContext = ctx

        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        enabled = prefs.getBoolean("enabled", false)
        bassStrength = prefs.getInt("bass", 0)
        levels = (prefs.getString("levels", "") ?: "")
            .split(",")
            .mapNotNull { it.trim().toIntOrNull() }
            .toIntArray()

        loaded = true
    }

    private fun save() {
        appContext
            ?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            ?.edit()
            ?.putBoolean("enabled", enabled)
            ?.putInt("bass", bassStrength)
            ?.putString("levels", levels.joinToString(","))
            ?.apply()
    }

    private fun ensureProbe(): Equalizer? {
        probeEq?.let { return it }

        return try {
            val player = MediaPlayer()
            probePlayer = player

            val session = player.audioSessionId
            val eq = Equalizer(0, session)
            probeEq = eq

            probeBass = try {
                BassBoost(0, session)
            } catch (_: Exception) {
                null
            }

            eq
        } catch (_: Exception) {
            null
        }
    }

    private fun syncLevels(eq: Equalizer) {
        val bands = eq.numberOfBands.toInt()

        if (levels.size != bands) {
            levels = IntArray(bands) { band ->
                eq.getBandLevel(band.toShort()).toInt()
            }
        }
    }

    private fun applyTo(fx: Effects) {
        try {
            fx.eq?.let { eq ->
                val bands = eq.numberOfBands.toInt()
                val range = eq.bandLevelRange

                if (levels.size == bands) {
                    for (band in 0 until bands) {
                        val level = levels[band].coerceIn(
                            range[0].toInt(),
                            range[1].toInt()
                        )
                        eq.setBandLevel(band.toShort(), level.toShort())
                    }
                }

                eq.setEnabled(enabled)
            }
        } catch (_: Exception) {
        }

        try {
            fx.bass?.let { bass ->
                if (bass.strengthSupported) {
                    bass.setStrength(bassStrength.toShort())
                    bass.setEnabled(enabled && bassStrength > 0)
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun applyAll() {
        for (fx in active.values) applyTo(fx)
    }

    // ------------------------------------------------------------------
    // Sessions
    // ------------------------------------------------------------------

    @Synchronized
    fun attach(session: Int) {
        if (session < 0 || active.containsKey(session)) return

        val eq = try {
            Equalizer(1000, session)
        } catch (_: Exception) {
            null
        }

        val bass = try {
            BassBoost(1000, session)
        } catch (_: Exception) {
            null
        }

        if (eq == null && bass == null) return

        val fx = Effects(eq, bass)
        active[session] = fx
        applyTo(fx)
    }

    @Synchronized
    fun detach(session: Int) {
        val fx = active.remove(session) ?: return

        try {
            fx.eq?.release()
        } catch (_: Exception) {
        }
        try {
            fx.bass?.release()
        } catch (_: Exception) {
        }
    }

    @Synchronized
    fun releaseAll() {
        for (session in active.keys.toList()) detach(session)
    }

    // ------------------------------------------------------------------
    // Settings used by the app
    // ------------------------------------------------------------------

    @Synchronized
    fun info(): Map<String, Any?> {
        val eq = ensureProbe() ?: return mapOf("available" to false)

        return try {
            syncLevels(eq)

            val range = eq.bandLevelRange

            val bands = (0 until eq.numberOfBands.toInt()).map { band ->
                mapOf(
                    "freq" to eq.getCenterFreq(band.toShort()) / 1000,
                    "level" to levels[band]
                )
            }

            val presets = (0 until eq.numberOfPresets.toInt()).map { preset ->
                eq.getPresetName(preset.toShort())
            }

            mapOf(
                "available" to true,
                "enabled" to enabled,
                "min" to range[0].toInt(),
                "max" to range[1].toInt(),
                "bands" to bands,
                "presets" to presets,
                "bass" to bassStrength,
                "bassSupported" to (probeBass?.strengthSupported == true),
                "sessions" to active.keys.count { it != 0 },
                "global" to active.containsKey(0)
            )
        } catch (_: Exception) {
            mapOf("available" to false)
        }
    }

    @Synchronized
    fun setEnabled(value: Boolean) {
        enabled = value
        save()
        applyAll()
    }

    @Synchronized
    fun isEnabled(): Boolean = enabled

    @Synchronized
    fun setBand(band: Int, level: Int) {
        val eq = ensureProbe() ?: return

        try {
            syncLevels(eq)
        } catch (_: Exception) {
            return
        }

        if (band !in levels.indices) return

        levels[band] = level
        save()
        applyAll()
    }

    @Synchronized
    fun usePreset(index: Int): List<Int> {
        val eq = ensureProbe() ?: return emptyList()

        return try {
            eq.usePreset(index.toShort())

            levels = IntArray(eq.numberOfBands.toInt()) { band ->
                eq.getBandLevel(band.toShort()).toInt()
            }

            save()
            applyAll()
            levels.toList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    @Synchronized
    fun setBass(strength: Int) {
        bassStrength = strength.coerceIn(0, 1000)
        save()
        applyAll()
    }
}