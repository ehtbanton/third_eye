package com.example.third_eye

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory for creating H264VideoView instances.
 * Registered with Flutter's platform views controller.
 */
class H264VideoViewFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        private const val TAG = "H264VideoViewFactory"
        const val VIEW_TYPE = "com.example.third_eye/h264_video_view"
    }

    // Keep track of active views for cleanup
    private val activeViews = mutableMapOf<Int, H264VideoView>()

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        Log.i(TAG, "Creating H264VideoView (viewId=$viewId)")

        // Create method channel for this specific view
        val channelName = "${VIEW_TYPE}_$viewId"
        val methodChannel = MethodChannel(messenger, channelName)

        val view = H264VideoView(context, viewId, methodChannel)
        activeViews[viewId] = view

        // Set up method channel handler for this view
        methodChannel.setMethodCallHandler { call, result ->
            val videoView = activeViews[viewId]
            if (videoView == null) {
                result.error("VIEW_NOT_FOUND", "View with id $viewId not found", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "startStream" -> {
                    val port = call.argument<Int>("port") ?: 5000
                    val success = videoView.startStream(port)
                    result.success(success)
                }

                "stopStream" -> {
                    videoView.stopStream()
                    result.success(true)
                }

                "captureFrame" -> {
                    videoView.captureFrame { bytes ->
                        if (bytes != null) {
                            result.success(bytes)
                        } else {
                            result.error("CAPTURE_FAILED", "Failed to capture frame", null)
                        }
                    }
                }

                "isStreaming" -> {
                    result.success(videoView.isStreaming())
                }

                "getStats" -> {
                    result.success(videoView.getStats())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        return view
    }

    /**
     * Get an active view by ID.
     */
    fun getView(viewId: Int): H264VideoView? = activeViews[viewId]

    /**
     * Remove a view from tracking.
     */
    fun removeView(viewId: Int) {
        activeViews.remove(viewId)
        Log.i(TAG, "Removed view $viewId, active views: ${activeViews.size}")
    }

    /**
     * Stop all active streams.
     */
    fun stopAllStreams() {
        activeViews.values.forEach { it.stopStream() }
    }
}
