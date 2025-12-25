package com.example.third_eye

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.PixelCopy
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.io.ByteArrayOutputStream

/**
 * Native Android SurfaceView for displaying H264 video stream.
 * Integrates UDP receiver, H264 parser, and MediaCodec decoder.
 */
class H264VideoView(
    context: Context,
    private val viewId: Int,
    private val methodChannel: MethodChannel?
) : PlatformView, SurfaceHolder.Callback {

    companion object {
        private const val TAG = "H264VideoView"
    }

    private val surfaceView: SurfaceView = SurfaceView(context)
    private var udpReceiver: UdpReceiver? = null
    private var h264Parser: H264Parser? = null
    private var h264Decoder: H264Decoder? = null
    private var isStreaming = false

    // For frame capture
    private val captureHandler: Handler
    private val captureHandlerThread: HandlerThread

    // Stored SPS/PPS for decoder init
    private var pendingSps: ByteArray? = null
    private var pendingPps: ByteArray? = null

    // Pending stream start request (if called before surface is ready)
    private var pendingStartPort: Int? = null

    init {
        surfaceView.holder.addCallback(this)
        surfaceView.holder.setFormat(PixelFormat.TRANSLUCENT)

        // Handler for PixelCopy operations
        captureHandlerThread = HandlerThread("PixelCopyThread")
        captureHandlerThread.start()
        captureHandler = Handler(captureHandlerThread.looper)

        Log.i(TAG, "H264VideoView created (viewId=$viewId)")
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        Log.i(TAG, "Disposing H264VideoView")
        stopStream()
        captureHandlerThread.quitSafely()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.i(TAG, "Surface created")
        // Surface is ready - start pending stream if any
        pendingStartPort?.let { port ->
            Log.i(TAG, "Processing pending stream start on port $port")
            pendingStartPort = null
            startStream(port)
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        Log.i(TAG, "Surface changed: ${width}x${height}")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Log.i(TAG, "Surface destroyed")
        stopStream()
    }

    /**
     * Start receiving and decoding H264 stream from UDP.
     */
    fun startStream(port: Int): Boolean {
        if (isStreaming) {
            Log.w(TAG, "Stream already running")
            return true
        }

        if (!surfaceView.holder.surface.isValid) {
            Log.i(TAG, "Surface not valid yet, queuing start request for port $port")
            pendingStartPort = port
            return true  // Return true since we'll start when surface is ready
        }

        Log.i(TAG, "Starting H264 stream on port $port")

        // Create parser
        h264Parser = H264Parser()
        h264Parser?.setCallback(object : H264Parser.NalUnitCallback {
            override fun onNalUnit(nalUnit: ByteArray, nalType: Int) {
                h264Decoder?.queueNalUnit(nalUnit)
            }

            override fun onSpsReceived(sps: ByteArray) {
                Log.i(TAG, "SPS received (${sps.size} bytes)")
                pendingSps = sps
                tryInitDecoder()
            }

            override fun onPpsReceived(pps: ByteArray) {
                Log.i(TAG, "PPS received (${pps.size} bytes)")
                pendingPps = pps
                tryInitDecoder()
            }

            override fun onKeyFrame(nalUnit: ByteArray) {
                // Keyframe - good for seeking/recovery
            }
        })

        // Create decoder (will be configured when SPS/PPS arrive)
        h264Decoder = H264Decoder()

        // Start UDP receiver
        udpReceiver = UdpReceiver(port)
        udpReceiver?.start { data, _ ->
            h264Parser?.feedData(data)
        }

        isStreaming = true
        Log.i(TAG, "Stream started")
        return true
    }

    /**
     * Try to initialize decoder once we have SPS and PPS.
     */
    private fun tryInitDecoder() {
        val sps = pendingSps ?: return
        val pps = pendingPps ?: return
        val decoder = h264Decoder ?: return

        if (decoder.isReady()) return

        Log.i(TAG, "Initializing decoder with SPS/PPS")
        val success = decoder.configure(sps, pps, surfaceView.holder.surface)
        if (success) {
            Log.i(TAG, "Decoder initialized successfully")
        } else {
            Log.e(TAG, "Failed to initialize decoder")
        }
    }

    /**
     * Stop the stream and release resources.
     */
    fun stopStream() {
        if (!isStreaming) return

        Log.i(TAG, "Stopping stream")
        isStreaming = false

        udpReceiver?.stop()
        udpReceiver = null

        h264Decoder?.release()
        h264Decoder = null

        h264Parser?.reset()
        h264Parser = null

        pendingSps = null
        pendingPps = null

        Log.i(TAG, "Stream stopped")
    }

    /**
     * Capture current frame as JPEG bytes.
     */
    fun captureFrame(callback: (ByteArray?) -> Unit) {
        if (!isStreaming || !surfaceView.holder.surface.isValid) {
            Log.w(TAG, "Cannot capture - stream not active")
            callback(null)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.e(TAG, "PixelCopy requires API 26+")
            callback(null)
            return
        }

        val bitmap = Bitmap.createBitmap(
            surfaceView.width,
            surfaceView.height,
            Bitmap.Config.ARGB_8888
        )

        try {
            PixelCopy.request(
                surfaceView.holder.surface,
                bitmap,
                { result ->
                    if (result == PixelCopy.SUCCESS) {
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                        val bytes = stream.toByteArray()
                        Log.d(TAG, "Frame captured: ${bytes.size} bytes")
                        callback(bytes)
                    } else {
                        Log.e(TAG, "PixelCopy failed: $result")
                        callback(null)
                    }
                    bitmap.recycle()
                },
                captureHandler
            )
        } catch (e: Exception) {
            Log.e(TAG, "Frame capture error: ${e.message}")
            bitmap.recycle()
            callback(null)
        }
    }

    /**
     * Check if stream is active.
     */
    fun isStreaming(): Boolean = isStreaming

    /**
     * Get streaming statistics.
     */
    fun getStats(): Map<String, Any> {
        val parserStats = h264Parser?.getStats() ?: emptyMap()
        val decoderStats = h264Decoder?.getStats() ?: emptyMap()
        val receiverStats = mapOf(
            "packetsReceived" to (udpReceiver?.getPacketsReceived() ?: 0L),
            "bytesReceived" to (udpReceiver?.getBytesReceived() ?: 0L)
        )

        return parserStats + decoderStats + receiverStats + mapOf("isStreaming" to isStreaming)
    }
}
