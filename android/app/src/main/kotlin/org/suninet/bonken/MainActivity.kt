package org.suninet.bonken

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Self-written screen-brightness channel (no third-party dependency).
        // Channel name is derived from the runtime application id so it matches
        // the Dart side (package_info's packageName) without hardcoding it.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "${applicationContext.packageName}/brightness",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setMax" -> {
                    setWindowBrightness(1f)
                    result.success(null)
                }
                "reset" -> {
                    setWindowBrightness(WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Window-level brightness needs no permission and is auto-released by the OS
    // when the window loses focus. `setMax` -> full; `reset` -> BRIGHTNESS_OVERRIDE_NONE
    // hands control back to the system.
    private fun setWindowBrightness(value: Float) {
        window.attributes = window.attributes.apply { screenBrightness = value }
    }
}
