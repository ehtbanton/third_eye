package com.example.third_eye

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.speech.tts.TextToSpeech
import android.util.Base64
import android.util.Log
import android.view.Surface
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.InputStreamReader
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Handles scene description in background when Flutter is not available.
 * - Decodes H264 stream to frames using ImageReader
 * - Captures frames on demand
 * - Sends to Azure OpenAI for description
 * - Uses Android TTS to speak the result
 */
class SceneDescriptionHandler(private val context: Context) {

    companion object {
        private const val TAG = "SceneDescriptionHandler"
        private const val MIME_TYPE = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val TIMEOUT_US = 10000L
        private const val DEFAULT_WIDTH = 1280
        private const val DEFAULT_HEIGHT = 720

        // Shared API config that can be set from Flutter
        @Volatile var sharedAzureEndpoint: String? = null
        @Volatile var sharedAzureApiKey: String? = null
        @Volatile var sharedAzureDeploymentName: String? = null
        @Volatile var sharedAzureApiVersion: String? = null
    }

    // API configuration (instance variables, loaded from shared config)
    private var azureEndpoint: String? = null
    private var azureApiKey: String? = null
    private var azureDeploymentName: String? = null
    private var azureApiVersion: String? = null

    // Decoder components
    private var decoder: MediaCodec? = null
    private var imageReader: ImageReader? = null
    private var decoderSurface: Surface? = null
    private var isConfigured = false
    private var isRunning = false

    // H264 Parser
    private var h264Parser: H264Parser? = null

    // NAL unit queue
    private val nalQueue = LinkedBlockingQueue<ByteArray>(100)

    // Latest captured frame
    @Volatile
    private var latestBitmap: Bitmap? = null
    private val bitmapLock = Object()

    // Decoder thread
    private var decoderThread: Thread? = null

    // ImageReader handler
    private var imageHandlerThread: HandlerThread? = null
    private var imageHandler: Handler? = null

    // TTS
    private var tts: TextToSpeech? = null
    private val ttsReady = AtomicBoolean(false)

    // HTTP client for API calls
    private var cellularHttpClient: CellularHttpClient? = null

    // Coroutine scope
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Stored SPS/PPS for decoder init
    private var pendingSps: ByteArray? = null
    private var pendingPps: ByteArray? = null

    /**
     * Initialize the handler
     */
    fun initialize(): Boolean {
        Log.i(TAG, "Initializing SceneDescriptionHandler")

        // Load configuration from .env file
        if (!loadEnvConfig()) {
            Log.e(TAG, "Failed to load configuration")
            return false
        }

        // Initialize TTS
        initializeTts()

        // Initialize HTTP client
        cellularHttpClient = CellularHttpClient(context)

        // Initialize H264 parser
        h264Parser = H264Parser()
        h264Parser?.setCallback(object : H264Parser.NalUnitCallback {
            override fun onNalUnit(nalUnit: ByteArray, nalType: Int) {
                if (isConfigured && isRunning) {
                    if (!nalQueue.offer(nalUnit)) {
                        nalQueue.poll()
                        nalQueue.offer(nalUnit)
                    }
                }
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
                // Keyframe received
            }
        })

        // Start image handler thread
        imageHandlerThread = HandlerThread("ImageReaderThread")
        imageHandlerThread?.start()
        imageHandler = Handler(imageHandlerThread!!.looper)

        Log.i(TAG, "SceneDescriptionHandler initialized")
        return true
    }

    /**
     * Load configuration from shared static config (set by Flutter)
     */
    private fun loadEnvConfig(): Boolean {
        // Load from shared config that Flutter sets
        azureEndpoint = sharedAzureEndpoint
        azureApiKey = sharedAzureApiKey
        azureDeploymentName = sharedAzureDeploymentName
        azureApiVersion = sharedAzureApiVersion ?: "2024-08-01-preview"

        Log.i(TAG, "Loading config - Endpoint: $azureEndpoint, Deployment: $azureDeploymentName")

        if (azureEndpoint == null || azureApiKey == null || azureDeploymentName == null) {
            Log.e(TAG, "API configuration not set. Flutter must call setApiConfig first.")
            return false
        }

        return true
    }

    /**
     * Initialize Android TextToSpeech
     */
    private fun initializeTts() {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts?.setLanguage(Locale.US)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.e(TAG, "TTS language not supported")
                } else {
                    ttsReady.set(true)
                    Log.i(TAG, "TTS initialized successfully")
                }
            } else {
                Log.e(TAG, "TTS initialization failed")
            }
        }
    }

    /**
     * Feed UDP data into the parser
     */
    fun feedData(data: ByteArray) {
        h264Parser?.feedData(data)
    }

    /**
     * Try to initialize decoder once we have SPS and PPS
     */
    private fun tryInitDecoder() {
        val sps = pendingSps ?: return
        val pps = pendingPps ?: return

        if (isConfigured) return

        try {
            Log.i(TAG, "Initializing headless decoder")

            // Create ImageReader for frame capture using YUV format (compatible with MediaCodec)
            imageReader = ImageReader.newInstance(
                DEFAULT_WIDTH,
                DEFAULT_HEIGHT,
                ImageFormat.YUV_420_888,
                2  // Max images
            )

            imageReader?.setOnImageAvailableListener({ reader ->
                try {
                    val image = reader.acquireLatestImage()
                    if (image != null) {
                        try {
                            val bitmap = yuvImageToBitmap(image)
                            if (bitmap != null) {
                                synchronized(bitmapLock) {
                                    latestBitmap?.recycle()
                                    latestBitmap = bitmap
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error converting image to bitmap: ${e.message}")
                        } finally {
                            image.close()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error acquiring image: ${e.message}")
                }
            }, imageHandler)

            decoderSurface = imageReader?.surface

            // Create MediaFormat with SPS and PPS
            val format = MediaFormat.createVideoFormat(MIME_TYPE, DEFAULT_WIDTH, DEFAULT_HEIGHT)
            format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 100000)

            // Create decoder
            decoder = MediaCodec.createDecoderByType(MIME_TYPE)
            decoder?.configure(format, decoderSurface, null, 0)
            decoder?.start()

            isConfigured = true
            Log.i(TAG, "Headless decoder configured")

            // Start decoder thread
            startDecoderThread()

        } catch (e: Exception) {
            Log.e(TAG, "Failed to configure decoder: ${e.message}")
            e.printStackTrace()
            releaseDecoder()
        }
    }

    /**
     * Convert YUV_420_888 Image to Bitmap via JPEG compression
     */
    private fun yuvImageToBitmap(image: Image): Bitmap? {
        try {
            val yBuffer = image.planes[0].buffer
            val uBuffer = image.planes[1].buffer
            val vBuffer = image.planes[2].buffer

            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining()
            val vSize = vBuffer.remaining()

            val nv21 = ByteArray(ySize + uSize + vSize)

            // Copy Y plane
            yBuffer.get(nv21, 0, ySize)

            // Copy VU planes (NV21 format: Y then VU interleaved)
            vBuffer.get(nv21, ySize, vSize)
            uBuffer.get(nv21, ySize + vSize, uSize)

            val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), 90, out)
            val jpegBytes = out.toByteArray()

            return android.graphics.BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
        } catch (e: Exception) {
            Log.e(TAG, "Error converting YUV to bitmap: ${e.message}")
            return null
        }
    }

    /**
     * Start decoder thread
     */
    private fun startDecoderThread() {
        isRunning = true
        decoderThread = thread(name = "SceneDescriptionDecoder") {
            Log.i(TAG, "Decoder thread started")
            val bufferInfo = MediaCodec.BufferInfo()

            while (isRunning) {
                try {
                    val nalUnit = nalQueue.poll(10, java.util.concurrent.TimeUnit.MILLISECONDS)
                    if (nalUnit != null) {
                        feedInputBuffer(nalUnit)
                    }
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

    private fun feedInputBuffer(nalUnit: ByteArray) {
        val dec = decoder ?: return

        val inputIndex = dec.dequeueInputBuffer(TIMEOUT_US)
        if (inputIndex >= 0) {
            val inputBuffer = dec.getInputBuffer(inputIndex)
            inputBuffer?.clear()
            inputBuffer?.put(nalUnit)
            dec.queueInputBuffer(inputIndex, 0, nalUnit.size, System.nanoTime() / 1000, 0)
        }
    }

    private fun drainOutputBuffer(bufferInfo: MediaCodec.BufferInfo) {
        val dec = decoder ?: return

        var outputIndex = dec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
        while (outputIndex >= 0) {
            dec.releaseOutputBuffer(outputIndex, true)  // Render to ImageReader
            outputIndex = dec.dequeueOutputBuffer(bufferInfo, 0)
        }
    }

    /**
     * Trigger scene description
     * Captures current frame, sends to API, speaks result
     */
    fun triggerSceneDescription(onStatusUpdate: ((String) -> Unit)? = null) {
        Log.i(TAG, "Triggering scene description")
        onStatusUpdate?.invoke("Capturing frame...")

        scope.launch {
            try {
                // Wait a moment for a fresh frame
                delay(100)

                // Capture frame
                val bitmap = synchronized(bitmapLock) {
                    latestBitmap?.copy(latestBitmap!!.config ?: Bitmap.Config.ARGB_8888, false)
                }

                if (bitmap == null) {
                    Log.e(TAG, "No frame available")
                    withContext(Dispatchers.Main) {
                        speak("No video frame available")
                    }
                    return@launch
                }

                Log.i(TAG, "Frame captured: ${bitmap.width}x${bitmap.height}")
                onStatusUpdate?.invoke("Sending to AI...")

                // Convert to JPEG base64
                val base64Image = bitmapToBase64(bitmap)
                bitmap.recycle()

                Log.i(TAG, "Image encoded: ${base64Image.length} base64 chars")

                // Request cellular network
                val cellularAvailable = cellularHttpClient?.requestCellularNetwork() ?: false
                if (!cellularAvailable) {
                    Log.e(TAG, "Cellular network not available")
                    withContext(Dispatchers.Main) {
                        speak("Cellular network not available")
                    }
                    return@launch
                }

                // Call Azure OpenAI API
                val description = callAzureOpenAI(base64Image)
                Log.i(TAG, "Description: $description")

                onStatusUpdate?.invoke("Speaking...")

                // Speak the description
                withContext(Dispatchers.Main) {
                    speak(description)
                }

            } catch (e: Exception) {
                Log.e(TAG, "Scene description failed: ${e.message}")
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    speak("Scene description failed: ${e.message}")
                }
            }
        }
    }

    /**
     * Convert bitmap to base64 JPEG
     */
    private fun bitmapToBase64(bitmap: Bitmap): String {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
        val bytes = stream.toByteArray()
        return Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    /**
     * Call Azure OpenAI API with image
     */
    private suspend fun callAzureOpenAI(base64Image: String): String {
        val baseUrl = azureEndpoint?.removeSuffix("/") ?: throw Exception("No endpoint configured")
        val url = "$baseUrl/openai/deployments/$azureDeploymentName/chat/completions?api-version=${azureApiVersion ?: "2024-08-01-preview"}"

        // Build request body
        val contentArray = JSONArray()
        contentArray.put(JSONObject().apply {
            put("type", "text")
            put("text", "Describe this image in one sentence.")
        })
        contentArray.put(JSONObject().apply {
            put("type", "image_url")
            put("image_url", JSONObject().apply {
                put("url", "data:image/jpeg;base64,$base64Image")
            })
        })

        val messageObject = JSONObject().apply {
            put("role", "user")
            put("content", contentArray)
        }

        val messagesArray = JSONArray()
        messagesArray.put(messageObject)

        val requestBody = JSONObject().apply {
            put("messages", messagesArray)
            put("max_tokens", 1024)
            put("temperature", 0.4)
        }

        Log.i(TAG, "Calling Azure OpenAI: $url")

        val headers = mapOf(
            "Content-Type" to "application/json",
            "api-key" to (azureApiKey ?: "")
        )

        val responseJson = cellularHttpClient?.executePost(
            url,
            headers,
            requestBody.toString(),
            "application/json"
        ) ?: throw Exception("No response from API")

        // Parse response
        val response = JSONObject(responseJson)

        if (response.has("error")) {
            val error = response.getJSONObject("error")
            throw Exception("API error: ${error.getString("message")}")
        }

        val choices = response.optJSONArray("choices")
        if (choices == null || choices.length() == 0) {
            throw Exception("No response from API")
        }

        val firstChoice = choices.getJSONObject(0)
        val message = firstChoice.getJSONObject("message")
        return message.getString("content").trim()
    }

    /**
     * Speak text using TTS
     */
    private fun speak(text: String) {
        if (ttsReady.get()) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "scene_description")
            Log.i(TAG, "Speaking: $text")
        } else {
            Log.w(TAG, "TTS not ready, cannot speak: $text")
        }
    }

    /**
     * Check if handler is ready
     */
    fun isReady(): Boolean = isConfigured && isRunning

    /**
     * Release decoder resources
     */
    private fun releaseDecoder() {
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
        decoderSurface = null
        imageReader?.close()
        imageReader = null
        isConfigured = false
        nalQueue.clear()
    }

    /**
     * Release all resources
     */
    fun release() {
        Log.i(TAG, "Releasing SceneDescriptionHandler")

        releaseDecoder()

        h264Parser?.reset()
        h264Parser = null

        tts?.stop()
        tts?.shutdown()
        tts = null
        ttsReady.set(false)

        cellularHttpClient?.release()
        cellularHttpClient = null

        imageHandlerThread?.quitSafely()
        imageHandlerThread = null
        imageHandler = null

        synchronized(bitmapLock) {
            latestBitmap?.recycle()
            latestBitmap = null
        }

        scope.cancel()

        Log.i(TAG, "SceneDescriptionHandler released")
    }
}
