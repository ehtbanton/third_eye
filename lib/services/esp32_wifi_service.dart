import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Service for connecting to ESP32-CAM via WiFi WebSocket
/// The ESP32-CAM runs in SoftAP mode at 192.168.4.1
/// and streams JPEG frames via WebSocket at ws://192.168.4.1/ws
class Esp32WifiService {
  WebSocketChannel? _channel;
  bool _isConnected = false;

  final _imageStreamController = StreamController<Uint8List>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  /// Stream of JPEG image frames from ESP32-CAM
  Stream<Uint8List> get imageStream => _imageStreamController.stream;

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Check if connected to ESP32-CAM
  bool get isConnected => _isConnected;

  /// Connect to ESP32-CAM WebSocket
  /// The ESP32 is expected to be at ws://192.168.4.1/ws
  Future<bool> connect({String esp32Ip = '192.168.4.1'}) async {
    try {
      print('Connecting to ESP32-CAM at ws://$esp32Ip/ws...');

      // Disconnect if already connected
      if (_isConnected) {
        await disconnect();
      }

      // Connect to WebSocket
      final wsUrl = Uri.parse('ws://$esp32Ip/ws');
      _channel = WebSocketChannel.connect(wsUrl);

      // Wait for connection to establish (with timeout)
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Connection timeout after 10 seconds');
        },
      );

      _isConnected = true;
      _connectionStateController.add(true);
      print('✓ Connected to ESP32-CAM WebSocket');

      // Listen to incoming WebSocket messages (binary JPEG frames)
      _channel!.stream.listen(
        (data) {
          if (data is Uint8List) {
            // Binary data = JPEG frame
            _imageStreamController.add(data);
          } else if (data is List<int>) {
            // Convert List<int> to Uint8List
            _imageStreamController.add(Uint8List.fromList(data));
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('WebSocket connection closed');
          _handleDisconnect();
        },
        cancelOnError: false,
      );

      return true;
    } catch (e) {
      print('✗ Failed to connect to ESP32-CAM: $e');
      _isConnected = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  /// Disconnect from ESP32-CAM
  Future<void> disconnect() async {
    print('Disconnecting from ESP32-CAM...');
    _isConnected = false;
    _connectionStateController.add(false);

    await _channel?.sink.close();
    _channel = null;

    print('✓ Disconnected from ESP32-CAM');
  }

  /// Handle unexpected disconnect
  void _handleDisconnect() {
    if (_isConnected) {
      _isConnected = false;
      _connectionStateController.add(false);
      _channel = null;
      print('ESP32-CAM disconnected unexpectedly');
    }
  }

  /// Send a control command to ESP32 (optional feature)
  /// You can extend the ESP32 Arduino code to handle text commands
  void sendCommand(String command) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(command);
      print('Sent command to ESP32: $command');
    } else {
      print('Cannot send command: Not connected to ESP32');
    }
  }

  /// Dispose of resources
  void dispose() {
    print('Disposing Esp32WifiService...');
    disconnect();
    _imageStreamController.close();
    _connectionStateController.close();
  }
}
