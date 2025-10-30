package com.example.third_eye

import android.view.KeyEvent
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val HARDWARE_KEYS_CHANNEL = "com.example.third_eye/hardware_keys"
    private val CELLULAR_HTTP_CHANNEL = "com.example.third_eye/cellular_http"

    private var hardwareKeysChannel: MethodChannel? = null
    private var cellularHttpChannel: MethodChannel? = null
    private var cellularHttpClient: CellularHttpClient? = null

    private val mainScope = CoroutineScope(Dispatchers.Main + Job())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set up method channel for sending key events to Flutter
        hardwareKeysChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_KEYS_CHANNEL)
        Log.d("MainActivity", "Hardware keys channel configured: $HARDWARE_KEYS_CHANNEL")

        // Set up method channel for cellular HTTP requests
        cellularHttpClient = CellularHttpClient(applicationContext)
        cellularHttpChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CELLULAR_HTTP_CHANNEL)

        cellularHttpChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCellularNetwork" -> {
                    mainScope.launch {
                        try {
                            val success = cellularHttpClient!!.requestCellularNetwork()
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("CELLULAR_ERROR", "Failed to request cellular network: ${e.message}", null)
                        }
                    }
                }

                "executePost" -> {
                    val url = call.argument<String>("url")
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val body = call.argument<String>("body")
                    val contentType = call.argument<String>("contentType") ?: "application/json"

                    if (url == null || body == null) {
                        result.error("INVALID_ARGS", "url and body are required", null)
                        return@setMethodCallHandler
                    }

                    mainScope.launch {
                        try {
                            val response = cellularHttpClient!!.executePost(url, headers, body, contentType)
                            result.success(response)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "POST request failed: ${e.message}")
                            result.error("HTTP_ERROR", "POST request failed: ${e.message}", null)
                        }
                    }
                }

                "executeGet" -> {
                    val url = call.argument<String>("url")
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()

                    if (url == null) {
                        result.error("INVALID_ARGS", "url is required", null)
                        return@setMethodCallHandler
                    }

                    mainScope.launch {
                        try {
                            val response = cellularHttpClient!!.executeGet(url, headers)
                            result.success(response)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "GET request failed: ${e.message}")
                            result.error("HTTP_ERROR", "GET request failed: ${e.message}", null)
                        }
                    }
                }

                "isCellularAvailable" -> {
                    result.success(cellularHttpClient!!.isCellularAvailable())
                }

                "releaseCellularNetwork" -> {
                    cellularHttpClient!!.release()
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        Log.d("MainActivity", "Cellular HTTP channel configured: $CELLULAR_HTTP_CHANNEL")
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
                hardwareKeysChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "volumeUp",
                    "keyCode" to keyCode
                ))
                return true // Prevent system from handling volume change
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d("MainActivity", "✓ Volume DOWN intercepted")
                hardwareKeysChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "volumeDown",
                    "keyCode" to keyCode
                ))
                return true // Prevent system from handling volume change
            }
            KeyEvent.KEYCODE_CAMERA -> {
                Log.d("MainActivity", "✓ Camera button intercepted")
                hardwareKeysChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "camera",
                    "keyCode" to keyCode
                ))
                return true
            }
            KeyEvent.KEYCODE_FOCUS -> {
                Log.d("MainActivity", "✓ Focus button intercepted")
                hardwareKeysChannel?.invokeMethod("onKeyPressed", mapOf(
                    "keyType" to "focus",
                    "keyCode" to keyCode
                ))
                return true
            }
            KeyEvent.KEYCODE_ENTER -> {
                Log.d("MainActivity", "✓ Enter button intercepted")
                hardwareKeysChannel?.invokeMethod("onKeyPressed", mapOf(
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
        // Consume volume keys to prevent system handling
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d("MainActivity", "Volume key UP consumed (keyCode: $keyCode)")
                return true
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
        hardwareKeysChannel = null
        cellularHttpChannel = null
        cellularHttpClient?.release()
        cellularHttpClient = null
        mainScope.cancel()
        super.onDestroy()
    }
}
