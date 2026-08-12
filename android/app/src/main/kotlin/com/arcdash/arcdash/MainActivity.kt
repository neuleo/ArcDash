package com.arcdash.arcdash

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.arcdash.arcdash/service"
        var activeChannel: MethodChannel? = null

        fun onMacroDroidBroadcast(context: Context, action: String) {
            activeChannel?.invokeMethod("onMacroDroidTrigger", mapOf("action" to action))
        }
    }

    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        activeChannel = methodChannel

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, ArcDashForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(this, intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, ArcDashForegroundService::class.java))
                    result.success(null)
                }
                "updateNotification" -> {
                    val text = call.argument<String>("text") ?: "ArcDash aktiv"
                    val intent = Intent(this, ArcDashForegroundService::class.java).apply {
                        action = ArcDashForegroundService.ACTION_UPDATE_NOTIFICATION
                        putExtra(ArcDashForegroundService.EXTRA_TEXT, text)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(this, intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "vibrateSuccess" -> {
                    vibratePattern(longArrayOf(0, 150, 100, 150)) // 2 short pulses
                    result.success(null)
                }
                "vibrateError" -> {
                    vibratePattern(longArrayOf(0, 400)) // 1 long pulse
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        if (activeChannel == methodChannel) {
            activeChannel = null
        }
        methodChannel = null
        super.onDestroy()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val data: Uri? = intent.data

        if (action == MacroDroidReceiver.ACTION_APPLY_STREET_LEGAL ||
            (data != null && data.scheme == "arcdash" && data.host == "profile" && data.path == "/street_legal")) {
            activeChannel?.invokeMethod(
                "onMacroDroidTrigger",
                mapOf("action" to MacroDroidReceiver.ACTION_APPLY_STREET_LEGAL)
            )
        }
    }

    private fun vibratePattern(pattern: LongArray) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vibratorManager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

        vibrator?.let {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                it.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                it.vibrate(pattern, -1)
            }
        }
    }
}
