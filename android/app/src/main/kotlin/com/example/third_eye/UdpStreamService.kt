package com.example.third_eye

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Network
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground Service for persistent UDP streaming and MediaSession handling.
 * Manages the UDP receiver so streaming continues even when app is backgrounded.
 * Enables the Bluetooth clicker to trigger scene description when screen is off.
 */
class UdpStreamService : Service() {

    companion object {
        private const val TAG = "UdpStreamService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "udp_stream_channel"
        private const val CHANNEL_NAME = "Video Stream"

        // Service state accessible from MainActivity
        @Volatile
        var instance: UdpStreamService? = null
            private set

        // Method channel for callbacks to Flutter
        var flutterMethodChannel: MethodChannel? = null
    }

    // Binder for local service binding
    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): UdpStreamService = this@UdpStreamService
    }

    // Service state
    private var wakeLock: PowerManager.WakeLock? = null
    private var isStreaming = false

    // UDP streaming - owned by service for persistent background operation
    private var udpReceiver: UdpReceiver? = null
    private var currentPort = 5000
    private var currentNetwork: Network? = null

    // Registered data consumers (video views that want to receive UDP data)
    private val dataConsumers = mutableListOf<(ByteArray) -> Unit>()
    private val consumersLock = Object()

    // MediaSession for background button handling
    private var mediaSession: MediaSessionCompat? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    // Callback for trigger events
    var onTriggerCallback: (() -> Unit)? = null

    // Handler for main thread operations
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Service created")
        instance = this
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
        setupMediaSession()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "Service started with action: ${intent?.action}")

        // Handle media button events
        MediaButtonReceiver.handleIntent(mediaSession, intent)

        when (intent?.action) {
            "START_STREAM", "START_SERVICE" -> {
                val port = intent.getIntExtra("port", 5000)
                startForegroundWithNotification()
                acquireWakeLock()
                requestAudioFocus()
                activateMediaSession()
                startUdpReceiver(port)
                updateNotification("Streaming on port $port")
            }
            "STOP_STREAM", "STOP_SERVICE" -> {
                stopUdpReceiver()
                deactivateMediaSession()
                abandonAudioFocus()
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            "TRIGGER_DESCRIBE" -> {
                // Trigger scene description
                triggerSceneDescription()
            }
            Intent.ACTION_MEDIA_BUTTON -> {
                // Handle media button from broadcast
                MediaButtonReceiver.handleIntent(mediaSession, intent)
            }
            else -> {
                // Default: start foreground to keep service alive
                startForegroundWithNotification()
            }
        }

        // Don't restart service if killed - app will restart it when reopened
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder {
        Log.i(TAG, "Service bound")
        return binder
    }

    override fun onDestroy() {
        Log.i(TAG, "Service destroyed")
        stopUdpReceiver()
        deactivateMediaSession()
        mediaSession?.release()
        mediaSession = null
        abandonAudioFocus()
        releaseWakeLock()
        instance = null
        super.onDestroy()
    }

    // ========== UDP Receiver Management ==========

    private fun startUdpReceiver(port: Int) {
        if (udpReceiver != null) {
            Log.w(TAG, "UDP receiver already running")
            return
        }

        Log.i(TAG, "Starting UDP receiver on port $port")
        currentPort = port
        currentNetwork = WifiNetworkManager.currentWifiNetwork

        udpReceiver = UdpReceiver(port, currentNetwork)
        udpReceiver?.start { data, _ ->
            // Forward data to all registered consumers
            synchronized(consumersLock) {
                for (consumer in dataConsumers) {
                    try {
                        consumer(data)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error forwarding data to consumer: ${e.message}")
                    }
                }
            }
        }

        isStreaming = true
        Log.i(TAG, "UDP receiver started")
    }

    private fun stopUdpReceiver() {
        Log.i(TAG, "Stopping UDP receiver")
        udpReceiver?.stop()
        udpReceiver = null
        isStreaming = false
        synchronized(consumersLock) {
            dataConsumers.clear()
        }
        Log.i(TAG, "UDP receiver stopped")
    }

    /**
     * Register a callback to receive UDP data.
     * Used by H264VideoView to receive stream data from the service.
     */
    fun registerDataConsumer(consumer: (ByteArray) -> Unit) {
        synchronized(consumersLock) {
            if (!dataConsumers.contains(consumer)) {
                dataConsumers.add(consumer)
                Log.i(TAG, "Data consumer registered (total: ${dataConsumers.size})")
            }
        }
    }

    /**
     * Unregister a data consumer callback.
     */
    fun unregisterDataConsumer(consumer: (ByteArray) -> Unit) {
        synchronized(consumersLock) {
            dataConsumers.remove(consumer)
            Log.i(TAG, "Data consumer unregistered (total: ${dataConsumers.size})")
        }
    }

    /**
     * Check if the UDP receiver is running.
     */
    fun isUdpReceiverRunning(): Boolean = udpReceiver != null && isStreaming

    // ========== MediaSession Setup ==========

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "ThirdEyeSession").apply {
            // Set callback for media button events
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() {
                    Log.i(TAG, "MediaSession: onPlay")
                    triggerSceneDescription()
                }

                override fun onPause() {
                    Log.i(TAG, "MediaSession: onPause")
                    triggerSceneDescription()
                }

                override fun onMediaButtonEvent(mediaButtonEvent: Intent?): Boolean {
                    val keyEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        mediaButtonEvent?.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonEvent?.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                    }

                    if (keyEvent?.action == KeyEvent.ACTION_DOWN) {
                        Log.i(TAG, "MediaSession button: ${keyEvent.keyCode}")

                        when (keyEvent.keyCode) {
                            KeyEvent.KEYCODE_MEDIA_PLAY,
                            KeyEvent.KEYCODE_MEDIA_PAUSE,
                            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                            KeyEvent.KEYCODE_HEADSETHOOK -> {
                                triggerSceneDescription()
                                return true
                            }
                            KeyEvent.KEYCODE_VOLUME_UP -> {
                                triggerSceneDescription()
                                return true
                            }
                        }
                    }
                    return super.onMediaButtonEvent(mediaButtonEvent)
                }

                override fun onSkipToNext() {
                    Log.i(TAG, "MediaSession: onSkipToNext")
                    triggerSceneDescription()
                }

                override fun onSkipToPrevious() {
                    Log.i(TAG, "MediaSession: onSkipToPrevious")
                }
            })

            // Set flags to handle transport controls and media buttons
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
            )
        }

        Log.i(TAG, "MediaSession created")
    }

    private fun activateMediaSession() {
        mediaSession?.apply {
            isActive = true

            // Set metadata to appear in notification/lock screen
            setMetadata(
                MediaMetadataCompat.Builder()
                    .putString(MediaMetadataCompat.METADATA_KEY_TITLE, "Third Eye")
                    .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, "Scene Description")
                    .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, -1)
                    .build()
            )

            // Set playback state to "playing" so we receive media button events
            setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1.0f)
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
                    )
                    .build()
            )

            Log.i(TAG, "MediaSession activated")
        }
    }

    private fun deactivateMediaSession() {
        mediaSession?.isActive = false
        Log.i(TAG, "MediaSession deactivated")
    }

    // ========== Audio Focus (required for MediaSession priority) ==========

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(audioAttributes)
                .setOnAudioFocusChangeListener { }
                .build()

            audioManager?.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager?.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
        Log.i(TAG, "Audio focus requested")
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager?.abandonAudioFocus(null)
        }
        Log.i(TAG, "Audio focus abandoned")
    }

    // ========== Notification ==========

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when video stream is active"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
            Log.i(TAG, "Notification channel created")
        }
    }

    private fun startForegroundWithNotification() {
        val notification = buildNotification("Preparing stream...")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        Log.i(TAG, "Started foreground with notification")
    }

    private fun buildNotification(contentText: String): Notification {
        // Intent to bring app to foreground when notification tapped
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Describe action (trigger from notification)
        val describeIntent = Intent(this, UdpStreamService::class.java).apply {
            action = "TRIGGER_DESCRIBE"
        }
        val describePendingIntent = PendingIntent.getService(
            this,
            2,
            describeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Third Eye")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_view, "Describe", describePendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun updateNotification(contentText: String) {
        val notification = buildNotification(contentText)
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    // ========== Wake Lock ==========

    private fun acquireWakeLock() {
        if (wakeLock != null) return

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ThirdEye::UdpStreamWakeLock"
        ).apply {
            acquire(60 * 60 * 1000L)  // 1 hour
        }
        Log.i(TAG, "Wake lock acquired")
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.i(TAG, "Wake lock released")
            }
        }
        wakeLock = null
    }

    // ========== Scene Description Trigger ==========

    fun triggerSceneDescription() {
        Log.i(TAG, "Scene description triggered!")

        // Notify via local callback
        onTriggerCallback?.invoke()

        // Notify Flutter via method channel
        mainHandler.post {
            try {
                flutterMethodChannel?.invokeMethod("onTrigger", mapOf(
                    "source" to "background_service",
                    "timestamp" to System.currentTimeMillis()
                ))
                Log.i(TAG, "Sent trigger to Flutter")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send trigger to Flutter: ${e.message}")
            }
        }

        // Update notification to show we're processing
        updateNotification("Describing scene...")
    }

    // ========== Status Methods ==========

    fun isStreaming(): Boolean = isStreaming

    fun getStats(): Map<String, Any> {
        return mapOf(
            "isStreaming" to isStreaming,
            "isActive" to (mediaSession?.isActive ?: false)
        )
    }
}
