import 'dart:async';
import 'package:flutter/services.dart';

enum HardwareKeyType {
  volumeUp,
  volumeDown,
  other,
}

class HardwareKeyEvent {
  final HardwareKeyType keyType;
  final DateTime timestamp;

  HardwareKeyEvent(this.keyType) : timestamp = DateTime.now();
}

class HardwareKeyService {
  final _keyStreamController = StreamController<HardwareKeyEvent>.broadcast();
  bool _isListening = false;

  Stream<HardwareKeyEvent> get keyStream => _keyStreamController.stream;
  bool get isListening => _isListening;

  void startListening() {
    if (_isListening) return;

    _isListening = true;

    // Register handler for hardware key events
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent event) {
    // Only respond to key down events
    if (event is! KeyDownEvent) return false;

    HardwareKeyType? keyType;

    // Map physical keys to our key types
    if (event.physicalKey == PhysicalKeyboardKey.audioVolumeUp) {
      keyType = HardwareKeyType.volumeUp;
    } else if (event.physicalKey == PhysicalKeyboardKey.audioVolumeDown) {
      keyType = HardwareKeyType.volumeDown;
    } else {
      // For other keys that might come from Bluetooth clickers
      keyType = HardwareKeyType.other;
    }

    if (keyType != null && !_keyStreamController.isClosed) {
      print('Hardware key detected: $keyType');
      _keyStreamController.add(HardwareKeyEvent(keyType));

      // Return true for volume keys to prevent system from changing actual volume
      if (keyType == HardwareKeyType.volumeUp || keyType == HardwareKeyType.volumeDown) {
        return true;
      }
    }

    // Return false to allow the system to also handle the key
    return false;
  }

  void stopListening() {
    if (!_isListening) return;

    _isListening = false;
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
  }

  void dispose() {
    stopListening();
    _keyStreamController.close();
  }
}
