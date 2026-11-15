package com.xalpati.tabapagos

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.xalpati.tabapagos/native"
    private var toneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
        } catch (e: Exception) {
            e.printStackTrace()
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "beep" -> {
                    try {
                        toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
                        vibrateShort()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BEEP_ERROR", e.message, null)
                    }
                }
                "beepSuccess" -> {
                    try {
                        toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP2, 200)
                        vibrateShort()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BEEP_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun vibrateShort() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator?.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v?.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    v?.vibrate(50)
                }
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            toneGenerator?.release()
            toneGenerator = null
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
