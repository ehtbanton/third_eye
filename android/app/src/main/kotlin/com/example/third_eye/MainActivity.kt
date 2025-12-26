package com.example.third_eye

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.KeyEvent
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val HARDWARE_KEYS_CHANNEL = "com.example.third_eye/hardware_keys"
    private val CELLULAR_HTTP_CHANNEL = "com.example.third_eye/cellular_http"
    private val UDP_H264_CHANNEL = "com.example.third_eye/udp_h264"
    private val WIFI_NETWORK_CHANNEL = "com.example.third_eye/wifi_network"
    private val FOREGROUND_SERVICE_CHANNEL = "com.example.third_eye/foreground_service"

    private var hardwareKeysChannel: MethodChannel? = null
    private var cellularHttpChannel: MethodChannel? = null
    private var cellularHttpClient: CellularHttpClient? = null
    private var udpH264Channel: MethodChannel? = null
    private var udpReceiver: UdpReceiver? = null
    private var h264Parser: H264Parser? = null
    private var h264VideoViewFactory: H264VideoViewFactory? = null
    private var wifiNetworkChannel: MethodChannel? = null
    private var wifiNetworkManager: WifiNetworkManager? = null
    private var foregroundServiceChannel: MethodChannel? = null

    private val mainScope = CoroutineScope(Dispatchers.Main + Job())

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
    }

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

        // Set up method channel for UDP H264 video receiver
        udpH264Channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UDP_H264_CHANNEL)

        udpH264Channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startReceiver" -> {
                    val port = call.argument<Int>("port") ?: 5000
                    startUdpReceiver(port)
                    result.success(true)
                }

                "stopReceiver" -> {
                    stopUdpReceiver()
                    result.success(true)
                }

                "isReceiving" -> {
                    result.success(udpReceiver?.isRunning() ?: false)
                }

                "getStats" -> {
                    result.success(mapOf(
                        "packetsReceived" to (udpReceiver?.getPacketsReceived() ?: 0L),
                        "bytesReceived" to (udpReceiver?.getBytesReceived() ?: 0L),
                        "isRunning" to (udpReceiver?.isRunning() ?: false)
                    ))
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        Log.d("MainActivity", "UDP H264 channel configured: $UDP_H264_CHANNEL")

        // Set up method channel for WiFi network management
        wifiNetworkManager = WifiNetworkManager(applicationContext)
        wifiNetworkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_NETWORK_CHANNEL)

        wifiNetworkChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "connectToWifi" -> {
                    val ssid = call.argument<String>("ssid")
                    val password = call.argument<String>("password")

                    if (ssid == null || password == null) {
                        result.error("INVALID_ARGS", "ssid and password are required", null)
                        return@setMethodCallHandler
                    }

                    mainScope.launch {
                        try {
                            val success = wifiNetworkManager!!.connectToWifi(ssid, password)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("WIFI_ERROR", "Failed to connect to WiFi: ${e.message}", null)
                        }
                    }
                }

                "disconnectWifi" -> {
                    wifiNetworkManager!!.disconnect()
                    result.success(true)
                }

                "isConnectedToWifi" -> {
                    val ssid = call.argument<String>("ssid")
                    result.success(wifiNetworkManager!!.isConnectedToWifi(ssid))
                }

                "getWifiState" -> {
                    result.success(wifiNetworkManager!!.getWifiState())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        Log.d("MainActivity", "WiFi network channel configured: $WIFI_NETWORK_CHANNEL")

        // Set up method channel for foreground service control
        foregroundServiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FOREGROUND_SERVICE_CHANNEL)

        foregroundServiceChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val port = call.argument<Int>("port") ?: 5000
                    val success = startForegroundService(port)
                    result.success(success)
                }

                "stopService" -> {
                    stopForegroundService()
                    result.success(true)
                }

                "isServiceRunning" -> {
                    result.success(UdpStreamService.instance?.isStreaming() ?: false)
                }

                "getServiceStats" -> {
                    val stats = UdpStreamService.instance?.getStats() ?: mapOf(
                        "isStreaming" to false,
                        "port" to 0,
                        "packetsReceived" to 0L,
                        "bytesReceived" to 0L,
                        "hasNetwork" to false
                    )
                    result.success(stats)
                }

                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }

                "hasNotificationPermission" -> {
                    result.success(hasNotificationPermission())
                }

                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set the method channel on the service so it can send callbacks to Flutter
        UdpStreamService.flutterMethodChannel = foregroundServiceChannel

        Log.d("MainActivity", "Foreground service channel configured: $FOREGROUND_SERVICE_CHANNEL")

        // Register H264 video view factory for platform views
        h264VideoViewFactory = H264VideoViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            H264VideoViewFactory.VIEW_TYPE,
            h264VideoViewFactory!!
        )
        Log.d("MainActivity", "H264 video view factory registered: ${H264VideoViewFactory.VIEW_TYPE}")
    }

    private fun startUdpReceiver(port: Int) {
        // Stop existing receiver if any
        stopUdpReceiver()

        Log.i("MainActivity", "Starting UDP receiver on port $port")

        // Create H264 parser with callbacks
        h264Parser = H264Parser()
        h264Parser?.setCallback(object : H264Parser.NalUnitCallback {
            override fun onNalUnit(nalUnit: ByteArray, nalType: Int) {
                // NAL unit ready for decoding
                // Will be used when we add MediaCodec decoder
            }

            override fun onSpsReceived(sps: ByteArray) {
                Log.i("MainActivity", "H264: SPS received (${sps.size} bytes)")
            }

            override fun onPpsReceived(pps: ByteArray) {
                Log.i("MainActivity", "H264: PPS received (${pps.size} bytes)")
            }

            override fun onKeyFrame(nalUnit: ByteArray) {
                Log.i("MainActivity", "H264: Keyframe (IDR) received (${nalUnit.size} bytes)")
            }
        })

        udpReceiver = UdpReceiver(port)
        udpReceiver?.start { data, _ ->
            // Feed UDP data into H264 parser
            h264Parser?.feedData(data)
        }
    }

    private fun stopUdpReceiver() {
        udpReceiver?.stop()
        udpReceiver = null
        h264Parser?.reset()
        h264Parser = null
        Log.i("MainActivity", "UDP receiver stopped")
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

    // ========== Foreground Service Methods ==========

    private fun startForegroundService(port: Int): Boolean {
        Log.i("MainActivity", "Starting foreground service on port $port")

        val serviceIntent = Intent(this, UdpStreamService::class.java).apply {
            action = "START_STREAM"
            putExtra("port", port)
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            // Save state for boot recovery
            BootReceiver.saveServiceState(this, true, port)
            Log.i("MainActivity", "Foreground service started successfully")
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to start foreground service: ${e.message}")
            false
        }
    }

    private fun stopForegroundService() {
        Log.i("MainActivity", "Stopping foreground service")

        val serviceIntent = Intent(this, UdpStreamService::class.java).apply {
            action = "STOP_STREAM"
        }

        try {
            startService(serviceIntent)
            // Clear saved state
            BootReceiver.saveServiceState(this, false, 5000)
            Log.i("MainActivity", "Foreground service stop requested")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to stop foreground service: ${e.message}")
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        }
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        }
    }

    override fun onDestroy() {
        hardwareKeysChannel = null
        cellularHttpChannel = null
        cellularHttpClient?.release()
        cellularHttpClient = null
        stopUdpReceiver()
        udpH264Channel = null
        h264VideoViewFactory?.stopAllStreams()
        h264VideoViewFactory = null
        wifiNetworkChannel = null
        wifiNetworkManager?.disconnect()
        wifiNetworkManager = null
        foregroundServiceChannel = null
        mainScope.cancel()
        super.onDestroy()
    }
}
