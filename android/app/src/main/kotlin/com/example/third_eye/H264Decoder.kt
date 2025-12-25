package com.example.third_eye

import android.media.MediaCodec
import android.media.MediaFormat
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.util.concurrent.LinkedBlockingQueue
import kotlin.concurrent.thread

/**
 * Hardware H264 decoder using Android MediaCodec.
 * Decodes H264 NAL units and renders to a Surface.
 */
class H264Decoder {
    companion object {
        private const val TAG = "H264Decoder"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val TIMEOUT_US = 10000L  // 10ms timeout for buffer operations
        private const val DEFAULT_WIDTH = 1280
        private const val DEFAULT_HEIGHT = 720
    }

    private var decoder: MediaCodec? = null
    private var surface: Surface? = null
    private var isConfigured = false
    private var isRunning = false

    // Queue for NAL units waiting to be decoded
    private val nalQueue = LinkedBlockingQueue<ByteArray>(100)

    // Decoder thread
    private var decoderThread: Thread? = null

    // Stats
    private var framesDecoded = 0L
    private var framesDropped = 0L

    /**
     * Configure and start the decoder with SPS/PPS data.
     * @param sps Sequence Parameter Set (with start code)
     * @param pps Picture Parameter Set (with start code)
     * @param surface Surface to render decoded frames to
     */
    fun configure(sps: ByteArray, pps: ByteArray, surface: Surface): Boolean {
        if (isConfigured) {
            Log.w(TAG, "Decoder already configured")
            return true
        }

        this.surface = surface

        try {
            // Parse SPS to get video dimensions (simplified - using defaults)
            val width = DEFAULT_WIDTH
            val height = DEFAULT_HEIGHT

            Log.i(TAG, "Configuring decoder: ${width}x${height}")

            // Create MediaFormat with SPS and PPS
            val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height)

            // Add codec-specific data (SPS = csd-0, PPS = csd-1)
            // SPS and PPS should include start codes for MediaCodec
            format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))

            // Low latency settings
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 100000)

            // Create decoder
            decoder = MediaCodec.createDecoderByType(MIME_TYPE)
            decoder?.configure(format, surface, null, 0)
            decoder?.start()

            isConfigured = true
            Log.i(TAG, "Decoder configured and started")

            // Start decoder thread
            startDecoderThread()

            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to configure decoder: ${e.message}")
            e.printStackTrace()
            release()
            return false
        }
    }

    /**
     * Queue a NAL unit for decoding.
     * @param nalUnit Complete NAL unit (with start code)
     */
    fun queueNalUnit(nalUnit: ByteArray) {
        if (!isConfigured || !isRunning) return

        // Drop oldest if queue is full
        if (!nalQueue.offer(nalUnit)) {
            nalQueue.poll()
            nalQueue.offer(nalUnit)
            framesDropped++
        }
    }

    /**
     * Start the decoder processing thread.
     */
    private fun startDecoderThread() {
        isRunning = true
        decoderThread = thread(name = "H264Decoder") {
            Log.i(TAG, "Decoder thread started")
            val bufferInfo = MediaCodec.BufferInfo()

            while (isRunning) {
                try {
                    // Get NAL unit from queue
                    val nalUnit = nalQueue.poll(10, java.util.concurrent.TimeUnit.MILLISECONDS)
                    if (nalUnit != null) {
                        feedInputBuffer(nalUnit)
                    }

                    // Check for output
                    drainOutputBuffer(bufferInfo)
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "Decoder error: ${e.message}")
                }
            }

            Log.i(TAG, "Decoder thread stopped")
        }
    }

    /**
     * Feed NAL unit data into decoder input buffer.
     */
    private fun feedInputBuffer(nalUnit: ByteArray) {
        val decoder = this.decoder ?: return

        val inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
        if (inputIndex >= 0) {
            val inputBuffer = decoder.getInputBuffer(inputIndex)
            inputBuffer?.clear()
            inputBuffer?.put(nalUnit)

            decoder.queueInputBuffer(
                inputIndex,
                0,
                nalUnit.size,
                System.nanoTime() / 1000,  // Presentation time in microseconds
                0
            )
        }
    }

    /**
     * Drain decoded frames from output buffer to surface.
     */
    private fun drainOutputBuffer(bufferInfo: MediaCodec.BufferInfo) {
        val decoder = this.decoder ?: return

        var outputIndex = decoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)

        while (outputIndex >= 0) {
            // Release buffer to surface for rendering
            decoder.releaseOutputBuffer(outputIndex, true)
            framesDecoded++

            if (framesDecoded % 100 == 0L) {
                Log.d(TAG, "Frames decoded: $framesDecoded, dropped: $framesDropped")
            }

            outputIndex = decoder.dequeueOutputBuffer(bufferInfo, 0)
        }

        when (outputIndex) {
            MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                val newFormat = decoder.outputFormat
                Log.i(TAG, "Output format changed: $newFormat")
            }
            MediaCodec.INFO_TRY_AGAIN_LATER -> {
                // No output available
            }
        }
    }

    /**
     * Check if decoder is configured and running.
     */
    fun isReady(): Boolean = isConfigured && isRunning

    /**
     * Get decoder statistics.
     */
    fun getStats(): Map<String, Long> {
        return mapOf(
            "framesDecoded" to framesDecoded,
            "framesDropped" to framesDropped,
            "queueSize" to nalQueue.size.toLong()
        )
    }

    /**
     * Release decoder resources.
     */
    fun release() {
        Log.i(TAG, "Releasing decoder")
        isRunning = false

        decoderThread?.interrupt()
        decoderThread?.join(1000)
        decoderThread = null

        try {
            decoder?.stop()
            decoder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing decoder: ${e.message}")
        }

        decoder = null
        surface = null
        isConfigured = false
        nalQueue.clear()

        Log.i(TAG, "Decoder released. Total frames: $framesDecoded, dropped: $framesDropped")
    }
}
