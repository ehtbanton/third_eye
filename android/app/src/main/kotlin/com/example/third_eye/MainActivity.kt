package com.example.third_eye

import android.view.KeyEvent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.third_eye/hardware_keys"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up method channel for sending key events to Flutter
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        Log.d("MainActivity", "Method channel configured: $CHANNEL")
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        Log.d("MainActivity", "=== onKeyDown ===")
        Log.d("MainActivity", "KeyCode: $keyCode")
        Log.d("MainActivity", "Action: ${event?.action}")
        Log.d("MainActivity", "KeyEvent: $event")

        // Intercept volume and camera keys
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                Log.d("MainActivity", "✓ Volume UP intercepted")
                methodChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "volumeUp",
                    "keyCode" to keyCode
                ))
                return false // Allow system to handle volume change
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d("MainActivity", "✓ Volume DOWN intercepted")
                methodChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "volumeDown",
                    "keyCode" to keyCode
                ))
                return false // Allow system to handle volume change
            }
            KeyEvent.KEYCODE_CAMERA -> {
                Log.d("MainActivity", "✓ Camera button intercepted")
                methodChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "camera",
                    "keyCode" to keyCode
                ))
                return true
            }
            KeyEvent.KEYCODE_FOCUS -> {
                Log.d("MainActivity", "✓ Focus button intercepted")
                methodChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "focus",
                    "keyCode" to keyCode
                ))
                return true
            }
            KeyEvent.KEYCODE_ENTER -> {
                Log.d("MainActivity", "✓ Enter button intercepted")
                methodChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "enter",
                    "keyCode" to keyCode
                ))
                return true
            }
        }

        // Let other keys pass through
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        // Allow volume keys to pass through to system
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d("MainActivity", "Volume key UP passed through (keyCode: $keyCode)")
                return false
            }
            KeyEvent.KEYCODE_CAMERA,
            KeyEvent.KEYCODE_FOCUS -> {
                Log.d("MainActivity", "Camera/Focus key UP consumed (keyCode: $keyCode)")
                return true
            }
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onDestroy() {
        methodChannel = null
        super.onDestroy()
    }
}
