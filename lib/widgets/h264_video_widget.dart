import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Widget that displays H264 video stream using native Android decoder.
/// Uses PlatformView to embed native SurfaceView.
class H264VideoWidget extends StatefulWidget {
  final int port;
  final bool autoStart;
  final Function(H264VideoController)? onControllerCreated;

  const H264VideoWidget({
    super.key,
    this.port = 5000,
    this.autoStart = true,
    this.onControllerCreated,
  });

  @override
  State<H264VideoWidget> createState() => _H264VideoWidgetState();
}

class _H264VideoWidgetState extends State<H264VideoWidget> {
  H264VideoController? _controller;
  bool _isStreaming = false;

  @override
  void dispose() {
    _controller?.stopStream();
    super.dispose();
  }

  void _onPlatformViewCreated(int viewId) {
    debugPrint('H264VideoWidget: Platform view created (viewId=$viewId)');
    _controller = H264VideoController(viewId);
    widget.onControllerCreated?.call(_controller!);

    if (widget.autoStart) {
      _startStream();
    }
  }

  Future<void> _startStream() async {
    if (_controller == null) return;

    final success = await _controller!.startStream(widget.port);
    if (mounted) {
      setState(() {
        _isStreaming = success;
      });
    }
    debugPrint('H264VideoWidget: Stream started: $success');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Native video view
        AndroidView(
          viewType: 'com.example.third_eye/h264_video_view',
          onPlatformViewCreated: _onPlatformViewCreated,
          creationParamsCodec: const StandardMessageCodec(),
        ),
        // Loading indicator when not streaming
        if (!_isStreaming)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Waiting for video stream...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Controller for H264VideoWidget.
/// Provides methods to control the video stream.
class H264VideoController {
  final int viewId;
  late final MethodChannel _channel;

  H264VideoController(this.viewId) {
    _channel = MethodChannel('com.example.third_eye/h264_video_view_$viewId');
  }

  /// Start receiving and decoding H264 stream on the specified port.
  Future<bool> startStream(int port) async {
    try {
      final result = await _channel.invokeMethod<bool>('startStream', {'port': port});
      return result ?? false;
    } catch (e) {
      debugPrint('H264VideoController: Failed to start stream: $e');
      return false;
    }
  }

  /// Stop the video stream.
  Future<void> stopStream() async {
    try {
      await _channel.invokeMethod('stopStream');
    } catch (e) {
      debugPrint('H264VideoController: Failed to stop stream: $e');
    }
  }

  /// Capture the current frame as JPEG bytes.
  Future<Uint8List?> captureFrame() async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('captureFrame');
      return result;
    } catch (e) {
      debugPrint('H264VideoController: Failed to capture frame: $e');
      return null;
    }
  }

  /// Check if stream is active.
  Future<bool> isStreaming() async {
    try {
      final result = await _channel.invokeMethod<bool>('isStreaming');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get streaming statistics.
  Future<Map<String, dynamic>> getStats() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStats');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('H264VideoController: Failed to get stats: $e');
    }
    return {};
  }
}
