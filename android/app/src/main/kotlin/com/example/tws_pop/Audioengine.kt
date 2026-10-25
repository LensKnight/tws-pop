package com.example.tws_pop

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.net.Uri

/**
 * Small in-app music engine: a queue played through one MediaPlayer, with a
 * hardware Equalizer and BassBoost attached to that player's audio session.
 * No plugins required.
 */
class AudioEngine(private val context: Context) {

    private val uris = mutableListOf<Uri>()
    private var player: MediaPlayer? = null
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null

    private var index = -1
    private var prepared = false
    private var bassStrength = 0

    private fun ensurePlayer(): MediaPlayer {
        player?.let { return it }

        val p = MediaPlayer()
        p.setOnCompletionListener { playNextAuto() }
        p.setOnErrorListener { _, _, _ ->
            prepared = false
            true
        }
        player = p

        val session = p.audioSessionId

        equalizer = try {
            Equalizer(0, session).also { it.setEnabled(true) }
        } catch (_: Exception) {
            null
        }

        bassBoost = try {
            BassBoost(0, session).also { it.setEnabled(false) }
        } catch (_: Exception) {
            null
        }

        return p
    }

    // ------------------------------------------------------------------
    // Queue and playback
    // ------------------------------------------------------------------

    fun addTracks(newUris: List<Uri>) {
        uris.addAll(newUris)
    }

    fun playIndex(i: Int): Boolean {
        if (i !in uris.indices) return false

        val p = ensurePlayer()
        index = i

        return try {
            p.reset()
            p.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            p.setDataSource(context, uris[i])
            p.prepare()
            p.start()
            prepared = true
            true
        } catch (_: Exception) {
            prepared = false
            false
        }
    }

    private fun playNextAuto() {
        if (uris.isEmpty()) return
        playIndex((index + 1) % uris.size)
    }

    fun togglePlay(): Boolean {
        if (uris.isEmpty()) return false

        val p = ensurePlayer()

        if (!prepared) {
            return playIndex(if (index in uris.indices) index else 0)
        }

        return try {
            if (p.isPlaying) {
                p.pause()
                false
            } else {
                p.start()
                true
            }
        } catch (_: IllegalStateException) {
            false
        }
    }

    fun next(): Boolean {
        if (uris.isEmpty()) return false
        return playIndex((index + 1) % uris.size)
    }

    fun previous(): Boolean {
        if (uris.isEmpty()) return false

        val p = player
        if (prepared && p != null) {
            val position = try {
                p.currentPosition
            } catch (_: Exception) {
                0
            }

            // Like most players: restart the song first, go back if near start.
            if (position > 3000) {
                p.seekTo(0)
                return true
            }
        }

        return playIndex((index - 1 + uris.size) % uris.size)
    }

    fun seekTo(ms: Int) {
        val p = player ?: return
        if (!prepared) return

        try {
            p.seekTo(ms)
        } catch (_: IllegalStateException) {
        }
    }

    fun clear() {
        try {
            player?.reset()
        } catch (_: Exception) {
        }

        prepared = false
        index = -1
        uris.clear()
    }

    fun state(): Map<String, Any> {
        val p = player

        var playing = false
        var position = 0
        var duration = 0

        if (p != null && prepared) {
            try {
                playing = p.isPlaying
                position = p.currentPosition
                duration = p.duration
            } catch (_: IllegalStateException) {
            }
        }

        return mapOf(
            "index" to index,
            "playing" to playing,
            "position" to position,
            "duration" to duration,
            "count" to uris.size
        )
    }

    // ------------------------------------------------------------------
    // Equalizer and bass boost
    // ------------------------------------------------------------------

    fun eqInfo(): Map<String, Any?> {
        ensurePlayer()

        val eq = equalizer ?: return mapOf("available" to false)

        return try {
            val range = eq.bandLevelRange

            val bands = (0 until eq.numberOfBands.toInt()).map { band ->
                mapOf(
                    "freq" to eq.getCenterFreq(band.toShort()) / 1000,
                    "level" to eq.getBandLevel(band.toShort()).toInt()
                )
            }

            val presets = (0 until eq.numberOfPresets.toInt()).map { preset ->
                eq.getPresetName(preset.toShort())
            }

            mapOf(
                "available" to true,
                "enabled" to eq.getEnabled(),
                "min" to range[0].toInt(),
                "max" to range[1].toInt(),
                "bands" to bands,
                "presets" to presets,
                "bass" to bassStrength,
                "bassSupported" to (bassBoost?.strengthSupported == true)
            )
        } catch (_: Exception) {
            mapOf("available" to false)
        }
    }

    fun setEqEnabled(enabled: Boolean) {
        try {
            equalizer?.setEnabled(enabled)
        } catch (_: Exception) {
        }
    }

    fun setBand(band: Int, level: Int) {
        try {
            equalizer?.setBandLevel(band.toShort(), level.toShort())
        } catch (_: Exception) {
        }
    }

    fun usePreset(presetIndex: Int): List<Int> {
        val eq = equalizer ?: return emptyList()

        return try {
            eq.usePreset(presetIndex.toShort())

            (0 until eq.numberOfBands.toInt()).map { band ->
                eq.getBandLevel(band.toShort()).toInt()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun setBass(strength: Int) {
        val boost = bassBoost ?: return
        bassStrength = strength.coerceIn(0, 1000)

        try {
            if (boost.strengthSupported) {
                boost.setStrength(bassStrength.toShort())
                boost.setEnabled(bassStrength > 0)
            }
        } catch (_: Exception) {
        }
    }

    fun release() {
        try {
            equalizer?.release()
        } catch (_: Exception) {
        }
        try {
            bassBoost?.release()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }

        equalizer = null
        bassBoost = null
        player = null
        prepared = false
    }
}