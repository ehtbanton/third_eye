import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'esp32_wifi_service.dart';
import 'slp2_stream_service.dart';
import 'stereo_video_source.dart';
import '../widgets/h264_video_widget.dart';

/// Camera source options
enum CameraSource {
  slp2Udp('SLP2 UDP'),
  slp2Rtsp('SLP2 RTSP'),
  esp32('ESP32-CAM'),
  phone('Phone'),
  stereoSim('Stereo Sim');

  final String label;
  const CameraSource(this.label);
}

/// Abstract interface for any video source.
/// All sources implement this interface so they can be used interchangeably.
abstract class VideoSource {
  /// The type of this source
  CameraSource get sourceType;

  /// Whether the source is currently connected/active
  bool get isConnected;

  /// Connect/initialize the source
  Future<bool> connect(BuildContext context);

  /// Disconnect/dispose the source
  Future<void> disconnect();

  /// Capture a single frame as JPEG bytes
  Future<Uint8List?> captureFrame();

  /// Build the preview widget for this source
  Widget buildPreview({
    Widget? overlay,
    VoidCallback? onControllerCreated,
  });

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream;
}

/// Phone camera source using Flutter camera package
class PhoneCameraSource implements VideoSource {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isConnected = false;
  final _connectionStateController = StreamController<bool>.broadcast();

  @override
  CameraSource get sourceType => CameraSource.phone;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  CameraController? get controller => _controller;

  @override
  Future<bool> connect(BuildContext context) async {
    try {
      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('PhoneCameraSource: No cameras found');
        return false;
      }

      // Find back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isConnected = true;
      _connectionStateController.add(true);
      debugPrint('PhoneCameraSource: Connected');
      return true;
    } catch (e) {
      debugPrint('PhoneCameraSource: Failed to connect: $e');
      _isConnected = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectionStateController.add(false);
    await _controller?.dispose();
    _controller = null;
    debugPrint('PhoneCameraSource: Disconnected');
  }

  @override
  Future<Uint8List?> captureFrame() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return null;
    }

    try {
      final XFile image = await _controller!.takePicture();
      final bytes = await File(image.path).readAsBytes();
      return bytes;
    } catch (e) {
      debugPrint('PhoneCameraSource: Failed to capture frame: $e');
      return null;
    }
  }

  @override
  Widget buildPreview({Widget? overlay, VoidCallback? onControllerCreated}) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Initializing phone camera...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(_controller!)),
        if (overlay != null) overlay,
      ],
    );
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
  }
}

/// ESP32-CAM WiFi source
class Esp32Source implements VideoSource {
  final Esp32WifiService _service = Esp32WifiService();
  Uint8List? _currentFrame;
  StreamSubscription<Uint8List>? _frameSubscription;

  @override
  CameraSource get sourceType => CameraSource.esp32;

  @override
  bool get isConnected => _service.isConnected;

  @override
  Stream<bool> get connectionStateStream => _service.connectionStateStream;

  Uint8List? get currentFrame => _currentFrame;

  @override
  Future<bool> connect(BuildContext context) async {
    final success = await _service.connect(esp32Ip: '192.168.4.1');
    if (success) {
      _frameSubscription = _service.imageStream.listen((frame) {
        _currentFrame = frame;
      });
    }
    return success;
  }

  @override
  Future<void> disconnect() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    _currentFrame = null;
    await _service.disconnect();
  }

  @override
  Future<Uint8List?> captureFrame() async {
    return _currentFrame;
  }

  @override
  Widget buildPreview({Widget? overlay, VoidCallback? onControllerCreated}) {
    return StreamBuilder<Uint8List>(
      stream: _service.imageStream,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
              if (overlay != null) overlay,
            ],
          );
        }
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Waiting for ESP32-CAM WiFi stream...', style: TextStyle(color: Colors.white)),
            ],
          ),
        );
      },
    );
  }

  void dispose() {
    disconnect();
    _service.dispose();
  }
}

/// SLP2 RTSP stream source
class Slp2RtspSource implements VideoSource {
  final Slp2StreamService _service = Slp2StreamService();

  @override
  CameraSource get sourceType => CameraSource.slp2Rtsp;

  @override
  bool get isConnected => _service.isConnected;

  @override
  Stream<bool> get connectionStateStream => _service.connectionStateStream;

  VideoController? get videoController => _service.videoController;
  Slp2StreamService get service => _service;

  @override
  Future<bool> connect(BuildContext context) async {
    // Auto-connect to WiFi first
    final connectionResult = await _service.autoConnect();
    final wifiConnected = connectionResult['wifi'] as bool;

    if (!wifiConnected) {
      debugPrint('Slp2RtspSource: WiFi connection failed');
    }

    // Show IP dialog for RTSP
    final ipController = TextEditingController(text: Slp2StreamService.defaultSlp2Ip);

    final ip = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to SLP2 (RTSP)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SLP2 IP address:'),
            const SizedBox(height: 8),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                hintText: '192.168.50.1',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ipController.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    if (ip == null || ip.isEmpty) {
      return false;
    }

    return await _service.connect(ip: ip);
  }

  @override
  Future<void> disconnect() async {
    await _service.disconnect();
  }

  @override
  Future<Uint8List?> captureFrame() async {
    return await _service.captureFrame();
  }

  @override
  Widget buildPreview({Widget? overlay, VoidCallback? onControllerCreated}) {
    if (_service.videoController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Connecting to SLP2 RTSP stream...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: Video(controller: _service.videoController!)),
        if (overlay != null) overlay,
      ],
    );
  }

  void dispose() {
    _service.dispose();
  }
}

/// SLP2 Native UDP H264 source (low latency)
class Slp2UdpSource implements VideoSource {
  final Slp2StreamService _wifiService = Slp2StreamService();
  H264VideoController? _h264Controller;
  bool _isConnected = false;
  bool _wifiConnectAttempted = false;
  final _connectionStateController = StreamController<bool>.broadcast();
  final int port;

  Slp2UdpSource({this.port = 5000});

  @override
  CameraSource get sourceType => CameraSource.slp2Udp;

  @override
  bool get isConnected => _isConnected && _h264Controller != null;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  H264VideoController? get h264Controller => _h264Controller;

  /// Called when the H264VideoWidget creates its controller and stream starts
  void onStreamStarted(H264VideoController controller) {
    _h264Controller = controller;
    _isConnected = true;
    _connectionStateController.add(true);
    debugPrint('Slp2UdpSource: Stream actually started');
  }

  @override
  Future<bool> connect(BuildContext context) async {
    // Start WiFi connection in background - don't block
    if (!_wifiConnectAttempted) {
      _wifiConnectAttempted = true;
      _wifiService.autoConnect().then((connectionResult) {
        final wifiConnected = connectionResult['wifi'] as bool;
        if (!wifiConnected) {
          debugPrint('Slp2UdpSource: WiFi auto-connect failed');
        } else {
          debugPrint('Slp2UdpSource: WiFi connected');
        }
      });
    }

    // Don't mark as connected yet - wait for onStreamStarted callback
    // Return true to indicate we're ready to show the widget
    return true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectionStateController.add(false);
    await _h264Controller?.stopStream();
    _h264Controller = null;
    await _wifiService.disconnect();
  }

  @override
  Future<Uint8List?> captureFrame() async {
    if (_h264Controller == null) {
      return null;
    }
    return await _h264Controller!.captureFrame();
  }

  @override
  Widget buildPreview({Widget? overlay, VoidCallback? onControllerCreated}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        H264VideoWidget(
          port: port,
          autoStart: true,
          onControllerCreated: (controller) {
            onStreamStarted(controller);
            onControllerCreated?.call();
          },
        ),
        if (overlay != null) overlay,
      ],
    );
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
  }
}

/// Stereo simulation video source
class StereoSimSource implements VideoSource {
  final StereoVideoSource _source = StereoVideoSource();
  bool _initialized = false;
  final _connectionStateController = StreamController<bool>.broadcast();

  @override
  CameraSource get sourceType => CameraSource.stereoSim;

  @override
  bool get isConnected => _initialized;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  VideoController? get videoController => _source.videoController;
  StereoVideoSource get source => _source;

  @override
  Future<bool> connect(BuildContext context) async {
    final success = await _source.initialize('asset://assets/videos/sample_stereo.mp4');
    if (success) {
      await _source.play();
      _initialized = true;
      // Wait for frames to be available
      await Future.delayed(const Duration(milliseconds: 500));
      _connectionStateController.add(true);
    }
    return success;
  }

  @override
  Future<void> disconnect() async {
    _initialized = false;
    _connectionStateController.add(false);
    await _source.dispose();
  }

  @override
  Future<Uint8List?> captureFrame() async {
    // Capture stereo pair and return left image
    final pair = await _source.captureStereoPair();
    return pair?.leftImage;
  }

  @override
  Widget buildPreview({Widget? overlay, VoidCallback? onControllerCreated}) {
    if (_source.videoController == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Loading stereo simulation...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: Video(controller: _source.videoController!)),
        if (overlay != null) overlay,
      ],
    );
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
  }
}

/// Factory for creating video sources
class VideoSourceFactory {
  static VideoSource create(CameraSource type) {
    switch (type) {
      case CameraSource.phone:
        return PhoneCameraSource();
      case CameraSource.esp32:
        return Esp32Source();
      case CameraSource.slp2Rtsp:
        return Slp2RtspSource();
      case CameraSource.slp2Udp:
        return Slp2UdpSource();
      case CameraSource.stereoSim:
        return StereoSimSource();
    }
  }
}
