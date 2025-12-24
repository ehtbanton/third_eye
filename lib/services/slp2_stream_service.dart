import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Service for connecting to StereoPi SLP2 via RTSP stream.
class Slp2StreamService {
  static const String defaultSsid = 'cosmostreamer';
  static const String defaultPassword = '1234512345';
  static const String defaultSlp2Ip = '192.168.50.1';
  static const int rtspPort = 554;

  String _slp2Ip = defaultSlp2Ip;
  Player? _player;
  VideoController? _videoController;
  bool _isConnected = false;

  final _connectionStateController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  bool get isConnected => _isConnected;
  VideoController? get videoController => _videoController;

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
    debugPrint('SLP2: Connecting to $url');
    debugPrint('======================================');

    try {
      // Create player and video controller
      _player = Player();
      _videoController = VideoController(_player!);

      // Open the RTSP stream
      await _player!.open(Media(url));

      _isConnected = true;
      _connectionStateController.add(true);
      debugPrint('SLP2: Connected successfully');

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

1. Connect your phone to SLP2's WiFi:
   SSID: $defaultSsid
   Password: $defaultPassword

2. Enable RTSP in SLP2 web interface

3. The app will connect to:
   rtsp://$defaultSlp2Ip:$rtspPort/video
''';
  }
}
