import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Service to handle Bluetooth clicker connections and button press events
class BluetoothClickerService {
  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _dataSubscription;
  bool _isConnected = false;

  // Stream controller for button press events
  final StreamController<ClickerEvent> _clickEventController =
      StreamController<ClickerEvent>.broadcast();

  Stream<ClickerEvent> get clickStream => _clickEventController.stream;

  bool get isConnected => _isConnected;

  /// Get list of bonded Bluetooth devices
  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return devices.toList();
    } catch (e) {
      print('Error getting paired devices: $e');
      return [];
    }
  }

  /// Connect to Bluetooth clicker by device address
  Future<bool> connect(String address) async {
    try {
      print('=== Starting Bluetooth Clicker Connection ===');
      print('Target device address: $address');

      // Check if Bluetooth is enabled
      final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      print('Bluetooth enabled: $isEnabled');
      if (isEnabled != true) {
        print('ERROR: Bluetooth is not enabled');
        return false;
      }

      // Disconnect if already connected
      if (_isConnected) {
        print('Already connected, disconnecting first...');
        await disconnect();
      }

      print('Attempting to connect to Bluetooth clicker at $address...');

      // Add timeout to connection attempt
      _connection = await BluetoothConnection.toAddress(address).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('ERROR: Connection timeout after 10 seconds');
          throw Exception('Connection timeout - device may be out of range or not ready');
        },
      );

      print('Connection object created successfully');
      _isConnected = true;

      // Verify connection is actually established
      if (_connection == null || !_connection!.isConnected) {
        print('ERROR: Connection object exists but not connected');
        _isConnected = false;
        return false;
      }

      print('Connection verified, setting up data listener...');

      // Listen for incoming data (button presses)
      _dataSubscription = _connection!.input!.listen(
        _handleIncomingData,
        onDone: () {
          print('Bluetooth clicker connection closed gracefully');
          _isConnected = false;
          _connection = null;
        },
        onError: (error) {
          print('ERROR: Bluetooth clicker connection error: $error');
          _isConnected = false;
        },
      );

      print('=== Successfully connected to Bluetooth clicker ===');
      print('Connection established and listening for button presses');
      return true;
    } catch (e, stackTrace) {
      print('=== ERROR: Failed to connect to Bluetooth clicker ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      _isConnected = false;
      _connection = null;
      return false;
    }
  }

  /// Handle incoming data from Bluetooth clicker
  void _handleIncomingData(Uint8List data) {
    // Most Bluetooth clickers send simple byte codes for button presses
    // Common patterns:
    // - Single byte: 0x01 for button press
    // - HID keyboard codes: Volume up/down, play/pause, camera shutter
    // - Custom codes depending on the clicker model

    print('=== Received data from clicker ===');
    print('Data length: ${data.length} bytes');
    print('Raw bytes (hex): ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
    print('Raw bytes (decimal): ${data.join(' ')}');

    for (int i = 0; i < data.length; i++) {
      int byte = data[i];

      // Detect button press patterns
      ClickerEvent? event = _detectButtonPress(byte, data, i);
      if (event != null) {
        print('✓ Button press detected: ${event.buttonType}');
        _clickEventController.add(event);
      }
    }
  }

  /// Detect button press from byte data
  /// Supports multiple clicker types and protocols
  ClickerEvent? _detectButtonPress(int byte, Uint8List data, int index) {
    // Pattern 1: Simple single-byte commands
    if (byte == 0x01 || byte == 0x81) {
      return ClickerEvent(buttonType: ButtonType.primary, timestamp: DateTime.now());
    }

    // Pattern 2: Android media button (Volume Up)
    if (byte == 0xE9 || byte == 0x42) {
      return ClickerEvent(buttonType: ButtonType.volumeUp, timestamp: DateTime.now());
    }

    // Pattern 3: Android media button (Volume Down)
    if (byte == 0xEA || byte == 0x43) {
      return ClickerEvent(buttonType: ButtonType.volumeDown, timestamp: DateTime.now());
    }

    // Pattern 4: Camera shutter button
    if (byte == 0x58 || byte == 0xB1) {
      return ClickerEvent(buttonType: ButtonType.shutter, timestamp: DateTime.now());
    }

    // Pattern 5: Enter/OK button
    if (byte == 0x0D || byte == 0x28) {
      return ClickerEvent(buttonType: ButtonType.enter, timestamp: DateTime.now());
    }

    // Pattern 6: Space bar (common for presentation clickers)
    if (byte == 0x20) {
      return ClickerEvent(buttonType: ButtonType.space, timestamp: DateTime.now());
    }

    // Pattern 7: Check for HID keyboard report format (if data length >= 8)
    if (data.length >= 8 && index == 2) {
      // HID keyboard reports have format: [modifier, reserved, key1, key2, ...]
      if (byte != 0x00) {
        return ClickerEvent(buttonType: ButtonType.keyboard, timestamp: DateTime.now(), keyCode: byte);
      }
    }

    return null;
  }

  /// Disconnect from Bluetooth clicker
  Future<void> disconnect() async {
    try {
      await _dataSubscription?.cancel();
      _dataSubscription = null;

      await _connection?.close();
      _connection = null;

      _isConnected = false;

      print('Disconnected from Bluetooth clicker');
    } catch (e) {
      print('Error during disconnect: $e');
    }
  }

  /// Check if Bluetooth is enabled on device
  Future<bool> isBluetoothEnabled() async {
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    return isEnabled ?? false;
  }

  /// Request to enable Bluetooth
  Future<bool> requestEnableBluetooth() async {
    try {
      final result = await FlutterBluetoothSerial.instance.requestEnable();
      return result ?? false;
    } catch (e) {
      print('Error requesting Bluetooth enable: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _clickEventController.close();
  }
}

/// Types of buttons that can be pressed on a clicker
enum ButtonType {
  primary,
  volumeUp,
  volumeDown,
  shutter,
  enter,
  space,
  keyboard,
  unknown,
}

/// Event emitted when a button is pressed on the clicker
class ClickerEvent {
  final ButtonType buttonType;
  final DateTime timestamp;
  final int? keyCode;

  ClickerEvent({
    required this.buttonType,
    required this.timestamp,
    this.keyCode,
  });

  @override
  String toString() {
    return 'ClickerEvent(buttonType: $buttonType, timestamp: $timestamp, keyCode: $keyCode)';
  }
}
