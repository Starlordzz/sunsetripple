package com.wt.intercom.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager

enum class AudioFocusRequestState { GRANTED, DELAYED, DENIED }

object AudioFocusChange {
    const val focusGain = AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
    const val pauseWhenDucked = true

    fun interrupted(focusChange: Int): Boolean? = when (focusChange) {
        AudioManager.AUDIOFOCUS_GAIN -> false
        AudioManager.AUDIOFOCUS_LOSS,
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
        AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> true
        else -> null
    }

    fun requestState(requestResult: Int): AudioFocusRequestState = when (requestResult) {
        AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> AudioFocusRequestState.GRANTED
        AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> AudioFocusRequestState.DELAYED
        else -> AudioFocusRequestState.DENIED
    }
}

class AudioFocusController(context: Context) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var request: AudioFocusRequest? = null

    fun request(onInterrupted: (Boolean) -> Unit): AudioFocusRequestState {
        abandon()
        val focusRequest = AudioFocusRequest.Builder(AudioFocusChange.focusGain)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAcceptsDelayedFocusGain(true)
            .setWillPauseWhenDucked(AudioFocusChange.pauseWhenDucked)
            .setOnAudioFocusChangeListener { change ->
                AudioFocusChange.interrupted(change)?.let(onInterrupted)
            }
            .build()
        request = focusRequest
        return AudioFocusChange.requestState(audioManager.requestAudioFocus(focusRequest))
    }

    fun abandon() {
        request?.let(audioManager::abandonAudioFocusRequest)
        request = null
    }
}
