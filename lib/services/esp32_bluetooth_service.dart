import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class Esp32BluetoothService {
  BluetoothConnection? _connection;
  final StreamController<Uint8List> _imageStreamController =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get imageStream => _imageStreamController.stream;

  // Check if Bluetooth is enabled
  Future<bool> isBluetoothEnabled() async {
    try {
      final state = await FlutterBluetoothSerial.instance.state;
      return state == BluetoothState.STATE_ON;
    } catch (e) {
      return false;
    }
  }

  // Request to enable Bluetooth
  Future<bool> requestEnableBluetooth() async {
    try {
      await FlutterBluetoothSerial.instance.requestEnable();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Get paired Bluetooth devices
  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return devices.toList();
    } catch (e) {
      return [];
    }
  }

  // Connect to ESP32 CAM
  Future<bool> connect(String address) async {
    try {
      _connection = await BluetoothConnection.toAddress(address);

      // Listen to incoming data
      _connection!.input!.listen(
        (Uint8List data) {
          _processIncomingData(data);
        },
        onDone: () {
          disconnect();
        },
        onError: (error) {
          disconnect();
        },
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  List<int> _buffer = [];
  static const int jpegStartMarker = 0xFFD8; // JPEG start marker
  static const int jpegEndMarker = 0xFFD9; // JPEG end marker

  void _processIncomingData(Uint8List data) {
    _buffer.addAll(data);

    // Look for JPEG start and end markers
    while (_buffer.length > 2) {
      // Find JPEG start
      int startIndex = -1;
      for (int i = 0; i < _buffer.length - 1; i++) {
        if (_buffer[i] == 0xFF && _buffer[i + 1] == 0xD8) {
          startIndex = i;
          break;
        }
      }

      if (startIndex == -1) {
        // No start marker found, clear buffer
        _buffer.clear();
        break;
      }

      // Remove data before start marker
      if (startIndex > 0) {
        _buffer.removeRange(0, startIndex);
      }

      // Find JPEG end
      int endIndex = -1;
      for (int i = 1; i < _buffer.length - 1; i++) {
        if (_buffer[i] == 0xFF && _buffer[i + 1] == 0xD9) {
          endIndex = i + 2; // Include the end marker
          break;
        }
      }

      if (endIndex == -1) {
        // No end marker yet, wait for more data
        break;
      }

      // Extract complete JPEG image
      final imageData = Uint8List.fromList(_buffer.sublist(0, endIndex));
      _imageStreamController.add(imageData);

      // Remove processed image from buffer
      _buffer.removeRange(0, endIndex);
    }
  }

  // Start streaming from ESP32 CAM
  Future<void> startStreaming() async {
    try {
      if (_connection != null && _connection!.isConnected) {
        // Send command to ESP32 to start streaming
        _connection!.output.add(Uint8List.fromList('START'.codeUnits));
        await _connection!.output.allSent;
      }
    } catch (e) {
      // Error starting stream
    }
  }

  // Stop streaming
  Future<void> stopStreaming() async {
    try {
      if (_connection != null && _connection!.isConnected) {
        _connection!.output.add(Uint8List.fromList('STOP'.codeUnits));
        await _connection!.output.allSent;
      }
    } catch (e) {
      // Error stopping stream
    }
  }

  // Disconnect from ESP32 CAM
  void disconnect() {
    _connection?.dispose();
    _connection = null;
    _buffer.clear();
  }

  // Dispose resources
  void dispose() {
    disconnect();
    _imageStreamController.close();
  }
}
