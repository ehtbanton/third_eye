import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Service for BLE communication with CM4
/// Handles commands, configuration, and audio uplink
class Cm4BleService {
  // CM4 BLE UUIDs
  static const String serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const String commandCharUuid = '12345678-1234-5678-1234-56789abcdef1';
  static const String responseCharUuid = '12345678-1234-5678-1234-56789abcdef2';
  static const String terminalInUuid = '12345678-1234-5678-1234-56789abcdef3';
  static const String terminalOutUuid = '12345678-1234-5678-1234-56789abcdef4';
  static const String audioDataUuid = '12345678-1234-5678-1234-56789abcdef5';
  static const String configCharUuid = '12345678-1234-5678-1234-56789abcdef6';

  // Device info
  static const String deviceName = 'ThirdEye_CM4';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _responseChar;
  BluetoothCharacteristic? _audioChar;

  // Stream controllers
  final StreamController<String> _responseController =
      StreamController<String>.broadcast();
  final StreamController<ConnectionState> _connectionController =
      StreamController<ConnectionState>.broadcast();

  Stream<String> get responseStream => _responseController.stream;
  Stream<ConnectionState> get connectionStream =>
      _connectionController.stream;

  ConnectionState _connectionState = ConnectionState.disconnected;
  ConnectionState get connectionState => _connectionState;

  bool get isConnected =>
      _connectionState == ConnectionState.connected;

  /// Scan for CM4 device
  Future<List<ScanResult>> scanForCM4({Duration timeout = const Duration(seconds: 10)}) async {
    debugPrint('Cm4BleService: Starting scan for $deviceName...');

    final results = <ScanResult>[];
    final completer = Completer<List<ScanResult>>();

    // Start scanning
    await FlutterBluePlus.startScan(timeout: timeout);

    // Listen for scan results
    final subscription = FlutterBluePlus.scanResults.listen((scanResults) {
      for (var result in scanResults) {
        if (result.device.platformName == deviceName) {
          if (!results.any((r) => r.device.remoteId == result.device.remoteId)) {
            results.add(result);
            debugPrint('Cm4BleService: Found $deviceName - ${result.device.remoteId}');
          }
        }
      }
    });

    // Wait for timeout
    await Future.delayed(timeout);
    await FlutterBluePlus.stopScan();
    await subscription.cancel();

    debugPrint('Cm4BleService: Scan complete. Found ${results.length} device(s)');
    return results;
  }

  /// Connect to CM4 device
  Future<bool> connect(BluetoothDevice device) async {
    try {
      debugPrint('Cm4BleService: Connecting to ${device.platformName}...');
      _updateConnectionState(ConnectionState.connecting);

      _device = device;

      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15));
      debugPrint('Cm4BleService: Connected successfully');

      // Discover services
      debugPrint('Cm4BleService: Discovering services...');
      final services = await device.discoverServices();

      // Find Third Eye service
      final service = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase(),
        orElse: () => throw Exception('Third Eye service not found'),
      );

      debugPrint('Cm4BleService: Found Third Eye service');

      // Get characteristics
      _commandChar = service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == commandCharUuid.toLowerCase(),
        orElse: () => throw Exception('Command characteristic not found'),
      );

      _responseChar = service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == responseCharUuid.toLowerCase(),
        orElse: () => throw Exception('Response characteristic not found'),
      );

      _audioChar = service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == audioDataUuid.toLowerCase(),
        orElse: () => throw Exception('Audio characteristic not found'),
      );

      debugPrint('Cm4BleService: All characteristics found');

      // Enable notifications for responses
      await _responseChar!.setNotifyValue(true);
      _responseChar!.lastValueStream.listen((value) {
        final response = utf8.decode(value);
        debugPrint('Cm4BleService: Response received: $response');
        _responseController.add(response);
      });

      _updateConnectionState(ConnectionState.connected);
      debugPrint('Cm4BleService: Setup complete');

      return true;
    } catch (e) {
      debugPrint('Cm4BleService: Connection failed: $e');
      _updateConnectionState(ConnectionState.error);
      await disconnect();
      return false;
    }
  }

  /// Send command to CM4
  Future<bool> sendCommand(String command) async {
    if (_commandChar == null) {
      debugPrint('Cm4BleService: Not connected');
      return false;
    }

    try {
      debugPrint('Cm4BleService: Sending command: $command');
      final data = utf8.encode(command);
      await _commandChar!.write(data, withoutResponse: true);
      return true;
    } catch (e) {
      debugPrint('Cm4BleService: Failed to send command: $e');
      return false;
    }
  }

  /// Control WiFi AP
  Future<bool> startWiFi() async {
    return await sendCommand('WIFI_START');
  }

  Future<bool> stopWiFi() async {
    return await sendCommand('WIFI_STOP');
  }

  Future<bool> getWiFiStatus() async {
    return await sendCommand('WIFI_STATUS');
  }

  /// Control Camera Server
  Future<bool> startCamera() async {
    return await sendCommand('CAMERA_START');
  }

  Future<bool> stopCamera() async {
    return await sendCommand('CAMERA_STOP');
  }

  /// Get system status
  Future<bool> getStatus() async {
    return await sendCommand('STATUS');
  }

  /// Reboot CM4
  Future<bool> reboot() async {
    return await sendCommand('REBOOT');
  }

  /// Send audio data to CM4
  Future<bool> sendAudio(Uint8List audioData) async {
    if (_audioChar == null) {
      debugPrint('Cm4BleService: Not connected');
      return false;
    }

    try {
      // BLE has MTU limit, send in chunks
      const chunkSize = 512;
      for (int i = 0; i < audioData.length; i += chunkSize) {
        final end = (i + chunkSize < audioData.length)
            ? i + chunkSize
            : audioData.length;
        final chunk = audioData.sublist(i, end);
        await _audioChar!.write(chunk, withoutResponse: true);
      }
      return true;
    } catch (e) {
      debugPrint('Cm4BleService: Failed to send audio: $e');
      return false;
    }
  }

  /// Disconnect from CM4
  Future<void> disconnect() async {
    if (_device != null) {
      debugPrint('Cm4BleService: Disconnecting...');
      try {
        await _device!.disconnect();
      } catch (e) {
        debugPrint('Cm4BleService: Disconnect error: $e');
      }
      _device = null;
      _commandChar = null;
      _responseChar = null;
      _audioChar = null;
      _updateConnectionState(ConnectionState.disconnected);
    }
  }

  void _updateConnectionState(ConnectionState state) {
    _connectionState = state;
    _connectionController.add(state);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await disconnect();
    await _responseController.close();
    await _connectionController.close();
  }
}

/// Connection states
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}
