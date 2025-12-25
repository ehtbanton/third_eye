import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'native_udp_service.dart';

/// Service for connecting to StereoPi SLP2 via RTSP stream.
/// Also tests native UDP H264 receiver for low-latency streaming.
class Slp2StreamService {
  static const String defaultSsid = 'cosmostreamer';
  static const String defaultPassword = '1234512345';
  static const String defaultSlp2Ip = '192.168.50.1';
  static const int rtspPort = 554;
  static const int udpPort = 5000;

  final NativeUdpService _nativeUdp = NativeUdpService();

  String _slp2Ip = defaultSlp2Ip;
  Player? _player;
  VideoController? _videoController;
  bool _isConnected = false;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _bufferingSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _widthSubscription;

  final _connectionStateController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  bool get isConnected => _isConnected;
  VideoController? get videoController => _videoController;

  // RTSP URL for low-latency streaming
  String get streamUrl => 'rtsp://$_slp2Ip:$rtspPort/video';

  /// Initialize media_kit (call once at app startup)
  static void ensureInitialized() {
    MediaKit.ensureInitialized();
  }

  Future<bool> connect({String? ip}) async {
    if (ip != null && ip.isNotEmpty) {
      _slp2Ip = ip;
    }

    final url = streamUrl;
    debugPrint('======================================');
    debugPrint('SLP2: Connecting via RTSP (low-latency) to $_slp2Ip:$rtspPort');
    debugPrint('SLP2: URL = $url');
    debugPrint('SLP2: Also starting UDP receiver on port $udpPort for testing');
    debugPrint('======================================');

    // Start native UDP receiver for testing
    await _nativeUdp.startReceiver(port: udpPort);

    try {
      // Create player - use default config for stability
      _player = Player();

      // Listen to player state streams for debugging
      _errorSubscription = _player!.stream.error.listen((error) {
        debugPrint('SLP2: Player ERROR: $error');
      });

      _bufferingSubscription = _player!.stream.buffering.listen((buffering) {
        debugPrint('SLP2: Buffering: $buffering');
      });

      _playingSubscription = _player!.stream.playing.listen((playing) {
        debugPrint('SLP2: Playing: $playing');
      });

      _widthSubscription = _player!.stream.width.listen((width) {
        debugPrint('SLP2: Video width detected: $width');
      });

      _videoController = VideoController(_player!);

      // Open RTSP stream
      await _player!.open(
        Media(url),
        play: true,
      );

      _isConnected = true;
      _connectionStateController.add(true);
      debugPrint('SLP2: Listening for stream');

      return true;
    } catch (e, stack) {
      debugPrint('SLP2: EXCEPTION: $e');
      debugPrint('SLP2: Stack: $stack');
      _isConnected = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  Future<Uint8List?> captureFrame() async {
    if (_player == null || !_isConnected) {
      debugPrint('SLP2: Cannot capture frame - not connected');
      return null;
    }

    try {
      final screenshot = await _player!.screenshot();
      if (screenshot != null) {
        debugPrint('SLP2: Captured frame (${screenshot.length} bytes)');
        return screenshot;
      }
      debugPrint('SLP2: Screenshot returned null');
      return null;
    } catch (e) {
      debugPrint('SLP2: Failed to capture frame: $e');
      return null;
    }
  }

  Future<void> disconnect() async {
    debugPrint('SLP2: Disconnecting...');
    _isConnected = false;
    _connectionStateController.add(false);

    // Stop native UDP receiver
    await _nativeUdp.stopReceiver();

    await _errorSubscription?.cancel();
    await _bufferingSubscription?.cancel();
    await _playingSubscription?.cancel();
    await _widthSubscription?.cancel();
    _errorSubscription = null;
    _bufferingSubscription = null;
    _playingSubscription = null;
    _widthSubscription = null;

    await _player?.stop();
    await _player?.dispose();
    _player = null;
    _videoController = null;

    debugPrint('SLP2: Disconnected');
  }

  void _handleDisconnect() {
    if (_isConnected) {
      _isConnected = false;
      _connectionStateController.add(false);
      debugPrint('SLP2: Stream disconnected unexpectedly');
    }
  }

  Future<void> dispose() async {
    debugPrint('SLP2: Disposing service...');
    await disconnect();
    await _connectionStateController.close();
  }

  static String getConnectionInstructions() {
    return '''
To connect to SLP2:

1. Connect phone to SLP2's WiFi:
   SSID: $defaultSsid
   Password: $defaultPassword

2. In SLP2 > Streaming > RTSP:
   Enable RTSP server on port $rtspPort

3. App connects to: rtsp://$defaultSlp2Ip:$rtspPort/video
''';
  }
}
