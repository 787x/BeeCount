package com.tntlikely.beecount

import android.Manifest
import android.content.ComponentName
import android.provider.Settings
import android.util.Log
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** One main-thread session, released on every terminal path. */
class SpeechRecognitionBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.tntlikely.beecount/speech")
    private var recognizer: SpeechRecognizer? = null
    private var pending: MethodChannel.Result? = null
    private var sessionId: Long? = null
    private var speechStarted = false
    private var engine = "system"

    private fun onDeviceAvailable(): Boolean = try {
        Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
    } catch (_: Exception) { false }

    private fun systemAvailable(): Boolean = try {
        val selected = Settings.Secure.getString(context.contentResolver, "voice_recognition_service")
        val component = selected?.let { ComponentName.unflattenFromString(it) }
        component != null && SpeechRecognizer.isRecognitionAvailable(context) &&
            context.packageManager.getServiceInfo(component, 0).let { it.enabled && it.applicationInfo.enabled }
    } catch (_: Exception) { false }

    init {
        // Default MethodChannel dispatch and RecognitionListener callbacks use the main thread.
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "availability" -> result.success(mapOf(
                    "systemAvailable" to systemAvailable(),
                    "onDeviceAvailable" to onDeviceAvailable()))
                "startListening" -> start(call.argument<Boolean>("onDevice") == true,
                    call.argument<String>("language"), call.argument<Number>("sessionId")?.toLong(), result)
                "stopListening" -> {
                    try {
                        if (sessionId == call.argument<Number>("sessionId")?.toLong()) recognizer?.stopListening()
                    }
                    catch (_: Exception) { finish(error = "unknown") }
                    result.success(null)
                }
                "cancelListening" -> {
                    // A dialog can dispose after its successor starts. Never cancel that successor.
                    if (sessionId == call.argument<Number>("sessionId")?.toLong()) finish(error = "cancelled")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start(onDevice: Boolean, language: String?, id: Long?, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", null, null); return }
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("permission_denied", null, null); return
        }
        if (onDevice && !onDeviceAvailable()) { result.error("on_device_unavailable", null, mapOf("speechStarted" to false)); return }
        if (!onDevice && !systemAvailable()) {
            result.error("system_unavailable", null, mapOf("speechStarted" to false)); return
        }
        pending = result
        sessionId = id
        speechStarted = false
        engine = if (onDevice) "onDevice" else "system"
        try {
            val speech = if (onDevice && Build.VERSION.SDK_INT >= 31)
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            else SpeechRecognizer.createSpeechRecognizer(context)
            recognizer = speech
            speech.setRecognitionListener(object : RecognitionListener {
                // Ignore late callbacks from a disposed previous session.
                private fun active() = recognizer === speech
                override fun onResults(results: Bundle?) {
                    if (!active()) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()
                    if (text.isNullOrEmpty()) finish(error = "no_match") else finish(text = text)
                }
                override fun onError(error: Int) {
                    if (!active()) return
                    finish(androidError = error, error = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission_denied"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "no_match"
                        SpeechRecognizer.ERROR_CLIENT -> "client"
                        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "language_unsupported"
                        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "language_unavailable"
                        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "too_many_requests"
                        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "support_unavailable"
                        SpeechRecognizer.ERROR_CANNOT_LISTEN_TO_DOWNLOAD_EVENTS -> "download_events_unavailable"
                        SpeechRecognizer.ERROR_AUDIO -> "audio"
                        SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network"
                        SpeechRecognizer.ERROR_SERVER, SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "server"
                        else -> "unknown"
                    })
                }
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() { if (active()) speechStarted = true }
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {
                    if (active() && partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.any { it.isNotBlank() } == true) speechStarted = true
                }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            speech.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                language?.takeIf { it.isNotBlank() }?.let { putExtra(RecognizerIntent.EXTRA_LANGUAGE, it) }
            })
        } catch (_: SecurityException) { finish(error = "permission_denied") }
        catch (_: Exception) { finish(error = "unavailable") }
    }

    private fun finish(text: String? = null, error: String? = null, androidError: Int? = null) {
        val result = pending
        pending = null
        sessionId = null
        val speech = recognizer
        recognizer = null
        try { speech?.cancel() } catch (_: Exception) {}
        try { speech?.destroy() } catch (_: Exception) {}
        if (error != null) {
            Log.i("BeeCountSpeech", "engine=$engine error=$error speechStarted=$speechStarted androidError=$androidError")
            result?.error(error, null, mapOf("speechStarted" to speechStarted, "androidError" to androidError))
        } else result?.success(text)
    }

    fun dispose() {
        finish(error = "cancelled")
        channel.setMethodCallHandler(null)
    }
}
