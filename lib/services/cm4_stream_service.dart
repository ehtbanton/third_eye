import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

enum CameraFeed { left, right, eye }

enum Cm4ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class Cm4StreamService {
  // CM4 configuration
  static const String defaultIp = '192.168.50.1';
  static const Map<CameraFeed, int> cameraPorts = {
    CameraFeed.left: 8081,
    CameraFeed.right: 8082,
    CameraFeed.eye: 8083,
  };

  // Stream controllers for each camera
  final Map<CameraFeed, StreamController<Uint8List>> _imageControllers = {};
  final Map<CameraFeed, StreamController<Cm4ConnectionState>>
      _stateControllers = {};

  // HTTP clients for each camera
  final Map<CameraFeed, http.Client> _httpClients = {};
  final Map<CameraFeed, StreamSubscription?> _subscriptions = {};

  // FPS tracking
  final Map<CameraFeed, DateTime> _lastFrameTime = {};
  final Map<CameraFeed, double> _currentFps = {};

  String _cm4Ip = defaultIp;
  bool _isInitialized = false;

  Cm4StreamService() {
    _initialize();
  }

  void _initialize() {
    for (var camera in CameraFeed.values) {
      _imageControllers[camera] =
          StreamController<Uint8List>.broadcast();
      _stateControllers[camera] =
          StreamController<Cm4ConnectionState>.broadcast();
      _httpClients[camera] = http.Client();
      _currentFps[camera] = 0.0;
    }
    _isInitialized = true;
  }

  /// Get image stream for a specific camera
  Stream<Uint8List> getImageStream(CameraFeed camera) {
    return _imageControllers[camera]!.stream;
  }

  /// Get connection state stream for a specific camera
  Stream<Cm4ConnectionState> getConnectionStateStream(CameraFeed camera) {
    return _stateControllers[camera]!.stream;
  }

  /// Get current FPS for a specific camera
  double getFps(CameraFeed camera) {
    return _currentFps[camera] ?? 0.0;
  }

  /// Connect to all CM4 cameras
  Future<void> connectAll({String? cm4Ip}) async {
    if (cm4Ip != null) {
      _cm4Ip = cm4Ip;
    }

    debugPrint('CM4StreamService: Connecting to all cameras at $_cm4Ip');

    for (var camera in CameraFeed.values) {
      await connect(camera);
    }
  }

  /// Connect to a specific camera
  Future<void> connect(CameraFeed camera, {String? cm4Ip}) async {
    if (cm4Ip != null) {
      _cm4Ip = cm4Ip;
    }

    final port = cameraPorts[camera]!;
    final url = 'http://$_cm4Ip:$port/stream';

    debugPrint('CM4StreamService: Connecting to ${camera.name} at $url');
    _updateState(camera, Cm4ConnectionState.connecting);

    try {
      // Cancel existing subscription
      await _subscriptions[camera]?.cancel();

      // Create new HTTP request
      final request = http.Request('GET', Uri.parse(url));
      final response = await _httpClients[camera]!.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      debugPrint('CM4StreamService: Connected to ${camera.name}');
      _updateState(camera, Cm4ConnectionState.connected);

      // Parse MJPEG multipart stream
      _subscriptions[camera] = response.stream.listen(
        (chunk) => _processMjpegChunk(camera, chunk),
        onError: (error) {
          debugPrint('CM4StreamService: ${camera.name} stream error: $error');
          _updateState(camera, Cm4ConnectionState.error);
        },
        onDone: () {
          debugPrint('CM4StreamService: ${camera.name} stream ended');
          _updateState(camera, Cm4ConnectionState.disconnected);
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('CM4StreamService: Failed to connect to ${camera.name}: $e');
      _updateState(camera, Cm4ConnectionState.error);
    }
  }

  // Buffer for accumulating MJPEG data
  final Map<CameraFeed, BytesBuilder> _buffers = {};
  final Map<CameraFeed, bool> _inFrame = {};

  void _processMjpegChunk(CameraFeed camera, List<int> chunk) {
    // Initialize buffer if needed
    _buffers[camera] ??= BytesBuilder();
    _inFrame[camera] ??= false;

    _buffers[camera]!.add(chunk);
    final data = _buffers[camera]!.toBytes();

    // Look for JPEG markers
    // JPEG start: 0xFF 0xD8
    // JPEG end: 0xFF 0xD9

    int searchStart = 0;
    while (true) {
      if (!_inFrame[camera]!) {
        // Look for JPEG start marker
        final startIndex = _findJpegStart(data, searchStart);
        if (startIndex == -1) {
          // No start marker found, keep last 2 bytes in case marker spans chunks
          if (data.length > 2) {
            _buffers[camera] = BytesBuilder()
              ..add(data.sublist(data.length - 2));
          }
          break;
        }

        _inFrame[camera] = true;
        searchStart = startIndex;
      }

      if (_inFrame[camera]!) {
        // Look for JPEG end marker
        final endIndex = _findJpegEnd(data, searchStart + 2);
        if (endIndex == -1) {
          // No end marker yet, wait for more data
          break;
        }

        // Extract complete JPEG frame
        final frameData = Uint8List.fromList(
          data.sublist(searchStart, endIndex + 2),
        );

        // Emit frame
        _imageControllers[camera]!.add(frameData);
        _updateFps(camera);

        // Remove processed data from buffer
        _buffers[camera] = BytesBuilder()
          ..add(data.sublist(endIndex + 2));

        _inFrame[camera] = false;
        searchStart = 0;

        // Re-get data for next iteration
        final newData = _buffers[camera]!.toBytes();
        if (newData.isEmpty) break;

        // Continue searching in remaining data
        _buffers[camera] = BytesBuilder()..add(newData);
      }
    }
  }

  int _findJpegStart(Uint8List data, int offset) {
    for (int i = offset; i < data.length - 1; i++) {
      if (data[i] == 0xFF && data[i + 1] == 0xD8) {
        return i;
      }
    }
    return -1;
  }

  int _findJpegEnd(Uint8List data, int offset) {
    for (int i = offset; i < data.length - 1; i++) {
      if (data[i] == 0xFF && data[i + 1] == 0xD9) {
        return i;
      }
    }
    return -1;
  }

  void _updateFps(CameraFeed camera) {
    final now = DateTime.now();
    if (_lastFrameTime.containsKey(camera)) {
      final elapsed = now.difference(_lastFrameTime[camera]!).inMilliseconds;
      if (elapsed > 0) {
        // Exponential moving average for smooth FPS display
        final instantFps = 1000.0 / elapsed;
        _currentFps[camera] =
            (_currentFps[camera]! * 0.9) + (instantFps * 0.1);
      }
    }
    _lastFrameTime[camera] = now;
  }

  void _updateState(CameraFeed camera, Cm4ConnectionState state) {
    _stateControllers[camera]!.add(state);
  }

  /// Disconnect from a specific camera
  Future<void> disconnect(CameraFeed camera) async {
    debugPrint('CM4StreamService: Disconnecting ${camera.name}');
    await _subscriptions[camera]?.cancel();
    _subscriptions[camera] = null;
    _buffers.remove(camera);
    _inFrame.remove(camera);
    _currentFps[camera] = 0.0;
    _updateState(camera, Cm4ConnectionState.disconnected);
  }

  /// Disconnect from all cameras
  Future<void> disconnectAll() async {
    debugPrint('CM4StreamService: Disconnecting all cameras');
    for (var camera in CameraFeed.values) {
      await disconnect(camera);
    }
  }

  /// Check if a specific camera is connected
  bool isConnected(CameraFeed camera) {
    return _subscriptions[camera] != null;
  }

  /// Check if all cameras are connected
  bool get areAllConnected {
    return CameraFeed.values.every((camera) => isConnected(camera));
  }

  /// Get stats for a specific camera (from CM4 server)
  Future<Map<String, dynamic>?> getStats(CameraFeed camera) async {
    try {
      final port = cameraPorts[camera]!;
      final url = 'http://$_cm4Ip:$port/stats';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.body as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('CM4StreamService: Failed to get stats for ${camera.name}: $e');
    }
    return null;
  }

  /// Dispose all resources
  Future<void> dispose() async {
    debugPrint('CM4StreamService: Disposing');
    await disconnectAll();

    for (var camera in CameraFeed.values) {
      await _imageControllers[camera]?.close();
      await _stateControllers[camera]?.close();
      _httpClients[camera]?.close();
    }

    _imageControllers.clear();
    _stateControllers.clear();
    _httpClients.clear();
    _subscriptions.clear();
    _buffers.clear();
    _inFrame.clear();
    _lastFrameTime.clear();
    _currentFps.clear();
  }
}
